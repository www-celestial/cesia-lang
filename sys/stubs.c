/* The epoll system calls, which OCaml's unix library doesn't offer. Nothing else belongs here. */
#ifdef __linux__
#include <sys/epoll.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/signals.h>

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
