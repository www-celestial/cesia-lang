# Statistics

In this chapter you work with the laws of probability, with [std/stats]: the normal, Student's t, the chi-squared,
Fisher's F, the uniform, the exponential, the gamma, the beta, the binomial and the Poisson laws, each a value with
its density, its cumulative distribution, its quantiles and its random draws, what R's `pnorm` and `qt` and scipy's
`norm` and `t` give. Under them are the special functions of [std/special]: the gamma and beta functions, the error
function, and the incomplete gamma and beta ratios. Each comes from a published method, named here with what it
promises, and the last part of each section says how close it comes, measured against values computed to 70 digits
and against R and scipy.

## Laws of probability

A law is a value. `stats.Normal(100, 15)` is the normal law of mean 100 and standard deviation 15, and its methods
answer the questions of a course or a paper: the chance of a value below 130, of one above, the value below which 95 %
of them fall, the density at three points.

```cesia
use std/stats
d = stats.Normal(100, 15)
d.Cdf(130) -->
d.Cdf(130, upper = true) -->
d.Quantile(0.95) -->
d.Pdf([85, 100, 115]) -->
```

Every law has the same four methods:

| Cesia | What it gives | R | Python, `scipy.stats` | MATLAB |
|---|---|---|---|---|
| `d.Pdf(x)` | the density at `x`, or for a law of counts the probability of `x` | `dnorm(x, 100, 15)` | `d.pdf(x)`, `d.pmf(x)` | `normpdf(x, 100, 15)` |
| `d.Cdf(x)` | $P(X \le x)$ | `pnorm(x, 100, 15)` | `d.cdf(x)` | `normcdf(x, 100, 15)` |
| `d.Cdf(x, upper = true)` | $P(X > x)$, computed directly | `pnorm(x, 100, 15, lower.tail = FALSE)` | `d.sf(x)` | `normcdf(x, 100, 15, 'upper')` |
| `d.Quantile(p)` | the `x` where $P(X \le x) = p$ | `qnorm(p, 100, 15)` | `d.ppf(p)` | `norminv(p, 100, 15)` |
| `d.Quantile(p, upper = true)` | the `x` where $P(X > x) = p$ | `qnorm(p, 100, 15, lower.tail = FALSE)` | `d.isf(p)` | `norminv(1 - p, 100, 15)` |
| `d.Sample()`, `d.Sample(n)` | one draw, or an array of `n` | `rnorm(1, 100, 15)`, `rnorm(n, 100, 15)` | `d.rvs()`, `d.rvs(n)` | `normrnd(100, 15, 1, n)` |

`x` and `p` are a number or an array of any shape, and the answer has that shape. The laws, and their fields:

| Cesia | Its fields | R | scipy.stats | MATLAB |
|---|---|---|---|---|
| `stats.Normal(Mean, Sd)` | `Sd > 0` | `norm(mean, sd)` | `norm(loc, scale)` | `norm…(mu, sigma)` |
| `stats.StudentT(Df)` | `Df > 0`, infinite for the normal law | `t(df)` | `t(df)` | `t…(nu)` |
| `stats.ChiSquared(Df)` | `Df > 0` | `chisq(df)` | `chi2(df)` | `chi2…(nu)` |
| `stats.FisherF(Df1, Df2)` | both `> 0` | `f(df1, df2)` | `f(dfn, dfd)` | `f…(v1, v2)` |
| `stats.Uniform(Low, High)` | `Low < High` | `unif(min, max)` | `uniform(loc = Low, scale = High - Low)` | `unif…(a, b)` |
| `stats.Exponential(Rate)` | `Rate > 0` | `exp(rate)` | `expon(scale = 1 / Rate)` | `exp…(1 / Rate)`, a mean |
| `stats.Gamma(Shape, Rate)` | both `> 0` | `gamma(shape, rate)` | `gamma(a, scale = 1 / Rate)` | `gam…(a, 1 / Rate)` |
| `stats.Beta(A, B)` | both `> 0` | `beta(shape1, shape2)` | `beta(a, b)` | `beta…(a, b)` |
| `stats.Binomial(N, P)` | `N` a whole number of 0 or more, `P` in `[0, 1]` | `binom(size, prob)` | `binom(n, p)` | `bino…(n, p)` |
| `stats.Poisson(Lambda)` | `Lambda >= 0` | `pois(lambda)` | `poisson(mu)` | `poiss…(lambda)` |

In the MATLAB column, `…` is `pdf`, `cdf`, `inv` or `rnd`: `tcdf(x, nu)`, `chi2inv(p, nu)`. MATLAB and scipy take the
scale of the exponential and gamma laws, the mean time between events, where R and Cesia take the rate: Cesia's
`Exponential(2)` is MATLAB's `exp…(0.5)`.

A law is a struct, so `d.Mean` reads a field and a law passes to a function as any value. It is made without a check;
its first method call checks its fields, and a field outside its domain is a bug of the caller, a panic that names the
law, the field and the value:

```cesia fails
stats.Normal(0, -1).Cdf(0)
```

### Both tails

A tail is the probability beyond a point. `upper = true` computes the upper tail directly. `1 - d.Cdf(x)` would do it
in principle, but when the Cdf is near 1 the subtraction keeps none of the digits of the answer:

```cesia
1.0 - stats.Normal(0, 1).Cdf(9) -->
stats.Normal(0, 1).Cdf(9, upper = true) -->
```

A p-value of $10^{-40}$, the probability of a result at least as far when only chance is at work, keeps its digits
that way, and so does a quantile at `upper = true` for a small `p`.

### Quantiles

A quantile is the inverse of the Cdf: `d.Quantile(0.975)` is the `x` below which 97.5 % of the law falls. The two
critical values of a course, the Student quantile of a 95 % interval with 9 degrees of freedom and the chi-squared
quantile of a test at 5 % with 4:

```cesia
stats.StudentT(9).Quantile(0.975) -->
stats.ChiSquared(4).Quantile(0.05, upper = true) -->
```

For a law of counts, the binomial and the Poisson, the quantile is the smallest whole `k` with $P(X \le k) \ge p$, or
$P(X > k) \le p$ with `upper`, as in R: `p` first moves by $64 \epsilon$ toward the answer, so that the rounding of
a Cdf that equals `p` exactly doesn't push the answer one too far.

```cesia
b = stats.Binomial(20, 0.3)
b.Cdf(5) -->
b.Quantile(0.5) -->
stats.Poisson(4).Pdf([0, 1, 2]) -->
```

Outside the support, where the law has no mass, `Pdf` is 0 and `Cdf` 0 or 1; the `Pdf` of a law of counts is 0 at a
number that isn't whole. A `p` outside `[0, 1]` gives NaN, as `math.Log(-1.0)` does, and a NaN given is a NaN
returned.

### The same in Python, R and MATLAB

```python
from scipy import stats
d = stats.norm(100, 15)
d.cdf(130), d.sf(130), d.ppf(0.95), d.pdf([85, 100, 115])
stats.t(9).ppf(0.975), stats.chi2(4).isf(0.05), stats.binom(20, 0.3).cdf(5), stats.poisson(4).pmf([0, 1, 2])
```

```r
pnorm(130, 100, 15); pnorm(130, 100, 15, lower.tail = FALSE); qnorm(0.95, 100, 15); dnorm(c(85, 100, 115), 100, 15)
qt(0.975, 9); qchisq(0.05, 4, lower.tail = FALSE); pbinom(5, 20, 0.3); dpois(0:2, 4)
```

```matlab
normcdf(130, 100, 15), normcdf(130, 100, 15, 'upper'), norminv(0.95, 100, 15), normpdf([85 100 115], 100, 15)
tinv(0.975, 9), chi2inv(0.95, 4), binocdf(5, 20, 0.3), poisspdf(0:2, 4)
```

### What each method promises

- **Cdf.** The normal law's comes from Cody's approximations of `erf` and `erfc`, as `special.Erf`, with
  $e^{-z^2/2}$ taken from $z$ itself: dividing $z$ by $\sqrt 2$ first, as `erfc(-z / sqrt 2) / 2` does, would cost
  $z^2 \epsilon$ in the far tails. The others are the incomplete ratios of std/special: $P(T > |t|) = I_x(\nu/2, 1/2)/2$,
  $x = \nu / (\nu + t^2)$, for Student's t; $P(\nu / 2, x / 2)$ for the chi-squared; $I_u(d_1/2, d_2/2)$,
  $u = d_1 x / (d_1 x + d_2)$, for the F; $1 - I_p(k + 1, n - k)$ for the binomial; $Q(k + 1, \lambda)$ for the Poisson.
  Of $x$ and $1 - x$, the one given to the ratio is the one that keeps its digits, computed directly from the arguments,
  never as 1 minus the other.
- **Quantile.** The normal law's is Wichura's PPND16, as `special.ErfInv`. The gamma and the chi-squared, the beta and
  the F, and Student's t through the beta law of its tail, $t^2 = \nu (1 - x) / x$, are solved: a Newton step on the
  tail, in logarithms while the tail is far from its target and with Halley's correction near it, inside a bracket
  that every step narrows, with a bisection when a step leaves it, at most 100 steps; the variable solved for is the
  one on the small side, $x$ or $1 - x$, so that the answer keeps its digits in both tails. The start is the
  Wilson–Hilferty approximation for the gamma, a normal guess for the beta, and the first term of each tail's series
  where it is small. For $\nu = 1$ and $\nu = 2$, Student's quantile has its closed forms. Where the answer underflows
  the first term of the series is the answer.
- **Pdf.** The densities whose parameters are large, a binomial of $10^6$ trials, a gamma of shape 1,000, are computed
  through $\lambda = x / a$ and Stirling's series, $\sqrt{a / 2\pi}\, e^{a(\log\lambda - \lambda + 1)} / \Gamma^*(a)$,
  so that two large logarithms never cancel: the factors of the incomplete ratios of std/special.

### Beside R

On 300 random points for each law, its parameters spread over $e^{-3}$ to $e^{8}$, `x` around the bulk and into the
tails, and `p` from $10^{-200}$ to 1, Cesia's answers are within 2 $\epsilon$ of R 4.6.2's at the median, for every
method of every law. Where they differ by more, the 70-digit values were computed, and Cesia was the one nearer, by
far:

| R 4.6.2 | Cesia | The exact value |
|---|---|---|
| `pbeta(0.14303666358300993, 380.44661739092425, 34.46702297684653)`: 6.27888829438920e-275 | 6.27625470304679e-275 | 6.27625470304513e-275 |
| `qgamma(1.16e-14, 0.1966, lower.tail = FALSE)` off by $1.2 \times 10^{-10}$ in its tail | off by $8 \times 10^{-16}$ | |
| `qchisq(5.13e-14, 2668.04, lower.tail = FALSE)` off by $2.3 \times 10^{-8}$ | off by $2.3 \times 10^{-14}$ | |
| `qf(0.996, 0.5516, 1.8333, lower.tail = FALSE)` off by $1.8 \times 10^{-11}$ | off by $10^{-18}$ | |
| `dpois(19102, 18785.69)` off by $1.7 \times 10^{-12}$ | off by $10^{-16}$ | |
| `qt(8.93e-71, 0.434)`: $-\infty$ for the upper tail | $1.8195 \times 10^{160}$ | |

The tails are given as the relative error of the tail at the answer, $|F(x) - p| / p$, the measure of a quantile.
R is right on all the others, and nearer than Cesia on a few: where a parameter is below about $10^{-2}$, `pbeta` keeps
all its digits where Cesia's `BetaInc` loses up to a few hundred $\epsilon$.

## Special functions

`std/special` holds the eleven functions under the laws, for those who need them alone: a physicist's `erf`, a
`LogGamma`. Each takes numbers; its last argument may also be an array, of any shape, and
then the answer is an array of the same shape, element by element:

```cesia
use std/special
special.Gamma(5) -->
special.LogGamma(100) -->
special.Erf([0.0, 0.5, 1.0, 2.0]) -->
special.GammaInc(3, 2.5) -->
special.BetaInc(2, 3, 0.4) -->
```

| Cesia | What it is | R | Python | MATLAB |
|---|---|---|---|---|
| `special.Gamma(x)` | $\Gamma(x)$, $(n - 1)!$ at a whole $n$ | `gamma(x)` | `scipy.special.gamma(x)` | `gamma(x)` |
| `special.LogGamma(x)` | $\log \lvert\Gamma(x)\rvert$, finite where $\Gamma$ overflows | `lgamma(x)` | `gammaln(x)` | `gammaln(x)` |
| `special.Beta(a, b)` | $B(a, b) = \Gamma(a) \Gamma(b) / \Gamma(a + b)$ | `beta(a, b)` | `beta(a, b)` | `beta(a, b)` |
| `special.LogBeta(a, b)` | $\log B(a, b)$ | `lbeta(a, b)` | `betaln(a, b)` | `betaln(a, b)` |
| `special.Erf(x)` | $\frac{2}{\sqrt\pi} \int_0^x e^{-t^2} dt$ | `2 * pnorm(x * sqrt(2)) - 1` | `erf(x)` | `erf(x)` |
| `special.Erfc(x)` | $1 - \mathrm{erf}(x)$, computed directly | `2 * pnorm(-x * sqrt(2))` | `erfc(x)` | `erfc(x)` |
| `special.Erfcx(x)` | $e^{x^2} \mathrm{erfc}(x)$ | | `erfcx(x)` | `erfcx(x)` |
| `special.ErfInv(y)` | the $x$ where $\mathrm{erf}(x) = y$ | `qnorm((y + 1) / 2) / sqrt(2)` | `erfinv(y)` | `erfinv(y)` |
| `special.ErfcInv(y)` | the $x$ where $\mathrm{erfc}(x) = y$ | `qnorm(y / 2, lower.tail = FALSE) / sqrt(2)` | `erfcinv(y)` | `erfcinv(y)` |
| `special.GammaInc(a, x)` | $P(a, x)$, the regularized lower incomplete gamma | `pgamma(x, a)` | `gammainc(a, x)` | `gammainc(x, a)` |
| `special.GammaInc(a, x, upper = true)` | $Q(a, x) = 1 - P(a, x)$, computed directly | `pgamma(x, a, lower.tail = FALSE)` | `gammaincc(a, x)` | `gammainc(x, a, 'upper')` |
| `special.BetaInc(a, b, x)` | $I_x(a, b)$, the regularized incomplete beta | `pbeta(x, a, b)` | `betainc(a, b, x)` | `betainc(x, a, b)` |
| `special.BetaInc(a, b, x, upper = true)` | $1 - I_x(a, b)$, computed directly | `pbeta(x, a, b, lower.tail = FALSE)` | `betaincc(a, b, x)` | `betainc(x, a, b, 'upper')` |

R has no `erf`: the rows above write it with the normal law, which is what R users do. MATLAB puts `x` first in
`gammainc` and `betainc`; Cesia puts last the argument that may be an array, as scipy does.

The incomplete ratios are probabilities: $P(a, x)$ is the chance that a gamma variable of shape $a$ falls below $x$,
and $I_x(a, b)$ the chance that a beta variable falls below $x$. Every law of the next sections rests on them: the
chi-squared, the gamma and the Poisson on $P$, the Student, the F, the beta and the binomial on $I$.

### Both tails

A tail of a law is the probability beyond a point, below it or above it. `upper = true` computes the upper one
directly. `1 - P` would do it in principle, but when $P$ is near 1 the subtraction keeps none of the digits of the
small answer:

```cesia
1.0 - special.GammaInc(100, 200) -->
special.GammaInc(100, 200, upper = true) -->
```

The first is the gap between two floats near 1, and has no digit right. The second is $Q(100, 200)$ to 15 digits.

### Outside the domain

A domain is where a function is defined. Outside it the answer is NaN, as `math.Log(-1.0)` gives: `GammaInc(a, x)`
with a negative `a` or `x`, `BetaInc(a, b, x)` with `x` outside `[0, 1]`, `ErfInv(y)` with `|y| > 1`. A NaN given is
a NaN returned. $\Gamma$ is infinite at 0, with the sign of the zero, and NaN at the negative whole numbers, where it
has poles; `LogGamma` is infinite there. An argument that isn't a number, or an array with a text or a `missing` in
it, is a bug of the caller: a panic that names it.

```cesia
special.Gamma(-0.5) -->
special.Gamma(0.0) -->
special.ErfInv(1.5) -->
```

```cesia fails
special.Gamma([1.0, missing])
```

### The same in Python, R and MATLAB

```python
from scipy import special
special.gamma(5), special.gammaln(100), special.erf([0.0, 0.5, 1.0, 2.0])
special.gammainc(3, 2.5), special.betainc(2, 3, 0.4), special.gammaincc(100, 200)
```

```r
gamma(5); lgamma(100); 2 * pnorm(c(0, 0.5, 1, 2) * sqrt(2)) - 1
pgamma(2.5, 3); pbeta(0.4, 2, 3); pgamma(200, 100, lower.tail = FALSE)
```

```matlab
gamma(5), gammaln(100), erf([0 0.5 1 2])
gammainc(2.5, 3), betainc(0.4, 2, 3), gammainc(200, 100, 'upper')
```

### What each one promises

Each function follows a published method; its precision is what Cesia's tests measure, in units of $\epsilon = 2^{-52}$,
the gap between 1.0 and the next float: an error of 1 $\epsilon$ is a relative error of $2.2 \times 10^{-16}$, about 16
digits right, 45 $\epsilon$ about 14 digits.

- **`LogGamma` and `Gamma`.** On $[1.5, 2.5]$, $\log \Gamma(2 + z)$ is its Taylor series at 2,
  $(1 - \gamma) z + \sum_{k \ge 2} (-1)^k (\zeta(k) - 1) z^k / k$ (Abramowitz and Stegun, 6.1.33), 27 terms, whose
  coefficients were computed to 60 digits with the decimal arithmetic of Python; below 1.5 and up to 10, the recurrence
  $\Gamma(x + 1) = x \Gamma(x)$ brings $x$ there; from 10, Stirling's series, with eight of its terms; below 0, the
  reflection $\Gamma(x) \Gamma(1 - x) = \pi / \sin \pi x$, with $\sin \pi x$ from $x$ less the nearest whole number,
  a difference that is exact. Near 1 and 2, where $\log \Gamma$ is 0, the series keeps the relative precision too.
- **`Erf`, `Erfc`, `Erfcx`.** The rational approximations of Cody (1969), with the coefficients of his SPECFUN (1993),
  on $|x| \le 0.46875$, up to 4 and beyond. For a large $x$, $e^{-x^2}$ multiplies the error of $x^2$ by $x^2$: $x$ is
  split into a number of 1/16ths, whose square is exact, and the rest, so that $\mathrm{erfc}$ keeps its digits down to
  $10^{-308}$, at $x = 26.5$.
- **`ErfInv`, `ErfcInv`.** The normal quantile PPND16 of Wichura (1988), rational approximations in three regions,
  "accurate to about 1 part in $10^{16}$" (the paper), as $\mathrm{erfc}(x) = 2 P(Z > x \sqrt 2)$ for $Z$ of the
  normal law. `ErfcInv` keeps its digits for a small `y`, down to the smallest float.
- **`GammaInc`.** The regions of DiDonato and Morris (1986): near $x = a$ for $a \ge 20$, from $0.6 a$ to $1.4 a$,
  Temme's uniform asymptotic expansion (Temme 1979; DLMF 8.12), whose 142 coefficients come from the recurrence of
  DLMF 8.12.12, computed exactly in rationals; below, the power series of $P$; above, the even part of Legendre's
  continued fraction for $Q$ (DLMF 8.9.2), evaluated forward by the modified method of Lentz (Thompson and Barnett,
  1986); for $a < 1$ and $x \le 1.5$, a series of $Q$ itself, whose three terms are each of the size of $a$, so that $Q$
  keeps its digits as $a$ goes to 0. The factor $x^a e^{-x} / \Gamma(a)$ is computed with `pow` and `exp` where neither
  overflows, and else through $\lambda = x / a$: $\sqrt{a / 2\pi} \, e^{a (\log \lambda - \lambda + 1)} / \Gamma^*(a)$,
  with $\log(1 + t) - t$ computed without cancellation for a small $t$.
- **`BetaInc`.** The smaller tail is computed: the one below the mean $a / (a + b)$, by the symmetry
  $I_x(a, b) = 1 - I_{1 - x}(b, a)$ (DLMF 8.17.4); for a small $x$ by the power series, else by the even part of the
  continued fraction of DLMF 8.17.22. Near the mean, the first terms of that fraction are differences of large numbers
  that cancel: they are written with $\lambda = a (1 - x) - b x$, which keeps the digits there. The factor
  $x^a (1 - x)^b / B(a, b)$ is computed for $a, b \ge 10$ through Stirling's series, as DiDonato and Morris (1992) do,
  so that nothing large cancels.

The tests compare each function with values computed to 70 digits, from the exact float of each argument, with the
decimal arithmetic of Python, and with the published test data of Boost.Math, computed by its authors to 100 digits.
On the values of 70 digits, a few thousand points spread over each domain:

| Function | Points | Largest error | Mean error |
|---|---:|---:|---:|
| `LogGamma`, $x$ from $10^{-13}$ to $10^{13}$, away from 1 and 2 | 992 | 3.3 $\epsilon$ | 0.33 $\epsilon$ |
| `LogGamma`, within 0.25 of 1 or 2 | 208 | 2.4 $\epsilon$ | 0.36 $\epsilon$ |
| `Gamma`, $0 < x < 171$ | 962 | 2.4 $\epsilon$ | 0.31 $\epsilon$ |
| `Gamma`, $-170 < x < 0$ | 600 | 3.3 $\epsilon$ | 0.72 $\epsilon$ |
| `Erf`, $\lvert x \rvert < 6$ | 1,200 | 2.0 $\epsilon$ | 0.34 $\epsilon$ |
| `ErfInv` and the normal quantile, $p$ down to $10^{-300}$ | 300 | 2.0 $\epsilon$ | 0.58 $\epsilon$ |

On Boost's data, beside R 4.6.2 and scipy 1.18.1 on the same points:

| Boost's data | Cesia, largest / mean | R | scipy |
|---|---|---|---|
| `igamma_small_data`, $Q$ | 3.3 / 0.50 $\epsilon$ | 13.8 / 0.87 | 61.4 / 4.02 |
| `igamma_med_data`, $P$ | 5.4 / 0.52 $\epsilon$ | 6.2 / 0.75 | 398.6 / 25.1 |
| `igamma_med_data`, $Q$ | 9.7 / 0.54 $\epsilon$ | 11.8 / 0.70 | 556.5 / 17.4 |
| `igamma_big_data`, $P$ | 199.6 / 2.30 $\epsilon$ | 25.7 / 0.41 | 3,093.8 / 35.2 |
| `igamma_big_data`, $Q$ | 214.2 / 1.83 $\epsilon$ | 51.7 / 0.75 | 11,588.5 / 57.0 |
| `igamma_int_data`, $Q$ | 4.8 / 0.64 $\epsilon$ | 19.0 / 0.61 | 136.8 / 8.90 |
| `ibeta_small_data`, $I$ | 22.9 / 1.80 $\epsilon$ | 22.9 / 1.70 | 8.3 / 1.31 |
| `ibeta_data`, $I$ | 384.7 / 10.6 $\epsilon$ | 232.1 / 11.0 | 106.0 / 8.25 |
| `ibeta_data`, $1 - I$ | 389.2 / 12.4 $\epsilon$ | 204.1 / 11.3 | 0.4 / 0.14 |
| `ibeta_large_data`, $I$ | 578.8 / 11.0 $\epsilon$ | 573.6 / 13.2 | 1,239.4 / 10.2 |
| `ibeta_int_data`, $I$ | 74.0 / 3.74 $\epsilon$ | 62.0 / 4.33 | 3.9 / 0.42 |
| `erf_data`, `erfc` | 2.5 / 0.30 $\epsilon$ | 75.5 / 6.67 | 3.6 / 0.45 |
| `erf_large_data`, `erfc` | 1.2 / 0.38 $\epsilon$ | 837.6 / 222.7 | 2.5 / 0.63 |

**Where the others win.** R is closer on the largest gammas, `igamma_big_data`, with $a$ up to $10^5$: there the
factor $e^{a(\log\lambda - \lambda + 1)}$ has an exponent of a few hundred, and R computes it in two floats, a sum that
holds about 30 digits, where Cesia uses one. scipy's `betaincc`, which is Boost's code, is closer on Boost's own beta
data, to half an $\epsilon$.

The largest errors of the incomplete ratios sit in their far tails, where the function itself changes by a large factor
for a small change of its arguments: a relative change of $\epsilon$ in $x$ changes $P(a, x)$ by about
$c \, \epsilon$, with $c = \lvert x \, \partial P / \partial x \rvert / P$, which reaches thousands there; the 70-digit tests
of Cesia accept $16 (1 + c) \, \epsilon$ there, and $4 \epsilon$ for `LogGamma`, `Gamma`, `LogBeta`, `Erf` and `Erfc`.
DiDonato and Morris call this the *inherent error*: their codes promise 14 digits "when precision is not restricted by
inherent error". Where an argument is below about $10^{-3}$, `BetaInc` loses up to about 2,500 $\epsilon$ in the tail
near $x = 1$, where R keeps all its digits.

### Speed of the special functions

On the machine of [Speed](speed.md#beside-the-giants), a call on one number costs about 0.4 µs for `LogGamma`, 1 µs
for `GammaInc` and `BetaInc`, most of it the call itself; the computation inside is machine code made by the JIT:
`special.Erf` on an array of $10^6$ floats takes about 70 ms, 70 ns an element.

## Security

The functions read only their arguments: no file, network or permission is touched. Every loop is bounded: the series
and continued fractions stop at a fixed number of terms (2,000 to 20,000) even if they haven't converged, so no
argument can make a call run forever, and a NaN or an infinity goes through each formula to a NaN or the right limit.
A text, a `missing` or another value where a number is expected is a panic that names it, before any computation.

## Further reading

- Milton Abramowitz, Irene A. Stegun, editors. *Handbook of Mathematical Functions*. National Bureau of Standards, 1964.
  Formula 6.1.33, the series of $\log \Gamma$.
- W. J. Cody. "Rational Chebyshev approximations for the error function". *Mathematics of Computation* 23(107):631–637,
  1969. <https://doi.org/10.1090/S0025-5718-1969-0247736-4>.
- Michael J. Wichura. "Algorithm AS 241: The percentage points of the normal distribution". *Applied Statistics*
  37(3):477–484, 1988. <https://doi.org/10.2307/2347330>.
- Armido R. DiDonato, Alfred H. Morris. "Computation of the incomplete gamma function ratios and their inverse". *ACM
  Transactions on Mathematical Software* 12(4):377–393, 1986. <https://doi.org/10.1145/22721.23109>.
- Armido R. DiDonato, Alfred H. Morris. "Algorithm 708: Significant digit computation of the incomplete beta function
  ratios". *ACM Transactions on Mathematical Software* 18(3):360–373, 1992. <https://doi.org/10.1145/131766.131776>.
- N. M. Temme. "The asymptotic expansion of the incomplete gamma functions". *SIAM Journal on Mathematical Analysis*
  10(4):757–766, 1979. <https://doi.org/10.1137/0510071>.
- NIST Digital Library of Mathematical Functions, chapter 8, *Incomplete Gamma and Related Functions*: §8.9 (continued
  fractions), §8.12 (uniform expansions), §8.17 (the incomplete beta function). <https://dlmf.nist.gov/8>.
- I. J. Thompson, A. R. Barnett. "Coulomb and Bessel functions of complex arguments and order". *Journal of
  Computational Physics* 64(2):490–509, 1986. <https://doi.org/10.1016/0021-9991(86)90046-X>. The modified method of
  Lentz for continued fractions.
- David Goldberg. "What every computer scientist should know about floating-point arithmetic". *ACM Computing Surveys*
  23(1):5–48, 1991. <https://doi.org/10.1145/103162.103163>. Theorem 4, $\log(1 + x)$ without cancellation.
- Boost.Math, its test data for the special functions: <https://github.com/boostorg/math/tree/develop/test>.

## Next

The next chapter, [JSON and CSV](json.md), reads data from other programs and writes it for them.
