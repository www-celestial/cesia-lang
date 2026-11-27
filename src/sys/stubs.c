/* What OCaml's unix library doesn't offer: the epoll system calls, loading C libraries, the size of the RAM, the memory a
   process holds and the space of a file system, and a command started in a process group of its own, and closing
   every descriptor from one on. */
#include <caml/alloc.h>
#include <caml/bigarray.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/signals.h>
#include <stdio.h>

_Static_assert(sizeof(void *) == 8, "Cesia needs 64 bits.");

#ifdef _WIN32
#include <string.h>
#include <windows.h>
/* A full path loads the DLLs it needs from its own folder first, as $ORIGIN and @loader_path do elsewhere: libssl of lib/
   finds the libcrypto beside it, not the one beside cesia.exe or on the PATH. Windows reads that path only with
   backslashes, and its behaviour for a relative one is undefined: a bare name or a relative path is searched as usual. */
static void *open_library(const char *name) {
  char path[MAX_PATH];
  size_t n = strlen(name);
  int full = (n > 2 && name[1] == ':' && (name[2] == '/' || name[2] == '\\')) ||
             (n > 1 && (name[0] == '/' || name[0] == '\\') && (name[1] == '/' || name[1] == '\\'));
  if (!full || n >= sizeof path) return (void *) LoadLibraryA(name);
  for (size_t i = 0; i <= n; i++) path[i] = name[i] == '/' ? '\\' : name[i];
  return (void *) LoadLibraryExA(path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
}
#define find_symbol(lib, name) ((void *) GetProcAddress((HMODULE) (lib), name))
/* K32GetProcessMemoryInfo, in kernel32 itself since Windows 7: no psapi.lib to link */
#define PSAPI_VERSION 2
#include <psapi.h>
#else
#include <dlfcn.h>
#include <sys/statvfs.h>
#include <unistd.h>
#ifdef __APPLE__
#include <mach/mach.h>
#endif
#define open_library(name) dlopen(name, RTLD_NOW | RTLD_LOCAL)
#define find_symbol(lib, name) dlsym(lib, name)
#endif

/* An address fits in an OCaml integer. 0 means that it failed. */
value cesia_dlopen(value name) { return Val_long((intnat) open_library(String_val(name))); }
value cesia_dlsym(value lib, value name) { return Val_long((intnat) find_symbol((void *) Long_val(lib), String_val(name))); }

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

/* The memory of this process that is in RAM now (its resident set) in bytes, or 0 if it can't be known. */
value cesia_rss(value unit) {
#if defined(_WIN32)
  PROCESS_MEMORY_COUNTERS counters;
  return Val_long(K32GetProcessMemoryInfo(GetCurrentProcess(), &counters, sizeof counters) ? (intnat) counters.WorkingSetSize : 0);
#elif defined(__APPLE__)
  struct mach_task_basic_info info;
  mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
  return Val_long(task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t) &info, &count) == KERN_SUCCESS ? (intnat) info.resident_size : 0);
#else
  long pages = 0, resident = 0, size = sysconf(_SC_PAGE_SIZE);
  FILE *f = fopen("/proc/self/statm", "r");
  if (f) {
    if (fscanf(f, "%ld %ld", &pages, &resident) != 2) resident = 0;
    fclose(f);
  }
  return Val_long(resident > 0 && size > 0 ? (intnat) resident * size : 0);
#endif
}

/* The bytes of the file system that holds a path: [|total; used; free to a program that isn't root|], or [|-1; 0; 0|]
   when the path can't be read. Used counts the blocks that root keeps too, as df does. */
value cesia_disk(value path) {
  CAMLparam1(path);
  CAMLlocal1(out);
  out = caml_alloc_tuple(3);
  intnat total = -1, used = 0, free = 0;
#ifdef _WIN32
  ULARGE_INTEGER avail, all, left;
  if (GetDiskFreeSpaceExA(String_val(path), &avail, &all, &left)) {
    total = (intnat) all.QuadPart;
    used = (intnat) (all.QuadPart - left.QuadPart);
    free = (intnat) avail.QuadPart;
  }
#else
  struct statvfs s;
  if (statvfs(String_val(path), &s) == 0) {
    total = (intnat) s.f_blocks * (intnat) s.f_frsize;
    used = (intnat) (s.f_blocks - s.f_bfree) * (intnat) s.f_frsize;
    free = (intnat) s.f_bavail * (intnat) s.f_frsize;
  }
#endif
  Store_field(out, 0, Val_long(total));
  Store_field(out, 1, Val_long(used));
  Store_field(out, 2, Val_long(free));
  CAMLreturn(out);
}

value cesia_block_address(value block) { return Val_long((intnat) Caml_ba_data_val(block)); }

/* The n bytes at an address, zero bytes too: SQLite's texts and BLOBs. */
value cesia_bytes(value address, value n) { return caml_alloc_initialized_string(Long_val(n), (const char *) Long_val(address)); }

/* sqlite3_db_config takes a variable argument list, which only a C call passes right on every system. */
value cesia_db_config(value fn, value db, value op, value on) {
  int (*config)(void *, int, ...) = (int (*)(void *, int, ...)) Long_val(fn);
  return Val_int(config((void *) Long_val(db), Int_val(op), Int_val(on), (int *) 0));
}

value cesia_cstring(value address) { return caml_copy_string((const char *) Long_val(address)); }

/* posix_spawnp with the child as the leader of a process group, which a timeout kills whole: the command and what it
   started. Its standard streams are fds[0..2]. Windows has no process groups: proc.ml never calls it there. */
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

/* Closes every descriptor from [first] on: at once where Linux has close_range, else one by one up to the limit. */
#include <sys/syscall.h>
value cesia_close_from(value first) {
#ifdef SYS_close_range
  if (syscall(SYS_close_range, Int_val(first), ~0U, 0) == 0) return Val_unit;
#endif
  for (long fd = Int_val(first), n = sysconf(_SC_OPEN_MAX); fd < n; fd++) close(fd);
  return Val_unit;
}

/* What fs.ml walks and acts with, by descriptors: a name opened from a folder open above it (-1: the current one), with
   the flags of [how], bits in the order of [open_flags]; with bit 9, by openat2 (Linux 5.6+), RESOLVE_BENEATH |
   RESOLVE_NO_MAGICLINKS, which refuses in the same call, with EXDEV, a walk that leaves the folder, by .., a link or a
   mount, and gives ENOSYS where the system has none. Then a name removed, made a folder, made a link or renamed in an
   open folder, a link read, the names a folder holds, the mode and times of an open file given to another, and its
   bytes copied in the kernel. */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#if defined(__linux__) && __has_include(<linux/openat2.h>)
#include <linux/openat2.h>
#endif
#ifndef O_PATH
#define O_PATH O_RDONLY
#endif
#ifdef __APPLE__
#define st_atim st_atimespec
#define st_mtim st_mtimespec
#endif
#define AT(dir) (Int_val(dir) < 0 ? AT_FDCWD : Int_val(dir))
static const int open_flags[] = { O_WRONLY, O_CREAT, O_TRUNC, O_APPEND, O_EXCL, O_NOFOLLOW, O_NONBLOCK, O_DIRECTORY, O_PATH };
value cesia_open_at(value dir, value name, value how, value mode) {
  CAMLparam4(dir, name, how, mode);
  int f = O_CLOEXEC, d = AT(dir), h = Int_val(how), m = Int_val(mode), fd = -1;
  for (int i = 0; i < 9; i++) if (h & 1 << i) f |= open_flags[i];
  char *path = caml_stat_strdup(String_val(name));
  caml_enter_blocking_section();
  if (!(h & 1 << 9)) fd = openat(d, path, f, m);
#if defined(SYS_openat2) && defined(RESOLVE_BENEATH)
  else {
    struct open_how o = { .flags = f, .mode = f & O_CREAT ? m : 0, .resolve = RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS }; int tries = 8;
    do fd = syscall(SYS_openat2, d, path, &o, sizeof o); while (fd < 0 && errno == EAGAIN && --tries);
  }
#else
  else errno = ENOSYS;
#endif
  int e = errno;
  caml_leave_blocking_section();
  caml_stat_free(path);
  if (fd < 0) caml_unix_error(e, "open", name);
  CAMLreturn(Val_int(fd));
}
value cesia_unlink_at(value dir, value name, value folder) {
  if (unlinkat(AT(dir), String_val(name), Bool_val(folder) ? AT_REMOVEDIR : 0) < 0) caml_unix_error(errno, "remove", name);
  return Val_unit;
}
value cesia_mkdir_at(value dir, value name, value mode) {
  if (mkdirat(AT(dir), String_val(name), Int_val(mode)) < 0) caml_unix_error(errno, "mkdir", name);
  return Val_unit;
}
value cesia_symlink_at(value target, value dir, value name) {
  if (symlinkat(String_val(target), AT(dir), String_val(name)) < 0) caml_unix_error(errno, "symlink", name);
  return Val_unit;
}
value cesia_rename_at(value dir, value from, value to) {
  if (renameat(AT(dir), String_val(from), AT(dir), String_val(to)) < 0) caml_unix_error(errno, "rename", to);
  return Val_unit;
}
value cesia_readlink_at(value dir, value name) {
  char target[4096];
  ssize_t n = readlinkat(AT(dir), String_val(name), target, sizeof target);
  if (n < 0 || n == sizeof target) caml_unix_error(n < 0 ? errno : ENAMETOOLONG, "readlink", name);
  return caml_alloc_initialized_string(n, target);
}
value cesia_names(value dir) {
  CAMLparam1(dir);
  CAMLlocal3(out, cell, name);
  int fd = dup(Int_val(dir));
  DIR *d = fd < 0 ? NULL : fdopendir(fd);
  if (!d) { if (fd >= 0) close(fd); caml_unix_error(errno, "list", Nothing); }
  out = Val_emptylist;
  struct dirent *e;
  while ((errno = 0, e = readdir(d)))
    if (strcmp(e->d_name, ".") && strcmp(e->d_name, "..")) {
      name = caml_copy_string(e->d_name);
      cell = caml_alloc_small(2, 0);
      Field(cell, 0) = name;
      Field(cell, 1) = out;
      out = cell;
    }
  int failed = errno;
  closedir(d);
  if (failed) caml_unix_error(failed, "list", Nothing);
  CAMLreturn(out);
}
value cesia_copy_meta(value from, value to) {
  struct stat st;
  if (fstat(Int_val(from), &st) < 0 || fchmod(Int_val(to), st.st_mode & 07777) < 0) caml_unix_error(errno, "copy", Nothing);
  struct timespec times[2] = { st.st_atim, st.st_mtim };
  if (futimens(Int_val(to), times) < 0) caml_unix_error(errno, "copy", Nothing);
  return Val_unit;
}
/* The bytes of an open file into another, in the kernel, as cp does: copy_file_range, which btrfs makes a clone, until
   a copy of nothing past the size that fstat gave. False if it stops before, at a failure or at a copy of nothing, as
   for /proc: the reads and writes of fs.ml go on from there, and do it all on macOS, whose fcopyfile never clones. */
value cesia_copy_data(value from, value to, value size) {
  long n = -1, done = 0, want = Long_val(size);
#ifdef SYS_copy_file_range
  int in = Int_val(from), out = Int_val(to);
  caml_enter_blocking_section();
  while (want > 0 && (n = syscall(SYS_copy_file_range, in, NULL, out, NULL, want > done ? want - done : 65536, 0)) > 0) done += n;
  caml_leave_blocking_section();
#endif
  return Val_bool(n == 0 && done >= want);
}
#else
#include <caml/fail.h>
value cesia_spawn_group(value cmd, value args, value fds) { caml_failwith("no process groups on Windows"); }
value cesia_close_from(value first) { return Val_unit; }
#define BY_PATHS { caml_failwith("fs.ml walks by paths on Windows"); }
value cesia_open_at(value dir, value name, value how, value mode) BY_PATHS
value cesia_unlink_at(value dir, value name, value folder) BY_PATHS
value cesia_mkdir_at(value dir, value name, value mode) BY_PATHS
value cesia_symlink_at(value target, value dir, value name) BY_PATHS
value cesia_rename_at(value dir, value from, value to) BY_PATHS
value cesia_readlink_at(value dir, value name) BY_PATHS
value cesia_names(value dir) BY_PATHS
value cesia_copy_meta(value from, value to) BY_PATHS
value cesia_copy_data(value from, value to, value size) { return Val_false; }
#endif

#ifdef __linux__
#include <sys/epoll.h>

#define MAX_EVENTS 1024

value cesia_epoll_create(value unit) {
  return Val_int(epoll_create1(EPOLL_CLOEXEC));
}

/* how: 0 removes, 1 adds, 2 adds a listener, which wakes one of the processes that wait on it: the workers of a server. */
value cesia_epoll_ctl(value ep, value how, value fd) {
  struct epoll_event event;
  event.events = Int_val(how) == 2 ? EPOLLIN | EPOLLET | EPOLLEXCLUSIVE : EPOLLIN | EPOLLOUT | EPOLLRDHUP | EPOLLET;
  event.data.fd = Int_val(fd);
  int op = Int_val(how) ? EPOLL_CTL_ADD : EPOLL_CTL_DEL;
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
