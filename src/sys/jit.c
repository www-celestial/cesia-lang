/* The JIT's glue to MIR: a context made at the first load, never at start-up; modules given as MIR text, which only
   Cesia's own generator writes; and one entry to call what they export. */
#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
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
static MIR_context_t mir;
static int broken;
static jmp_buf on_error;
static char error[256];

/* MIR stops at an error: back to the load, and the JIT is off for the rest of the run, as MIR's state is unknown. */
static void MIR_NO_RETURN failed(MIR_error_type_t type, const char *format, ...) {
  va_list args;
  va_start(args, format);
  vsnprintf(error, sizeof error, format, args);
  va_end(args);
  longjmp(on_error, 1);
}

static MIR_item_t exported(MIR_module_t m, const char *name) {
  for (MIR_item_t it = DLIST_HEAD(MIR_item_t, m->items); it != NULL; it = DLIST_NEXT(MIR_item_t, it))
    if (it->item_type == MIR_func_item && strcmp(it->u.func->name, name) == 0) return it;
  return NULL;
}

/* Loads a module of MIR text and gives the address of each function named, or fails with MIR's message. */
value cesia_jit_load(value text, value names) {
  CAMLparam2(text, names);
  CAMLlocal1(out);
  mlsize_t n = Wosize_val(names);
  void *addrs[64];
  if (n > 64) caml_failwith("jit: too many functions in one module");
  if (broken) caml_failwith(error);
  if (setjmp(on_error)) {
    broken = 1;
    caml_failwith(error);
  }
  if (mir == NULL) {
    mir = MIR_init2(NULL, &code);
    MIR_set_error_func(mir, failed);
    MIR_gen_init(mir);
    MIR_gen_set_optimize_level(mir, 2);
    /* The functions of libm that the IR names, as OCaml calls them, so that results are the same to the bit. */
    static const char *names[] = { "sqrt", "exp", "log", "sin", "cos", "tan", "asin", "acos", "atan", "fabs", "pow" };
    void *fs[] = { sqrt, exp, log, sin, cos, tan, asin, acos, atan, fabs, pow };
    for (int k = 0; k < 11; k++) MIR_load_external(mir, names[k], fs[k]);
  }
  MIR_scan_string(mir, String_val(text));
  MIR_module_t m = DLIST_TAIL(MIR_module_t, *MIR_get_module_list(mir));
  MIR_load_module(mir, m);
  MIR_link(mir, MIR_set_gen_interface, NULL);
  for (mlsize_t k = 0; k < n; k++) {
    MIR_item_t it = exported(m, String_val(Field(names, k)));
    if (it == NULL) {
      snprintf(error, sizeof error, "jit: no function %s", String_val(Field(names, k)));
      caml_failwith(error);
    }
    addrs[k] = it->addr;
  }
  out = caml_alloc(n, 0);
  for (mlsize_t k = 0; k < n; k++) Store_field(out, k, caml_copy_nativeint((intnat) addrs[k]));
  CAMLreturn(out);
}

/* The one entry: f(cx) gives a status. cx holds the stacks (ints and io are OCaml int arrays, whose cells hold 2n + 1;
   floats raw doubles; values an array of values), then the cells of io as raw integers, copied back after. Nothing here
   allocates, so no collection moves the stacks while native code runs. */
typedef intnat entry(int64_t *);

value cesia_jit_call(value f, value ints, value floats, value vals, value io) {
  int64_t cx[32];
  mlsize_t n = Wosize_val(io);
  if (n > 32) n = 32;
  cx[0] = (int64_t) ints;
  cx[1] = (int64_t) floats;
  cx[2] = (int64_t) vals;
  for (mlsize_t k = 3; k < n; k++) cx[k] = Long_val(Field(io, k));
  intnat status = ((entry *) Nativeint_val(f))(cx);
  for (mlsize_t k = 3; k < n; k++) Field(io, k) = Val_long(cx[k]);
  return Val_long(status);
}
