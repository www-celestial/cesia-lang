# Numbers and algorithms

In this chapter you meet the libraries of computation: [std/math] for one number, [std/num] for arrays, matrices and
statistics, [std/lapack] for the large matrices, [std/algo] for the classic algorithms, and three structures beside lists
and dictionaries: sets, queues and heaps. Each function is in the reference, with its examples; this chapter shows what
each library is for, and what it costs.

> [!NOTE]
> The examples of std/math and std/num have tabs: the same computation in Python with numpy, in R and in MATLAB. Each
> tab runs when the book is checked, and prints what the Cesia version shows; the MATLAB tabs run in GNU Octave. See
> [Tabs in other languages](tests.md#tabs-in-other-languages).

## One number: std/math

[std/math] holds the operators as functions, [math.Add], [math.Sub], [math.Mul], [math.Div] and [math.Mod], and
[math.Inc] and [math.Dec]; the rounding, [math.Round], [math.Floor] and [math.Ceil]; [math.Abs] and [math.Sign]; the
roots, powers and logarithms, [math.Sqrt], [math.Exp] and [math.Log]; the trigonometry in radians, [math.Sin],
[math.Cos], [math.Tan], [math.Asin], [math.Acos], [math.Atan], and [math.Atan2] for the angle of a point; the constants
[math.Pi], [math.Nan] and [math.Inf], `1.0 / 0.0`; and the tests [math.IsZero], [math.IsPos], [math.IsNeg],
[math.IsEven] and [math.IsOdd]. Each function of one number also works on an array, element by element. The sections
after the bits add the other logarithms and roots, the hyperbolic functions, the angles in degrees, a sensor's log
cleaned with them, the edges of floats and the physical constants of [std/constants].

```cesia
use std/math
math.Ceil(2.1) -->
math.Sign(-3) -->
math.Atan2(1.0, 1.0) * 4 --> math.Pi
math.Log(math.Exp(2.0)) -->
math.Sqrt([4, 9]) -->
math.IsEven(10) -->
```

```python
import numpy as np
print(np.ceil(2.1))
print(np.sign(-3))
print(np.arctan2(1.0, 1.0) * 4)
print(np.log(np.exp(2.0)))
print(np.sqrt([4, 9]))
print(10 % 2 == 0)
```

```r
print(ceiling(2.1))
print(sign(-3))
print(atan2(1, 1) * 4)
print(log(exp(2)))
print(sqrt(c(4, 9)))
print(10 %% 2 == 0)
```

```matlab
disp(ceil(2.1))
disp(sign(-3))
disp(atan2(1, 1) * 4)
disp(log(exp(2)))
disp(sqrt([4 9]))
disp(mat2str(mod(10, 2) == 0))
```

[math.Div] rounds down, toward minus infinity, and [math.Mod] has the sign of the divisor, so `math.Mod(-7, 3)` is `2`
and `math.Div(-7, 3) * 3 + math.Mod(-7, 3)` is `-7` again: the *floored division* of Python, not the *truncated* one of
C and Java, where `-7 % 3` is `-1`.

```cesia
math.Div(-7, 3) -->
math.Mod(-7, 3) -->
```

```python
print(-7 // 3)
print(-7 % 3)
```

```r
print(-7 %/% 3)
print(-7 %% 3)
```

```matlab
disp(floor(-7 / 3))
disp(mod(-7, 3))
```

### Bits

[math.BitAnd], [math.BitOr], [math.BitXor] and [math.BitNot] work on the bits of integers, and [math.BitShift] moves them
left for a positive count, right for a negative one. A right shift keeps the sign, as in Python and Go; a left shift works
on the 63 bits of an integer, and the bits shifted past them are lost:

```cesia
math.BitAnd(12, 10) -->
math.BitOr(12, 10) -->
math.BitXor(12, 10) -->
math.BitShift(1, 4) -->
math.BitShift(16, -2) -->
math.BitShift(-8, -1) -->
```

```python
print(12 & 10)
print(12 | 10)
print(12 ^ 10)
print(1 << 4)
print(16 >> 2)
print(-8 >> 1)
```

```r
print(bitwAnd(12L, 10L))
print(bitwOr(12L, 10L))
print(bitwXor(12L, 10L))
print(bitwShiftL(1L, 4L))
print(bitwShiftR(16L, 2L))
print(-8L %/% 2L)
```

```matlab
disp(bitand(12, 10))
disp(bitor(12, 10))
disp(bitxor(12, 10))
disp(bitshift(1, 4))
disp(bitshift(16, -2))
disp(floor(-8 / 2))
```

### Logarithms, roots and the hyperbolic functions

Beside [math.Log] and [math.Exp], [math.Log10] and [math.Log2] are the logarithms in base 10 and 2; [math.Log1p] is
`log(1 + x)` and [math.Expm1] is `exp(x) - 1`, which keep their digits for a small `x`, where `1 + x` has already lost
them. [math.Cbrt] is the cube root of any number, negative too, and [math.Hypot] is `sqrt(x^2 + y^2)`, the length of the
long side of a right triangle, without the overflow of the squares. [math.Sinh], [math.Cosh] and [math.Tanh] are the
hyperbolic functions, and [math.Asinh], [math.Acosh] and [math.Atanh] their inverses. Each works on a number and on an
array, element by element.

```cesia
math.Log10(1000) -->
math.Log2(1024) -->
math.Log1p(1e-12) -->
math.Log(1 + 1e-12) -->
math.Expm1(1e-12) -->
math.Cbrt([27, -8, 1000]) -->
math.Hypot(3, 4) -->
math.Hypot(1e200, 1e200) -->
math.Tanh(0.5) -->
math.Atanh(0.6) -->
```

```python
import numpy as np
print(np.log10(1000))
print(np.log2(1024))
print(np.log1p(1e-12))
print(np.log(1 + 1e-12))
print(np.expm1(1e-12))
print(np.round(np.cbrt([27, -8, 1000]), 12))
print(np.hypot(3, 4))
print(np.hypot(1e200, 1e200))
print(np.tanh(0.5))
print(np.arctanh(0.6))
```

```r
print(log10(1000))
print(log2(1024))
print(sprintf("%.16g", log1p(1e-12)))
print(sprintf("%.16g", log(1 + 1e-12)))
print(sprintf("%.16g", expm1(1e-12)))
x <- c(27, -8, 1000)
print(sign(x) * round(abs(x)^(1/3), 12))
print(Mod(complex(real = 3, imaginary = 4)))
print(Mod(complex(real = 1e200, imaginary = 1e200)))
print(tanh(0.5))
print(atanh(0.6))
```

```matlab
disp(log10(1000))
disp(log2(1024))
disp(sprintf('%.16g', log1p(1e-12)))
disp(sprintf('%.16g', log(1 + 1e-12)))
disp(sprintf('%.16g', expm1(1e-12)))
disp(nthroot([27 -8 1000], 3))
disp(hypot(3, 4))
disp(hypot(1e200, 1e200))
disp(tanh(0.5))
disp(atanh(0.6))
```

`math.Log(1 + 1e-12)` is wrong from its fifth digit: `1 + 1e-12` is rounded to the float nearest to it before the
logarithm sees it. [math.Cbrt] is correctly rounded, the float nearest to the real root, so that `math.Cbrt(27)` is `3.0`:
numpy's `np.cbrt(27.0)` is `3.0000000000000004`, from the C library, and the Python tab rounds it to show the same
numbers.

### Angles in degrees

[math.Radians] turns degrees into radians, and [math.Degrees] radians into degrees. [math.SinDegrees],
[math.CosDegrees] and [math.TanDegrees] take degrees themselves, and reduce the angle exactly first, so that the sine of
180 degrees is `0.0` and the sine of 30 degrees is `0.5`, where the sine of the radians, rounded, is off by a little:

```cesia
math.SinDegrees([30, 90, 180]) -->
math.Sin(math.Radians([30, 90, 180])) -->
math.CosDegrees(90) -->
math.TanDegrees(45) -->
math.Degrees(math.Atan(1.0)) -->
```

```python
import numpy as np
print(np.round(np.sin(np.radians([30, 90, 180])), 15))
print(np.sin(np.radians([30, 90, 180])))
print(round(np.cos(np.radians(90)), 15))
print(round(np.tan(np.radians(45)), 15))
print(np.degrees(np.arctan(1.0)))
```

```r
print(sinpi(c(30, 90, 180) / 180))
print(sprintf("%.17g", sin(c(30, 90, 180) * pi / 180)))
print(cospi(90 / 180))
print(tanpi(45 / 180))
print(atan(1) * 180 / pi)
```

```matlab
disp(sind([30 90 180]))
disp(sprintf('%.17g ', sin(deg2rad([30 90 180]))))
disp(cosd(90))
disp(tand(45))
disp(rad2deg(atan(1)))
```

The arc functions in degrees are [math.Degrees] of the arc functions: MATLAB's `asind(x)` is
`math.Degrees(math.Asin(x))`.

### A sensor log, cleaned

A weather station writes a line every ten minutes: the temperature in °C, the humidity in %, where the wind comes from
in degrees and its speed in m/s, and the rain in mm. Eight lines of it, as a sensor gives them: one temperature is
missing, the line lost, and one is NaN, `0.0 / 0.0`, a division by a zero count in the station's own firmware; two
humidities are out of 0..100, and the wind turns around north.

```cesia
use std/list
use std/num
use std/value
temp = [12.4, 12.9, missing, 13.8, 0.0 / 0.0, 14.6, 15.1, 15.3]
humidity = [81.0, 79.5, 78.2, 104.3, 76.0, -2.0, 74.1, 73.0]
direction = [350.0, 10.0, 20.0, 355.0, 5.0, 15.0, 0.0, 345.0]
speed = [3.1, 2.8, 4.0, 3.5, 2.2, 3.9, 4.4, 3.0]
rain = [0.0, 0.0, 0.2, 1.5, 12.0, 0.4, 0.0, 30.0]
```

**1. Find the holes.** [math.IsNan] finds the NaN, and `value.IsMissing` the missing value: they are not the same
thing, a number that went wrong and no number at all, but both are holes. numpy and MATLAB have NaN alone for both, and
R has both, `NaN` and `NA`, which `is.na` finds together; MATLAB's `fillmissing` of step 2 is in its core, and in a package of Octave. [math.IsFinite] keeps the numbers that are neither, and an
infinity of a broken sensor would go with them:

```cesia
holes = [value.IsMissing(x) or math.IsNan(x) for x in temp]
holes -->
list.Sum(holes) -->
good = [x for x in temp if math.IsFinite(x)]
list.Mean(good) -->
```

```python
import numpy as np
temp = np.array([12.4, 12.9, np.nan, 13.8, np.nan, 14.6, 15.1, 15.3])
holes = np.isnan(temp)
print(holes)
print(holes.sum())
good = temp[np.isfinite(temp)]
print(good.mean())
```

```r
temp <- c(12.4, 12.9, NA, 13.8, NaN, 14.6, 15.1, 15.3)
holes <- is.na(temp)
print(holes)
print(sum(holes))
good <- temp[is.finite(temp)]
print(mean(good))
```

```matlab
temp = [12.4 12.9 NaN 13.8 NaN 14.6 15.1 15.3];
holes = isnan(temp);
disp(mat2str(holes))
disp(sum(holes))
good = temp(isfinite(temp));
disp(mean(good))
```

**2. Fill them.** [num.ReplaceNan] puts a value in place of each NaN and each missing value: here the mean of the good
temperatures, and no rain for a reading the gauge lost, `num.ReplaceNan(0.0, rain)`.

```cesia
filled = num.ReplaceNan(list.Mean(good), temp)
filled -->
```

```python
import numpy as np
temp = np.array([12.4, 12.9, np.nan, 13.8, np.nan, 14.6, 15.1, 15.3])
good = temp[np.isfinite(temp)]
filled = np.nan_to_num(temp, nan=good.mean())
print(filled)
```

```r
temp <- c(12.4, 12.9, NA, 13.8, NaN, 14.6, 15.1, 15.3)
good <- temp[is.finite(temp)]
filled <- replace(temp, is.na(temp), mean(good))
print(filled)
```

```matlab
temp = [12.4 12.9 NaN 13.8 NaN 14.6 15.1 15.3];
good = temp(isfinite(temp));
filled = temp;
filled(isnan(filled)) = mean(good);
disp(filled)
```

**3. Clip what can't be.** A humidity is from 0 to 100 %: [math.Clamp] keeps each reading in that range, and a bound
it passes is the bound itself.

```cesia
math.Clamp(0, 100, humidity) -->
```

```python
import numpy as np
humidity = np.array([81.0, 79.5, 78.2, 104.3, 76.0, -2.0, 74.1, 73.0])
print(np.clip(humidity, 0, 100))
```

```r
humidity <- c(81.0, 79.5, 78.2, 104.3, 76.0, -2.0, 74.1, 73.0)
print(pmin(pmax(humidity, 0), 100))
```

```matlab
humidity = [81.0 79.5 78.2 104.3 76.0 -2.0 74.1 73.0];
disp(mat2str(min(max(humidity, 0), 100)))
```

**4. Average the wind.** The mean of the directions is 137.5 degrees, south-east, for a wind that blows from the north
all along: 350 and 10 are 20 degrees apart, not 340. The mean wind is the mean of its vectors, east and north, with
[math.SinDegrees] and [math.CosDegrees]; a wind from a direction blows toward the other side, hence the minus signs.
[math.Atan2] gives the direction of the mean vector back, and [math.Hypot] its speed:

```cesia
list.Mean(direction) -->
east = -speed * math.SinDegrees(direction)
north = -speed * math.CosDegrees(direction)
math.Degrees(math.Atan2(-list.Mean(east), -list.Mean(north))) -->
math.Hypot(list.Mean(east), list.Mean(north)) -->
```

```python
import numpy as np
direction = np.array([350.0, 10.0, 20.0, 355.0, 5.0, 15.0, 0.0, 345.0])
speed = np.array([3.1, 2.8, 4.0, 3.5, 2.2, 3.9, 4.4, 3.0])
print(direction.mean())
east = -speed * np.sin(np.radians(direction))
north = -speed * np.cos(np.radians(direction))
print(np.degrees(np.arctan2(-east.mean(), -north.mean())))
print(np.hypot(east.mean(), north.mean()))
```

```r
direction <- c(350, 10, 20, 355, 5, 15, 0, 345)
speed <- c(3.1, 2.8, 4.0, 3.5, 2.2, 3.9, 4.4, 3.0)
print(mean(direction))
east <- -speed * sinpi(direction / 180)
north <- -speed * cospi(direction / 180)
print(atan2(-mean(east), -mean(north)) * 180 / pi)
print(Mod(complex(real = mean(east), imaginary = mean(north))))
```

```matlab
direction = [350 10 20 355 5 15 0 345];
speed = [3.1 2.8 4.0 3.5 2.2 3.9 4.4 3.0];
disp(mean(direction))
east = -speed .* sind(direction);
north = -speed .* cosd(direction);
disp(rad2deg(atan2(-mean(east), -mean(north))))
disp(hypot(mean(east), mean(north)))
```

The mean wind comes from 3.1 degrees, a little east of north, at 3.3 m/s: a little less than the mean of the speeds,
as the wind didn't blow from one direction all along.

**5. Put the rain on a log scale.** Rain is 0 most of the time and 30 mm in a storm: on a plot, the storm hides the
rest. A logarithm spreads them, but `math.Log10(0)` is `-math.Inf`; [math.Log1p], `log(1 + x)`, is 0 at 0, close to `x`
for a small rain, and grows as the logarithm for a large one:

```cesia
math.Log10(rain) -->
math.Log1p(rain) -->
```

```python
import numpy as np
rain = np.array([0.0, 0.0, 0.2, 1.5, 12.0, 0.4, 0.0, 30.0])
with np.errstate(divide="ignore"):
    print(np.log10(rain))
print(np.log1p(rain))
```

```r
rain <- c(0.0, 0.0, 0.2, 1.5, 12.0, 0.4, 0.0, 30.0)
print(log10(rain))
print(log1p(rain))
```

```matlab
rain = [0.0 0.0 0.2 1.5 12.0 0.4 0.0 30.0];
disp(log10(rain))
disp(log1p(rain))
```

```cesia allow=read,write
use std/plot
times = list.Range(0, 70, step = 10)
rainPlot = plot.Of([plot.Line(times, math.Log1p(rain), label = "log1p(rain)"), plot.Points(times, math.Log1p(rain))],
  title = "Rain on a log scale: math.Log1p keeps the dry readings at 0", x = "minutes", y = "log(1 + mm)", size = [640, 340])
plot.Save(rainPlot, "numbers-rain.svg") -->
```

**6. A switch.** The heating of the station's box turns on below 14 °C: [math.Step] is 0 below 0 and 1 above, Heaviside's
step, and `zero` its value at 0 itself, 0.5 when not given, as MATLAB's `heaviside`.

```cesia
math.Step(14 - filled, zero = 0) -->
```

```python
import numpy as np
temp = np.array([12.4, 12.9, np.nan, 13.8, np.nan, 14.6, 15.1, 15.3])
filled = np.nan_to_num(temp, nan=temp[np.isfinite(temp)].mean())
print(np.heaviside(14 - filled, 0))
```

```r
temp <- c(12.4, 12.9, NA, 13.8, NaN, 14.6, 15.1, 15.3)
filled <- replace(temp, is.na(temp), mean(temp[is.finite(temp)]))
print(as.numeric(14 - filled > 0))
```

```matlab
temp = [12.4 12.9 NaN 13.8 NaN 14.6 15.1 15.3];
filled = temp;
filled(isnan(filled)) = mean(temp(isfinite(temp)));
disp(double(14 - filled > 0))
```

### The edges of floats

A float has 53 bits: [math.Epsilon] is the gap from a number to the next float above it, so `math.Epsilon(1.0)` is the
machine epsilon, and [math.NextAfter] is that next float. [math.MaxFloat] is the largest float, [math.MinFloat] the
smallest normal one, [math.MaxInt] and [math.MinInt] the bounds of Cesia's integers of 63 bits, and [math.E] the base of
the natural logarithm. [math.IsInf] finds the infinities that an overflow leaves, and [math.LogSumExp] is
`log(sum(exp(xs)))` without that overflow, the softmax's denominator of machine learning:

```cesia
math.Epsilon(1.0) -->
math.Epsilon(1e9) -->
math.NextAfter(1.0, 2.0) -->
math.MaxFloat -->
math.MinFloat -->
math.E -->
math.IsInf(math.Exp([700.0, 710.0])) -->
math.LogSumExp([1000.0, 1001.0, 1002.0]) -->
```

```python
import numpy as np
import scipy.special
print(np.finfo(float).eps)
print(np.spacing(1e9))
print(np.nextafter(1.0, 2.0))
print(np.finfo(float).max)
print(np.finfo(float).tiny)
print(np.e)
with np.errstate(over="ignore"):
    print(np.isinf(np.exp([700.0, 710.0])))
print(scipy.special.logsumexp([1000.0, 1001.0, 1002.0]))
```

```r
print(sprintf("%.16g", .Machine$double.eps))
print(sprintf("%.16g", 2^(floor(log2(1e9)) - 52)))
print(sprintf("%.17g", 1 + .Machine$double.eps))
print(sprintf("%.17g", .Machine$double.xmax))
print(sprintf("%.17g", .Machine$double.xmin))
print(sprintf("%.16g", exp(1)))
print(is.infinite(exp(c(700, 710))))
x <- c(1000, 1001, 1002)
print(sprintf("%.16g", max(x) + log(sum(exp(x - max(x))))))
```

```matlab
disp(sprintf('%.16g', eps))
disp(sprintf('%.16g', eps(1e9)))
disp(sprintf('%.17g', 1 + eps))
disp(sprintf('%.17g', realmax))
disp(sprintf('%.17g', realmin))
disp(sprintf('%.16g', exp(1)))
disp(mat2str(isinf(exp([700 710]))))
x = [1000 1001 1002];
disp(sprintf('%.16g', max(x) + log(sum(exp(x - max(x))))))
```

### Physical constants: std/constants

[std/constants] holds the 355 constants of CODATA 2022, the values that NIST publishes, by their names in its table:
[constants.Value] gives the value, [constants.Unit] the unit, [constants.Uncertainty] the standard uncertainty, 0 for
the exact ones, and [constants.Find] the names that hold a word. The energy of a photon of green light, 532 nm, is
`h c / lambda`:

```cesia
use std/constants
constants.Find("Planck") -->
planck = constants.Value("Planck constant")
light = constants.Value("speed of light in vacuum")
planck * light / 532e-9 -->
planck * light / 532e-9 / constants.Value("elementary charge") -->
constants.Unit("Newtonian constant of gravitation") -->
constants.Uncertainty("Newtonian constant of gravitation") -->
```

```python
import scipy.constants as sc
print(sc.find("Planck"))
h = sc.value("Planck constant")
c = sc.value("speed of light in vacuum")
print(h * c / 532e-9)
print(h * c / 532e-9 / sc.value("elementary charge"))
print(sc.unit("Newtonian constant of gravitation"))
print(sc.physical_constants["Newtonian constant of gravitation"][2])
```

### What they promise

Each function was run on 100,000 inputs each, its edges among them, beside numpy 2.5, R 4.6 and GNU Octave 11 (for
MATLAB), and compared with mpmath at 300 bits on 20,000 of them: the count of results that are not the float nearest
to the exact value, and the largest error, in units of the last place (ulps).

| Function | Cesia | numpy | R | MATLAB (Octave) |
|---|---|---|---|---|
| [math.Cbrt] | 0 | 10,055, 3 ulps | 15,888, 120 ulps | 10,055, 3 ulps |
| [math.Sinh], [math.Cosh], [math.Asinh], [math.Acosh], [math.Atanh] | 0 | 0 | 0 | 0 |
| [math.Tanh] | 0 | 2,578, 1 ulp | 0 | 0 |
| [math.Log2] | 34, 1 ulp | the same | the same | the same |
| [math.Log1p] | 41, 1 ulp | the same | 130, 1 ulp | the same |
| [math.Expm1] | 541, 1 ulp | the same | 606, 1 ulp | the same |
| [math.Log10] | 2,868, 2 ulps | the same | the same | the same |
| [math.Hypot] | 16, 1 ulp | the same | the same | the same |
| [math.SinDegrees] | 3,128, 1 ulp | 14,669 | 14,982 | 10,980 |
| [math.CosDegrees] | 2,851, 1 ulp | 14,356 | 14,383 | 9,146 |
| [math.TanDegrees] | 6,816, 2 ulps | 17,083 | 17,411 | 17,661 |

Cesia calls the C library, glibc 2.44 here, as numpy, R and Octave do, for all but [math.Cbrt], its own, and gives the
same bits as numpy where numpy calls it too. The C library's cube root is up to 3 ulps away; Cesia's takes the float
nearest to the real root from a polynomial, its cube made exact, and decides the rare cases near the middle of two floats
by the exact sign of a sum (Shewchuk's expansions), so that it is never wrong, and as fast. numpy's `tanh` is its own,
faster and 1 ulp off one time in eight. The degrees of numpy, R and Octave are wrong at the multiples of 180 and 90: the
sine of 180 degrees is 1.2e-16 there, in place of 0, an error of an infinity of ulps; Cesia's reduction makes them exact,
and errs by 1 ulp at most elsewhere, where the radians are rounded once. [math.Log10] is the weak one of the C library,
2 ulps near 1, as everywhere.

### What they cost

On a million floats, in nanoseconds per element, medians of 5 runs alternated with numpy 2.5 and R 4.6 (Intel Core
i7-4720HQ, 4 cores, load average 2.1 to 2.6): Cesia's call on the array, on all cores and on one, and a loop of
machine code that calls the function on each element.

| Function | Cesia, 4 cores | Cesia, 1 core | loop | numpy | R |
|---|---|---|---|---|---|
| [math.Log10] | 5.7 | 11.3 | 12.4 | 9.7 | 17.0 |
| [math.Log1p] | 6.0 | 11.8 | 12.5 | 9.8 | 16.0 |
| [math.Expm1] | 6.5 | 13.8 | 15.3 | 12.1 | 17.0 |
| [math.Cbrt] | 6.1 | 21.3 | 55.6 | 20.4 | 35.0 |
| [math.Tanh] | 6.3 | 18.4 | 19.0 | 16.3 | 20.0 |
| [math.Asinh] | 6.9 | 24.6 | 26.2 | 23.6 | 26.0 |
| [math.SinDegrees] | 7.0 | 23.7 | 29.1 | 14.1 | 23.0 |
| [math.Radians] | 1.9 | 1.7 | 3.9 | 1.8 | 6.0 |
| [math.Hypot] | 3.2 | 9.2 | 12.6 | 8.8 | 29.0 |
| [math.Clamp] | 2.1 | 1.9 | 76.6 | 1.5 | 7.0 |
| [math.IsNan] | 3.1 | 6.0 | 3.5 | 0.6 | 2.0 |
| [num.ReplaceNan] | 3.4 | 3.5 | 44.3 | 5.6 | 4.0 |
| [math.LogSumExp] | 8.9 | 8.8 | | 24.5 | 12.0 |

On one core, Cesia takes 1.04 to 1.21 times numpy's time for the functions of the C library, which both call, and as
long for [math.Cbrt], its own and correctly rounded; on four, it is ahead. [math.LogSumExp] is three times as fast as
scipy's, which makes the array of the differences, then of their exponentials, before it sums them. numpy wins three:
its `isnan` writes a byte for each element, where Cesia's array of booleans holds a word of 8 bytes; its `clip` takes
the SIMD instructions of the processor; and `np.sin(np.radians(x))` skips the exact reduction of [math.SinDegrees],
whose `fmod` and `round` take 10 of its 24 ns, at the price of `0.0` for the sine of 180 degrees. A loop that calls
[math.Cbrt], [math.Clamp], [num.ReplaceNan], [math.Step], [math.Epsilon] or [math.LogSumExp] stays in the interpreter,
as machine code calls no function written in OCaml; give it the array in one call.

## Arrays and statistics: std/num

[std/num] is numerical computing in the spirit of numpy: an array is a list or a matrix of floats, and the operators of
the language already work on it element by element. It adds the rest.

| To | Use |
|---|---|
| make arrays | [num.Linspace] evenly spaced floats, [num.Eye] the identity matrix, [num.Diag] a diagonal matrix |
| draw random arrays | [num.Uniform] from 0 to 1, [num.Normal] from the normal distribution of mean 0 and deviation 1, both from [std/random]'s generator |
| describe | [num.Median], [num.Percentile], [num.Variance], [num.Std], [num.Covariance], [num.Correlation], [num.Histogram] |
| run along | [num.Cumsum] the running sum, [num.Diff] the differences, [num.Trapezoid] the area under points |
| fit | [num.Polyfit] a polynomial through points, [num.Polyval] its value, [num.Interpolate] between points, [num.LeastSquares] the best `x` of `a * x = b` |
| linear algebra | [num.Dot], [num.Norm], [num.Det], [num.Solve], [num.Inverse], [num.Qr], [num.Eigen] |
| signals | [num.Fft] and [num.Ifft], the Fourier transform and its inverse |

```cesia
use std/num
num.Linspace(0.0, 1.0, 5) -->
num.Percentile(90, 1..10) -->
num.Correlation([1.0, 2.0, 3.0], [2.0, 4.0, 6.5]) -->
num.Cumsum([1, 2, 3]) -->
num.Trapezoid([0.0, 1.0, 2.0], [0.0, 1.0, 4.0]) -->
num.Solve([2.0, 1.0; 1.0, 3.0], [3.0; 5.0]) -->
num.Det([1.0, 2.0; 3.0, 4.0]) -->
```

```python
import numpy as np
print(np.linspace(0.0, 1.0, 5))
print(np.percentile(np.arange(1, 11), 90))
print(np.corrcoef([1.0, 2.0, 3.0], [2.0, 4.0, 6.5])[0, 1])
print(np.cumsum([1, 2, 3]))
print(np.trapezoid([0.0, 1.0, 4.0], [0.0, 1.0, 2.0]))
print(np.linalg.solve([[2.0, 1.0], [1.0, 3.0]], [3.0, 5.0]))
print(np.linalg.det([[1.0, 2.0], [3.0, 4.0]]))
```

```r
print(seq(0, 1, length.out = 5))
print(quantile(1:10, 0.9, names = FALSE))
print(cor(c(1, 2, 3), c(2, 4, 6.5)))
print(cumsum(c(1, 2, 3)))
x <- c(0, 1, 2)
y <- c(0, 1, 4)
print(sum(diff(x) * (head(y, -1) + tail(y, -1)) / 2))
print(solve(matrix(c(2, 1, 1, 3), 2), c(3, 5)))
print(det(matrix(c(1, 3, 2, 4), 2)))
```

```matlab
disp(linspace(0, 1, 5))
x = 1:10;                      % the 90th percentile, linear between ranks, as numpy and R
h = (numel(x) - 1) * 0.9 + 1;
disp(x(floor(h)) + (h - floor(h)) * (x(ceil(h)) - x(floor(h))))
r = corrcoef([1 2 3], [2 4 6.5]);
disp(r(1, 2))
disp(cumsum([1 2 3]))
disp(trapz([0 1 2], [0 1 4]))
disp([2 1; 1 3] \ [3; 5])
disp(det([1 2; 3 4]))
```

[num.Trapezoid] joins the points by straight lines and adds the areas of the trapezoids under them:

```cesia allow=read,write
use std/plot
tx = [0.0, 1.0, 2.0]
ty = [0.0, 1.0, 4.0]
area = plot.Of([plot.Area(tx, 0.0 * tx, ty, label = "area $(num.Trapezoid(tx, ty))"), plot.Line(tx, ty), plot.Points(tx, ty)],
  title = "num.Trapezoid: the area under lines through the points", x = "x", y = "y", size = [640, 340])
plot.Save(area, "numbers-trapezoid.svg") -->
```

### How it computes

- [num.Solve], [num.Det] and [num.Inverse] use *Gaussian elimination with partial pivoting*: at each column, the row of
  the largest value goes first, which keeps the rounding errors small. A matrix whose pivot falls below $10^{-14}$ is
  *singular*, it has no inverse, and gives an `Err` of kind `"math"`.
- [num.Eigen] takes a symmetric matrix and turns it diagonal by *Jacobi rotations*, each of which zeroes one value off
  the diagonal; the diagonal left holds the *eigenvalues*, the numbers $\lambda$ for which $a v = \lambda v$ has a solution $v$,
  its *eigenvector*.
- [num.LeastSquares] solves the *normal equations*, $a^T a x = a^T b$. This is fast, but it squares the *condition number*
  of $a$, how much an error in the data grows in the answer, so a nearly singular $a$ loses digits: [num.Qr] gives the
  factors for a steadier method.
- [num.Fft] is the radix-2 *fast Fourier transform* of Cooley and Tukey, $O(n \log n)$, when the length is a power of two,
  and the plain sum, $O(n^2)$, otherwise.

### Large matrices: BLAS and LAPACK

*BLAS* is the standard interface of the basic operations of linear algebra, as the matrix product, and *LAPACK* the one
of solving, factoring and eigenvalues, written on BLAS; OpenBLAS and Apple's Accelerate are fast versions of both, tuned
for each processor. A release of Cesia brings OpenBLAS on Linux and Windows, and uses Accelerate on macOS. [num.Backend]
and [lapack.Name] tell the one in use, or `missing`. [matrix.Matmul], [num.Solve], [num.Det], [num.Qr] and [num.Eigen]
call it for a large matrix, from order 32, or from $32 \times 32 \times 32$ multiplications for a product, and use Cesia's own code
below that, which gives the same bits on every machine, or without a library; [std/lapack] calls
it directly, and gives `missing` where it can't: [lapack.Solve], [lapack.Det], [lapack.Qr] and [lapack.Eigen].
`CESIA_BLAS=none` runs Cesia's code alone, to compare.

## Algorithms: std/algo

[std/algo] holds the classic algorithms, written in Cesia, functions first and the collection last.

| To | Use |
|---|---|
| search a sorted array | [algo.BinarySearch] the position of a value, [algo.LowerBound] the first position not below it, in $O(\log n)$ |
| cut and combine | [algo.Chunk] pieces of `n`, [algo.Windows] sliding runs of `n`, [algo.Partition] by a test, [algo.Combinations], [algo.Permutations] |
| integers | [algo.Gcd] and [algo.Lcm], [algo.IsPrime] by trial division, [algo.Primes] by the sieve of Eratosthenes |
| texts | [algo.Levenshtein], the *edit distance*: the fewest insertions, deletions and replacements of a character from one text to another |
| graphs | [algo.Bfs] breadth first and [algo.Dfs] depth first, [algo.Dijkstra] the shortest distances, [algo.TopologicalSort] an order where each node comes after those it needs |

```cesia
use std/algo
algo.BinarySearch(7, [1, 3, 7, 9]) -->
algo.Chunk(2, [1, 2, 3, 4, 5]) -->
algo.Windows(2, [1, 2, 3]) -->
algo.Gcd(84, 36) -->
algo.Primes(20) -->
algo.Levenshtein("kitten", "sitting") -->
```

A *graph* here is a function that gives the neighbors of a node, so no structure must be built first:

```cesia
roads = {a: [{Node: "b", Weight: 4}, {Node: "c", Weight: 1}], c: [{Node: "b", Weight: 2}], b: []}
algo.Dijkstra(n -> roads[n], "a") -->
algo.Bfs(n -> [e.Node for e in roads[n]], "a") -->
needs = {app: ["lib", "log"], lib: ["log"], log: []}
algo.TopologicalSort(n -> needs[n], ["app", "lib", "log"]) -->
```

[algo.Dijkstra] keeps the nodes to visit in a [std/heap], by their distance so far, so it takes $O(E \log E)$ for $E$
edges; its weights must not be negative. [algo.TopologicalSort] walks the graph depth first and gives an `Err` of kind `"cycle"`
when a node needs itself through others.

## Sets, queues and heaps

Three persistent structures, like lists and dictionaries: a change gives a new value, and the old one stays.

- A *set*, [std/set], holds numbers and texts, each once, in order: [set.Of], [set.Empty], [set.Add], [set.Remove],
  [set.Has], [set.Items], [set.Union], [set.Intersection], [set.Difference] and [set.IsSubset]. It is a dictionary whose
  keys are its elements, so a test or a change costs as a dictionary's does, $O(\log_{32} n)$; [set.Items] sorts them, in
  $O(n \log n)$.
- A *queue*, [std/queue], is open at both ends, a *deque*: [queue.Push] at the back and [queue.PushFront] at the front,
  [queue.Pop] and [queue.PopBack] take away, [queue.First] and [queue.Last] read the ends, [queue.Items] gives them all,
  [queue.Of] and [queue.Empty] make one, [queue.IsEmpty] asks; [queue.Queue] is its struct. It is a dictionary from positions to elements, so each
  operation is $O(\log_{32} n)$, as for a dictionary.
- A *heap*, [std/heap], gives back the smallest key first, a *priority queue*: [heap.Insert] adds a value under a key,
  [heap.Peek] reads the smallest, [heap.Pop] takes it away, [heap.Merge] joins two heaps, [heap.Items] gives them all in
  order, [heap.Empty] and [heap.IsEmpty]. It is a *leftist heap*, from Okasaki's book: its shorter branch is always on
  the right, so an insert, a pop or a merge is $O(\log n)$.

```cesia
use std/set
use std/queue
use std/heap
set.Items(set.Union(set.Of([3, 1]), set.Of([2, 3]))) -->
set.IsSubset(set.Of([1]), set.Of([1, 2])) -->
q = queue.Of([1, 2]) then queue.Push(3) then queue.PushFront(0)
queue.Items(q) -->
queue.First(queue.Pop(q)) -->
h = heap.Empty() then heap.Insert(5, "low") then heap.Insert(1, "urgent")
heap.Peek(h) -->
heap.Items(heap.Pop(h)) -->
```

## Further reading

- E. Anderson and others, *LAPACK Users' Guide*, 1999; Cooley and Tukey, *An Algorithm for the Machine Calculation of
  Complex Fourier Series*, 1965; Charles R. Harris and others, *Array programming with NumPy*, 2020.
- E. W. Dijkstra, *A note on two problems in connexion with graphs*, 1959; V. I. Levenshtein, *Binary codes capable of
  correcting deletions, insertions, and reversals*, 1966.
- Chris Okasaki, *Purely Functional Data Structures*, 1998: the leftist heap and persistent structures.
- Jonathan Richard Shewchuk, *Adaptive Precision Floating-Point Arithmetic and Fast Robust Geometric Predicates*, 1997:
  the exact sign of [math.Cbrt]'s rare cases; Pierre Blanchard, Desmond J. Higham and Nicholas J. Higham, *Accurately
  computing the log-sum-exp and softmax functions*, 2021: [math.LogSumExp]; Charles F. F. Karney, *Algorithms for
  geodesics*, 2013: the reduction of [math.SinDegrees]; CODATA 2022, the constants of [std/constants].

Each with its link in [References](references.md#data-and-numbers).

## Next

You can compute with numbers and structures. The next chapter, [Graphs](graphs.md), draws what you compute.
