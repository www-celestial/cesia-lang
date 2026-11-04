/* What OCaml's unix library doesn't offer: the epoll system calls, loading C libraries, and the size of the RAM. */
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

value cesia_cstring(value address) {
  return caml_copy_string((const char *) Long_val(address));
}

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
