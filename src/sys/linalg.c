/* BLAS and LAPACK in their Fortran form, found at run time so that cesia links nothing new: columns first, like the arrays
   of Cesia, and every argument by address. A value of OCaml's floatarray is its doubles. Each call gives LAPACK's info. */
#include <caml/mlvalues.h>
#include <stdlib.h>

#define DOUBLES(v) ((double *) (v))
#define CALL(type, f) ((type *) Long_val(f))

typedef void gemm(const char *, const char *, const int *, const int *, const int *, const double *, const double *,
                  const int *, const double *, const int *, const double *, double *, const int *, size_t, size_t);
typedef void gesv(const int *, const int *, double *, const int *, int *, double *, const int *, int *);
typedef void getrf(const int *, const int *, double *, const int *, int *, int *);
typedef void geqrf(const int *, const int *, double *, const int *, double *, double *, const int *, int *);
typedef void orgqr(const int *, const int *, const int *, double *, const int *, double *, double *, const int *, int *);
typedef void syev(const char *, const char *, const int *, double *, const int *, double *, double *, const int *, int *,
                  size_t, size_t);

value cesia_dgemm(value f, value dims, value out, value x, value y) {
  int rows = Int_val(Field(dims, 0)), cols = Int_val(Field(dims, 1)), inner = Int_val(Field(dims, 2));
  double one = 1.0, zero = 0.0;
  CALL(gemm, f)("N", "N", &rows, &cols, &inner, &one, DOUBLES(x), &rows, DOUBLES(y), &inner, &zero, DOUBLES(out), &rows, 1, 1);
  return Val_unit;
}

value cesia_dgesv(value f, value order, value columns, value a, value b) {
  int n = Int_val(order), k = Int_val(columns), info = -1;
  int *pivots = malloc(sizeof(int) * n);
  if (pivots) CALL(gesv, f)(&n, &k, DOUBLES(a), &n, pivots, DOUBLES(b), &n, &info);
  free(pivots);
  return Val_int(info);
}

/* Factors [a], and gives the sign of its permutation in [sign]. */
value cesia_dgetrf(value f, value order, value a, value sign) {
  int n = Int_val(order), info = -1;
  int *pivots = malloc(sizeof(int) * n);
  if (pivots) {
    CALL(getrf, f)(&n, &n, DOUBLES(a), &n, pivots, &info);
    DOUBLES(sign)[0] = 1.0;
    for (int k = 0; k < n; k++)
      if (pivots[k] != k + 1) DOUBLES(sign)[0] = -DOUBLES(sign)[0];
  }
  free(pivots);
  return Val_int(info);
}

/* The Q of [a] replaces it, and the R stays in [r], which has its upper triangle on return. */
value cesia_qr(value factor, value build, value dims, value a, value r) {
  int rows = Int_val(Field(dims, 0)), cols = Int_val(Field(dims, 1)), size = 64 * cols, info = -1;
  double *tau = malloc(sizeof(double) * cols), *work = malloc(sizeof(double) * size);
  if (tau && work) {
    CALL(geqrf, factor)(&rows, &cols, DOUBLES(a), &rows, tau, work, &size, &info);
    if (info == 0) {
      for (int j = 0; j < cols; j++)
        for (int i = 0; i <= j; i++) DOUBLES(r)[j * cols + i] = DOUBLES(a)[j * rows + i];
      CALL(orgqr, build)(&rows, &cols, &cols, DOUBLES(a), &rows, tau, work, &size, &info);
    }
  }
  free(tau);
  free(work);
  return Val_int(info);
}

/* The eigenvectors of [a] replace it, and the eigenvalues go in [w]. */
value cesia_dsyev(value f, value order, value a, value w) {
  int n = Int_val(order), size = 66 * n, info = -1;
  double *work = malloc(sizeof(double) * size);
  if (work) CALL(syev, f)("V", "U", &n, DOUBLES(a), &n, DOUBLES(w), work, &size, &info, 1, 1);
  free(work);
  return Val_int(info);
}
