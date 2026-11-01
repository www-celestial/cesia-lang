/* What OCaml's unix library doesn't offer: the epoll system calls, and loading C libraries. */
#include <caml/alloc.h>
#include <caml/bigarray.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/signals.h>
#include <stdio.h>

_Static_assert(sizeof(void *) == 8, "Kepler needs 64 bits.");

#ifdef _WIN32
#include <windows.h>
#define open_library(name) ((void *) LoadLibraryA(name))
#define find_symbol(lib, name) ((void *) GetProcAddress((HMODULE) (lib), name))
#else
#include <dlfcn.h>
#define open_library(name) dlopen(name, RTLD_NOW | RTLD_LOCAL)
#define find_symbol(lib, name) dlsym(lib, name)
#endif

/* An address fits in an OCaml integer. 0 means that it failed. */
value kepler_dlopen(value name) {
  return Val_long((intnat) open_library(String_val(name)));
}

value kepler_dlsym(value lib, value name) {
  return Val_long((intnat) find_symbol((void *) Long_val(lib), String_val(name)));
}

/* Why the last load failed. */
value kepler_dlerror(value unit) {
#ifdef _WIN32
  char text[32];
  snprintf(text, sizeof text, "error %lu", GetLastError());
  return caml_copy_string(text);
#else
  const char *text = dlerror();
  return caml_copy_string(text ? text : "unknown error");
#endif
}

value kepler_block_address(value block) {
  return Val_long((intnat) Caml_ba_data_val(block));
}

value kepler_cstring(value address) {
  return caml_copy_string((const char *) Long_val(address));
}

#ifdef __linux__
#include <sys/epoll.h>

#define MAX_EVENTS 1024

value kepler_epoll_create(value unit) {
  return Val_int(epoll_create1(EPOLL_CLOEXEC));
}

value kepler_epoll_ctl(value ep, value add, value fd) {
  struct epoll_event event;
  event.events = EPOLLIN | EPOLLOUT | EPOLLRDHUP | EPOLLET;
  event.data.fd = Int_val(fd);
  int op = Bool_val(add) ? EPOLL_CTL_ADD : EPOLL_CTL_DEL;
  return Val_int(epoll_ctl(Int_val(ep), op, Int_val(fd), &event));
}

/* The descriptors go in [out], which holds at least MAX_EVENTS. Returns how many; 0 if a signal arrived. */
value kepler_epoll_wait(value ep, value out, value milliseconds) {
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
