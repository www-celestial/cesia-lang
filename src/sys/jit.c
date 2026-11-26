/* The JIT's glue to MIR: a context per module of MIR text, which only Cesia's own generator writes, made by its load,
   never at start-up, and freed once nothing can run its code; and one entry to call what they export. */
#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/signals.h>
#include <math.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include "mir.h"
#include "mir-gen.h"

/* Code pages are never writable and executable at once: read-write while MIR writes them, then read and execute.
   MIR's own allocator keeps them writable and executable while it writes. On Apple's arm64, MAP_JIT and its switch per
   thread, Apple's own way. A failed map gives what MIR compares with: MAP_FAILED of mman.h, or NULL on Windows. */
#if defined(_WIN32)
#include <windows.h>
static void *map(size_t len, void *u) { return VirtualAlloc(NULL, len, MEM_RESERVE | MEM_COMMIT, PAGE_NOACCESS); }
static int unmap(void *a, size_t len, void *u) { return VirtualFree(a, 0, MEM_RELEASE) ? 0 : -1; }
static int protect(void *a, size_t len, MIR_mem_protect_t p, void *u) {
  DWORD old;
  if (!VirtualProtect(a, len, p == PROT_WRITE_EXEC ? PAGE_READWRITE : PAGE_EXECUTE_READ, &old)) return -1;
  if (p != PROT_WRITE_EXEC) FlushInstructionCache(GetCurrentProcess(), a, len);
  return 0;
}
#else
#include <sys/mman.h>
#if defined(__APPLE__) && defined(__aarch64__)
#include <libkern/OSCacheControl.h>
#include <pthread.h>
static void *map(size_t len, void *u) {
  return mmap(NULL, len, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
}
static int protect(void *a, size_t len, MIR_mem_protect_t p, void *u) {
  pthread_jit_write_protect_np(p != PROT_WRITE_EXEC);
  if (p != PROT_WRITE_EXEC) sys_icache_invalidate(a, len);
  return 0;
}
#else
static void *map(size_t len, void *u) { return mmap(NULL, len, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0); }
static int protect(void *a, size_t len, MIR_mem_protect_t p, void *u) {
  return mprotect(a, len, p == PROT_WRITE_EXEC ? PROT_READ | PROT_WRITE : PROT_READ | PROT_EXEC);
}
#endif
static int unmap(void *a, size_t len, void *u) { return munmap(a, len); }
#endif

static struct MIR_code_alloc code = { map, unmap, protect, NULL };
/* A load runs on any domain, the level 2 of a unit on another one than its runs: each thread has its own way back. */
static _Atomic int broken;
static _Thread_local jmp_buf on_error;
static _Thread_local char error[256];

/* MIR stops at an error: back to the load, and the JIT is off for the rest of the run, as MIR's state is unknown. */
static void MIR_NO_RETURN failed(MIR_error_type_t type, const char *format, ...) {
  va_list args;
  va_start(args, format);
  vsnprintf(error, sizeof error, format, args);
  va_end(args);
  longjmp(on_error, 1);
}

/* A failed check inside MIR, which would abort: back to the load too. */
void cesia_mir_failed(const char *what) {
  snprintf(error, sizeof error, "jit: a check of MIR failed: %s", what);
  longjmp(on_error, 1);
}

intnat cesia_jit_native(int64_t *cx, value *args, intnat n, intnat k, intnat at, intnat site, intnat fuel);

static MIR_item_t exported(MIR_module_t m, const char *name) {
  for (MIR_item_t it = DLIST_HEAD(MIR_item_t, m->items); it != NULL; it = DLIST_NEXT(MIR_item_t, it))
    if (it->item_type == MIR_func_item && strcmp(it->u.func->name, name) == 0) return it;
  return NULL;
}

/* Makes machine code of a module of MIR text at a level of MIR, in a context of its own, without the domain's lock, so
   that the other domains, and their collections, go on meanwhile: the context, then the address of each function named;
   or fails with MIR's message, and after an error of MIR, every load fails. */
value cesia_jit_load(value text, value names, value level) {
  CAMLparam3(text, names, level);
  CAMLlocal1(out);
  mlsize_t n = Wosize_val(names);
  void *addrs[65];
  if (n > 64) caml_failwith("jit: too many functions in one module");
  if (broken) caml_failwith("jit: off after an error of MIR");
  char *src = caml_stat_strdup(String_val(text));
  int opt = Int_val(level);
  MIR_context_t mir;
  caml_enter_blocking_section();
  if (setjmp(on_error)) {
    broken = 1;
    caml_leave_blocking_section();
    caml_stat_free(src);
    caml_failwith(error);
  }
  mir = MIR_init2(NULL, &code);
  MIR_set_error_func(mir, failed);
  MIR_gen_init(mir);
  MIR_gen_set_optimize_level(mir, opt);
  /* The functions of libm that the IR names, as OCaml calls them, so that results are the same to the bit. */
#define LIBM(f) MIR_load_external(mir, #f, f);
  LIBM(sqrt) LIBM(exp) LIBM(log) LIBM(sin) LIBM(cos) LIBM(tan) LIBM(asin) LIBM(acos) LIBM(atan) LIBM(fabs) LIBM(pow) LIBM(log10)
  LIBM(log2) LIBM(log1p) LIBM(expm1) LIBM(sinh) LIBM(cosh) LIBM(tanh) LIBM(asinh) LIBM(acosh) LIBM(atanh) LIBM(hypot) LIBM(fmod) LIBM(round)
  MIR_load_external(mir, "caml_modify", caml_modify);
  MIR_load_external(mir, "cesia_jit_native", cesia_jit_native);
  MIR_scan_string(mir, src);
  MIR_module_t m = DLIST_TAIL(MIR_module_t, *MIR_get_module_list(mir));
  MIR_load_module(mir, m);
  MIR_link(mir, MIR_set_gen_interface, NULL);
  /* Every function is made: the generator's own memory goes now, in the thread that made them. */
  MIR_gen_finish(mir);
  caml_leave_blocking_section();
  caml_stat_free(src);
  addrs[0] = mir;
  for (mlsize_t k = 0; k < n; k++) {
    MIR_item_t it = exported(m, String_val(Field(names, k)));
    if (it == NULL) { MIR_finish(mir); caml_failwith("jit: a function named is not in the module"); }
    addrs[k + 1] = it->addr;
  }
  out = caml_alloc(n + 1, 0);
  for (mlsize_t k = 0; k <= n; k++) Store_field(out, k, caml_copy_nativeint((intnat) addrs[k]));
  CAMLreturn(out);
}

/* Frees what a load made, its machine code with it: called once nothing can run that code. The isb: on arm64, this core
   then fetches the code that another core wrote, which replaces the code freed. */
value cesia_jit_free(value mir) {
  MIR_finish((MIR_context_t) Nativeint_val(mir));
#if defined(__aarch64__)
  __asm__ volatile("isb" ::: "memory");
#endif
  return Val_unit;
}

/* The one entry: f(cx) gives a status. cx holds the stacks (ints and io are OCaml int arrays, whose cells hold 2n + 1;
   floats raw doubles; values an array of values), then the cells of io as raw integers, copied back after, at 30 and 31
   the addresses of the young heap's pointer and limit, where native code allocates in room it checked first, and at 32
   that of the list of local roots. Only a call of OCaml through [cesia_jit_native] collects: io is a root here, so that
   it is written where the collection put it (OCaml's rule of CAMLparam). */
typedef intnat entry(int64_t *);

value cesia_jit_call(value f, value ints, value floats, value vals, value io) {
  CAMLparam5(f, ints, floats, vals, io);
  int64_t cx[33];
  mlsize_t n = Wosize_val(io);
  if (n > 29) n = 29;
  cx[0] = (int64_t) ints;
  cx[1] = (int64_t) floats;
  cx[2] = (int64_t) vals;
  for (mlsize_t k = 3; k < n; k++) cx[k] = Long_val(Field(io, k));
  cx[30] = (int64_t) &Caml_state->young_ptr;
  cx[31] = (int64_t) &Caml_state->young_limit;
  cx[32] = (int64_t) &CAML_LOCAL_ROOTS;
  intnat status = ((entry *) Nativeint_val(f))(cx);
  for (mlsize_t k = 3; k < n; k++) Field(io, k) = Val_long(cx[k]);
  CAMLreturn(Val_long(status));
}

/* A call of native code to OCaml: [Engine]'s closure runs the native [k] of the unit at [site], from the frame at [at],
   with the [n] values at [args], its result in Engine's [result], or grows the stacks for a frame at [at] (k -1), or makes room for [at] words in the
   young heap (k -2). Native code linked a block of local roots that holds [args] and each value it needs after, as
   CAMLlocalN would: a collection here moves them and writes where they went, and native code reads them back after
   (OCaml's rules of the C interface: every value live across an allocation or a callback is a registered root). Here,
   [a] is made, filled and given to the callback with no allocation between, and [r] read before any: neither needs a
   root of its own. The closure catches every exception of OCaml, which never unwinds native code's frames. The result to
   args[0], the stacks, which a growth or a collection replaced, and the cells of io that the call changed to cx; the
   fuel, or -1 when the native raised. */
intnat cesia_jit_native(int64_t *cx, value *args, intnat n, intnat k, intnat at, intnat site, intnat fuel) {
  value a, r;
  static const value *bridge = NULL, *io = NULL, *result = NULL;
  /* The cells of io, as Ir's: operands in, then the limits and the counts of steps that a call changes. */
  enum { code = 14, op_a = 15, op_b = 16, point = 13, spent = 10, quantum = 11 };
  static const int back[] = { 6, 7, 9, 19, 21 };
  if (bridge == NULL) {
    bridge = caml_named_value("cesia_jit_native");
    io = caml_named_value("cesia_jit_io");
    result = caml_named_value("cesia_jit_result");
  }
  a = n > 0 ? caml_alloc_small(n, 0) : Atom(0);
  for (intnat j = 0; j < n; j++) Field(a, j) = args[j];
  Field(*io, op_a) = Val_long(k);
  Field(*io, op_b) = Val_long(at);
  Field(*io, point) = Val_long(site);
  Field(*io, code) = Val_long(cx[spent] + cx[quantum] - fuel);
  r = caml_callback_exn(*bridge, a);
  if (Is_exception_result(r) || Is_long(r)) {
    cx[5] = fuel;
    fuel = -1;
  } else {
    r = Field(r, 0);
    cx[0] = (int64_t) Field(r, 2);
    cx[1] = (int64_t) Field(r, 1);
    cx[2] = (int64_t) Field(r, 0);
    for (int j = 0; j < 5; j++) cx[back[j]] = Long_val(Field(*io, back[j]));
    if (k >= 0) args[0] = Field(*result, 0);
  }
  return fuel;
}
