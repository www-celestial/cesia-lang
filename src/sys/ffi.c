/* Calls through libffi, found at run time so that kepler links nothing new: more than 6 arguments, structures by
   value, variadic functions and callbacks. The types below are the stable part of libffi's interface. */
#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

void *kepler_open(const char *name);
void *kepler_symbol(void *lib, const char *name);

typedef struct type { size_t size; unsigned short alignment; unsigned short kind; struct type **elements; } type;

#define STRUCT_KIND 13
#if defined(__x86_64__) && !defined(_WIN64)
#define ABI 2
#elif defined(__x86_64__) || defined(__aarch64__)
#define ABI 1
#else
#error "No libffi calling convention for this processor."
#endif

typedef void handler(void *, void *, void **, void *);

typedef struct {
  int (*prep)(void *, int, unsigned, type *, type **);
  int (*prep_var)(void *, int, unsigned, unsigned, type *, type **);
  void (*call)(void *, void *, void *, void **);
  void *(*closure_alloc)(size_t, void **);
  int (*prep_closure)(void *, void *, handler *, void *, void *);
  type *types[12];
} table;

typedef struct {
  table *t;
  unsigned nargs;
  _Alignas(16) char cif[128];
  type *args[];
} call;

typedef struct { value f; } holder;

static const char *const names[] = { "libffi.so.8", "libffi.so.7", "libffi.so", "libffi.8.dylib", "libffi.dylib",
                                     "/opt/homebrew/lib/libffi.dylib", "libffi-8.dll", "ffi-8.dll" };
static const char *const type_names[] = { "ffi_type_void", "ffi_type_uint8", "ffi_type_sint8", "ffi_type_uint16",
  "ffi_type_sint16", "ffi_type_uint32", "ffi_type_sint32", "ffi_type_uint64", "ffi_type_sint64", "ffi_type_float",
  "ffi_type_double", "ffi_type_pointer" };

/* The table of libffi's functions, or 0 if it isn't there. */
value kepler_ffi_load(value unit) {
  void *lib = NULL;
  for (size_t k = 0; !lib && k < sizeof names / sizeof names[0]; k++) lib = kepler_open(names[k]);
  if (!lib) return Val_long(0);
  table *t = malloc(sizeof(table));
  *(void **) &t->prep = kepler_symbol(lib, "ffi_prep_cif");
  *(void **) &t->prep_var = kepler_symbol(lib, "ffi_prep_cif_var");
  *(void **) &t->call = kepler_symbol(lib, "ffi_call");
  *(void **) &t->closure_alloc = kepler_symbol(lib, "ffi_closure_alloc");
  *(void **) &t->prep_closure = kepler_symbol(lib, "ffi_prep_closure_loc");
  for (int k = 0; k < 12; k++) t->types[k] = kepler_symbol(lib, type_names[k]);
  return Val_long((intnat) t);
}

value kepler_ffi_type(value t, value k) {
  return Val_long((intnat) ((table *) Long_val(t))->types[Long_val(k)]);
}

value kepler_ffi_struct(value fields) {
  size_t n = Wosize_val(fields);
  type *s = calloc(1, sizeof(type));
  s->kind = STRUCT_KIND;
  s->elements = calloc(n + 1, sizeof(type *));
  for (size_t k = 0; k < n; k++) s->elements[k] = (type *) Long_val(Field(fields, k));
  return Val_long((intnat) s);
}

/* A prepared signature. [fixed] is the number of fixed arguments of a variadic function, or -1. */
value kepler_ffi_cif(value vt, value ret, value args, value fixed) {
  table *t = (table *) Long_val(vt);
  unsigned n = Wosize_val(args);
  call *c = malloc(sizeof(call) + (n + 1) * sizeof(type *));
  c->t = t;
  c->nargs = n;
  for (unsigned k = 0; k < n; k++) c->args[k] = (type *) Long_val(Field(args, k));
  type *r = (type *) Long_val(ret);
  int status = Long_val(fixed) < 0 ? t->prep(c->cif, ABI, n, r, c->args)
                                   : t->prep_var(c->cif, ABI, Long_val(fixed), n, r, c->args);
  return Val_long(status == 0 ? (intnat) c : 0);
}

/* [slots] holds a word per argument, then the result. A bit of [structs] means that a word is the address of a
   structure. Everything is copied first: a callback can run the GC, which moves [slots]. */
value kepler_ffi_invoke(value vc, value fn, value slots, value structs, value ret) {
  CAMLparam1(slots);
  call *c = (call *) Long_val(vc);
  unsigned n = c->nargs;
  int64_t *words = malloc((n + 1) * sizeof(int64_t));
  void **pointers = malloc((n + 1) * sizeof(void *));
  memcpy(words, Bytes_val(slots), n * sizeof(int64_t));
  for (unsigned k = 0; k < n; k++)
    pointers[k] = Long_val(structs) >> k & 1 ? (void *) (intptr_t) words[k] : (void *) &words[k];
  int64_t scalar[2] = { 0, 0 };
  c->t->call(c->cif, (void *) Long_val(fn), Long_val(ret) ? (void *) Long_val(ret) : (void *) scalar, pointers);
  memcpy(Bytes_val(slots) + n * sizeof(int64_t), scalar, sizeof(int64_t));
  free(words);
  free(pointers);
  CAMLreturn(Val_unit);
}

static void entry(void *cif, void *ret, void **args, void *user) {
  caml_callback2(((holder *) user)->f, Val_long((intnat) args), Val_long((intnat) ret));
}

/* A C function that calls [f]. It lives until the program ends, since C can keep it. */
value kepler_ffi_closure(value vc, value f) {
  CAMLparam1(f);
  call *c = (call *) Long_val(vc);
  void *code = NULL;
  void *closure = c->t->closure_alloc(512, &code);
  if (!closure) CAMLreturn(Val_long(0));
  holder *h = malloc(sizeof(holder));
  h->f = f;
  caml_register_generational_global_root(&h->f);
  if (c->t->prep_closure(closure, c->cif, entry, h, code)) CAMLreturn(Val_long(0));
  CAMLreturn(Val_long((intnat) code));
}

value kepler_strdup(value s) {
  size_t n = caml_string_length(s) + 1;
  char *copy = malloc(n);
  memcpy(copy, String_val(s), n);
  return Val_long((intnat) copy);
}

value kepler_free(value p) {
  free((void *) Long_val(p));
  return Val_unit;
}

value kepler_peek(value address, value width) {
  int64_t x = 0;
  memcpy(&x, (void *) Long_val(address), Long_val(width));
  return caml_copy_int64(x);
}

value kepler_poke(value address, value x) {
  int64_t v = Int64_val(x);
  memcpy((void *) Long_val(address), &v, sizeof v);
  return Val_unit;
}
