/* What OCaml's unix library doesn't offer: the epoll system calls, loading C libraries, the size of the RAM, and a command
   started in a process group of its own. */
#include <caml/alloc.h>
#include <caml/bigarray.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/signals.h>
#include <stdio.h>

_Static_assert(sizeof(void *) == 8, "Cesia needs 64 bits.");

#ifdef _WIN32
#include <windows.h>
#define open_library(name) ((void *) LoadLibraryA(name))
#define find_symbol(lib, name) ((void *) GetProcAddress((HMODULE) (lib), name))
#else
#include <dlfcn.h>
#include <unistd.h>
#define open_library(name) dlopen(name, RTLD_NOW | RTLD_LOCAL)
#define find_symbol(lib, name) dlsym(lib, name)
#endif

/* An address fits in an OCaml integer. 0 means that it failed. */
value cesia_dlopen(value name) {
  return Val_long((intnat) open_library(String_val(name)));
}

value cesia_dlsym(value lib, value name) {
  return Val_long((intnat) find_symbol((void *) Long_val(lib), String_val(name)));
}

void *cesia_open(const char *name) { return open_library(name); }
void *cesia_symbol(void *lib, const char *name) { return find_symbol(lib, name); }

/* Why the last load failed. */
value cesia_dlerror(value unit) {
#ifdef _WIN32
  char text[32];
  snprintf(text, sizeof text, "error %lu", GetLastError());
  return caml_copy_string(text);
#else
  const char *text = dlerror();
  return caml_copy_string(text ? text : "unknown error");
#endif
}

/* The RAM of the machine in bytes, or 0 if it can't be known. */
value cesia_ram(value unit) {
#ifdef _WIN32
  MEMORYSTATUSEX status;
  status.dwLength = sizeof status;
  return Val_long(GlobalMemoryStatusEx(&status) ? (intnat) status.ullTotalPhys : 0);
#else
  long pages = sysconf(_SC_PHYS_PAGES), size = sysconf(_SC_PAGE_SIZE);
  return Val_long(pages > 0 && size > 0 ? (intnat) pages * size : 0);
#endif
}

value cesia_block_address(value block) {
  return Val_long((intnat) Caml_ba_data_val(block));
}

/* The n bytes at an address, zero bytes too: SQLite's texts and BLOBs. */
value cesia_bytes(value address, value n) {
  return caml_alloc_initialized_string(Long_val(n), (const char *) Long_val(address));
}

/* sqlite3_db_config takes a variable argument list, which only a C call passes right on every system. */
value cesia_db_config(value fn, value db, value op, value on) {
  int (*config)(void *, int, ...) = (int (*)(void *, int, ...)) Long_val(fn);
  return Val_int(config((void *) Long_val(db), Int_val(op), Int_val(on), (int *) 0));
}

value cesia_cstring(value address) {
  return caml_copy_string((const char *) Long_val(address));
}

/* posix_spawnp with the child as the leader of a process group, which a timeout kills whole: the command and what it
   started. Its standard streams are fds[0..2]; Windows has no process groups and never calls it. */
#ifndef _WIN32
#include <caml/unixsupport.h>
#include <spawn.h>
extern char **environ;

value cesia_spawn_group(value cmd, value args, value fds) {
  int n = Wosize_val(args), pid = 0;
  char **argv = caml_stat_alloc((n + 1) * sizeof(char *));
  for (int i = 0; i < n; i++) argv[i] = (char *) String_val(Field(args, i));
  argv[n] = NULL;
  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  for (int i = 0; i < 3; i++) posix_spawn_file_actions_adddup2(&actions, Int_val(Field(fds, i)), i);
  posix_spawnattr_t attr;
  posix_spawnattr_init(&attr);
  posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
  posix_spawnattr_setpgroup(&attr, 0);
  int failed = posix_spawnp(&pid, String_val(cmd), &actions, &attr, argv, environ);
  posix_spawn_file_actions_destroy(&actions);
  posix_spawnattr_destroy(&attr);
  caml_stat_free(argv);
  if (failed) caml_unix_error(failed, "create_process", cmd);
  return Val_int(pid);
}
#endif

#ifdef __linux__
#include <sys/epoll.h>

#define MAX_EVENTS 1024

value cesia_epoll_create(value unit) {
  return Val_int(epoll_create1(EPOLL_CLOEXEC));
}

value cesia_epoll_ctl(value ep, value add, value fd) {
  struct epoll_event event;
  event.events = EPOLLIN | EPOLLOUT | EPOLLRDHUP | EPOLLET;
  event.data.fd = Int_val(fd);
  int op = Bool_val(add) ? EPOLL_CTL_ADD : EPOLL_CTL_DEL;
  return Val_int(epoll_ctl(Int_val(ep), op, Int_val(fd), &event));
}

/* The descriptors go in [out], which holds at least MAX_EVENTS. Returns how many; 0 if a signal arrived. */
value cesia_epoll_wait(value ep, value out, value milliseconds) {
  CAMLparam1(out);
  struct epoll_event events[MAX_EVENTS];
  int epfd = Int_val(ep);
  int timeout = Int_val(milliseconds);
  caml_enter_blocking_section();
  int count = epoll_wait(epfd, events, MAX_EVENTS, timeout);
  caml_leave_blocking_section();
  if (count < 0) count = 0;
  for (int i = 0; i < count; i++) Field(out, i) = Val_int(events[i].data.fd);
  CAMLreturn(Val_int(count));
}
#endif
