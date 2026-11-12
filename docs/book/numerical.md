# Numerical methods

In this chapter you find where a function is zero, with [optimize.Root], and you solve differential equations, with
[ode.Solve]: what `fzero` and `ode45` do in MATLAB, `brentq` and `solve_ivp` in scipy. Each method comes from a paper,
named here with what it promises; the tests of Cesia check each promise, and the last part of each section says how it
compares with scipy and Octave, measured.

## The zero of a function

[optimize.Root] finds an `x` where `f(x) = 0`, for a function `f` of one number that gives one number. Give it a
*bracket*, two numbers `a` and `b` where `f(a)` and `f(b)` have opposite signs: if `f` is continuous, it is zero
somewhere between them.

```cesia
use std/math
use std/optimize
use std/result
r = result.Unwrap(optimize.Root(x -> x ^ 3 - 2.0 * x - 5.0, [2.0, 3.0]))
r -->
```

`X` is the zero, `F` is `f(X)`, and `Evaluations` counts the calls of `f`. The same in Python, R and MATLAB:

```python
from scipy.optimize import brentq
x, r = brentq(lambda x: x**3 - 2*x - 5, 2, 3, full_output=True)   # 2.094551481542327, r.function_calls 8
```

```r
uniroot(function(x) x^3 - 2*x - 5, c(2, 3), tol = 1e-15)$root   # 2.0945514815423265
```

```matlab
x = fzero(@(x) x^3 - 2*x - 5, [2 3])   % 2.094551481542327
```

The answers differ in their last digit: Cesia gives the float nearest to the zero, 2.0945514815423265, by default;
scipy's `brentq` and MATLAB's `fzero` stop one float away from it at their defaults, and R's `uniroot` needs `tol` to get
there.

### From one start

With one number instead of a bracket, Root looks for a bracket first: points on both sides of the start, 2 % of it away
(0.02 for 0), then twice as far at each step, at most 60 steps, until `f` changes sign. A side where `f` gives no finite
number, as `math.Log` of a negative number, stops there, and the other goes on:

```cesia
optimize.Root(x -> math.Cos(x) - x, 1.0).Value.X -->
optimize.Root(x -> math.Log(x) - 1.0, 0.01).Value.X -->
math.Exp(1.0) -->
```

`fzero(f, x0)` searches the same way; scipy has no search, so the Python version needs the bracket.

### What it promises

The method is Brent's (1973), which MATLAB's `fzero`, scipy's `brentq` and R's `uniroot` all follow. It keeps a bracket
`[b, c]` where `f` changes sign, `b` the end where `|f|` is smaller, and shrinks it at each step. The step is one of three:

- the *secant*: the zero of the line through the last two points;
- *inverse quadratic interpolation*: the parabola in `y` through the last three points, `x = p(y)`, at `y = 0`;
- *bisection*: the middle of the bracket.

The first two are fast near a simple zero: the error falls superlinearly, faster at each step. Bisection is slow but
sure: it halves the bracket every time. Brent takes an interpolation step only when it falls inside the bracket and
shrinks it fast enough, and bisects otherwise, so that, his book says, it "never converges much more slowly than
bisection". It stops when the bracket is at most $2 \epsilon |X| + 2 \cdot \text{tol}$ wide, where
$\epsilon = 2^{-52}$ is the gap between 1.0 and the next float: with `tol = 0.0`, the default, `X` is one of the two
floats around the zero. `tol` is an absolute tolerance: `tol = 1e-6` stops sooner, within about `1e-6` of the zero.

The promise holds for any continuous `f` that changes sign in the bracket: `X` is within the width above of a point where
`f` changes sign. A function with several zeros in the bracket gives one of them. Cesia's tests check it on the 154
problems of Alefeld, Potra and Shi (1995), functions chosen to be hard for such methods: flat at their zero, steep, with
poles nearby; on polynomials with a known simple zero, drawn at random; and on zeros known in closed form, as
$\pi / 6$ for $\sin x = 1/2$.

### When there is no zero

Root gives an `Err` of kind `"optimize"`, with `Best`, the point of smallest `|f|` it met, when the bracket has no sign
change, when the search finds none, when `f` gives a NaN, an infinity or no number, or when `|f|` grows as the bracket
shrinks: a *pole*, where `f` goes to infinity, changes sign too, but is no zero. scipy's `brentq` returns the pole of
`1 / (x - 0.3)`, 0.3000000000014551, as if it were a zero, and Octave's `fzero` returns 0.3 with a warning.

```cesia
optimize.Root(x -> x * x + 1.0, [0.0, 1.0]).Error.Message -->
optimize.Root(x -> 1.0 / (x - 0.3), [0.0, 1.0]).Error.Message -->
```

A bracket that isn't two different numbers, or a negative `tol`, is a bug of the caller: a panic that names it.

### Beside TOMS 748

Alefeld, Potra and Shi (1995) proposed TOMS 748, a method that uses cubic interpolation and proves a higher efficiency.
On their own 154 problems, Root makes 2,761 calls of `f` in all at full precision; scipy's `toms748` makes 2,682, 2.9 %
fewer, fewer on 88 problems and more on 46. At `tol = 5e-11` the gap is 2.1 %, at `5e-8` 0.5 %. Brent's method stays:
the gain is small, and not on every problem. scipy's `brentq` makes 2,753 calls, as it stops one float earlier.

### Speed of Root

The zero of $x^3 - 2x - 5$ on `[2, 3]` to the last float, 20,000 times in a loop: 7.1 µs a call in Cesia (95 % interval
of the median of 21 runs: 6.9 to 7.5), 11.5 µs for scipy's `brentq` (11.3 to 12.0), each with 8 calls of `f`, measured as
the solves of [Speed of Solve](#speed-of-solve) are. Root's loop runs in the interpreter, as the JIT doesn't yet make
machine code of a loop that calls [math.Abs] or [value.IsNumber].

## Differential equations

A *differential equation* gives the rate of change of a state: $y' = f(t, y)$, the derivative of `y` at time `t`. With
the state at a first time, `y0`, it fixes the state at every later time: a decay, an orbit, a reaction, a population.
[ode.Solve] computes it. Here a decay, $y' = -y$ from $y(0) = 1$, whose solution is $e^{-t}$:

```cesia
use std/ode
s = result.Unwrap(ode.Solve((t, y) -> -y, [0.0, 1.0], 1.0))
s.At(0.5) -->
math.Exp(-0.5) -->
s.Stats -->
```

A system has several components: `y` is an array, and `f` gives an array of the same shape. The Lorenz system, a model
of convection whose solutions never settle and never repeat:

```cesia
use std/value
sigma = 10.0
rho = 28.0
beta = 8.0 / 3.0
lorenz(t, y) = [sigma * (y[2] - y[1]), y[1] * (rho - y[3]) - y[2], y[1] * y[2] - beta * y[3]]
l = result.Unwrap(ode.Solve(lorenz, [0.0, 50.0], [1.0, 1.0, 1.0]))
l.At(2.5) -->
value.Size(l.Y) -->
```

The same in Python, R and MATLAB, at the same tolerances:

```python
from scipy.integrate import solve_ivp
sigma, rho, beta = 10.0, 28.0, 8.0 / 3.0
def lorenz(t, y):
    return [sigma * (y[1] - y[0]), y[0] * (rho - y[2]) - y[1], y[0] * y[1] - beta * y[2]]
sol = solve_ivp(lorenz, (0, 50), [1, 1, 1], rtol=1e-6, atol=1e-9, dense_output=True)
sol.sol(2.5)   # [-6.95961709, -7.27253256, 24.70314841]
```

```r
# deSolve, a package of CRAN: install.packages("deSolve"). Not run here: the machine that builds this page lacks it.
library(deSolve)
lorenz <- function(t, y, p) list(c(10 * (y[2] - y[1]), y[1] * (28 - y[3]) - y[2], y[1] * y[2] - 8 / 3 * y[3]))
out <- ode(c(1, 1, 1), c(0, 2.5, 50), lorenz, NULL, method = "ode45", rtol = 1e-6, atol = 1e-9)
out[2, ]
```

```matlab
sigma = 10; rho = 28; beta = 8 / 3;
lorenz = @(t, y) [sigma * (y(2) - y(1)); y(1) * (rho - y(3)) - y(2); y(1) * y(2) - beta * y(3)];
opts = odeset('RelTol', 1e-6, 'AbsTol', 1e-9);
[t, y] = ode45(lorenz, [0 2.5 50], [1 1 1], opts);
y(2, :)
```

### The solution

`Solve` gives an `Ok` of an [ode.Solution]:

| Field | What it holds | MATLAB | scipy |
|---|---|---|---|
| `T` | the times, a column | `t` | `sol.t` |
| `Y` | the states, one row for each time, one column for each component | `y` | `sol.y.T` |
| `s.At(t)` | the state at any time `t` of the solution, or a matrix as `Y` for an array of times | `deval(sol, t)` | `sol.sol(t)` |
| `Events` | the events met, in time order | `te`, `ye`, `ie` | `sol.t_events`, `sol.y_events` |
| `Stats` | `Steps`, `Rejected`, `Evaluations`, and `Jacobians` and `Factorizations`, 0 for this method | `sol.stats` | `sol.nfev` |

With two times, `[t0, t1]`, `T` holds the times of the steps the method took. With three or more, increasing or
decreasing, `T` holds those times and `Y` the states there, from the same steps, so `At` gives the same numbers either
way. Times that decrease solve back in time. A column of `Y` is what [plot.Line] takes: `plot.Line(s.T, s.Y[:, 1])`.

### Tolerances

`rtol = 1e-6` and `atol = 1e-9` are the defaults: about six correct digits, where MATLAB and scipy default to three
(`1e-3` and `1e-6`). `atol` is a number or an array, one for each component, for components of very different scales.
`maxStep` bounds the size of a step, and `steps`, a million by default, bounds their count, refused ones included.

What a tolerance promises needs care. At each step the method estimates the error it makes in that step, the *local
error*, and takes the step only when the root mean square of that estimate, each component divided by
$\text{atol} + \text{rtol} \cdot |y|$, is at most 1. The error of the whole solution, the *global error*, adds up the
local errors as the equation carries them along: no method bounds it in general. What holds, and the tests of Cesia
check, is *tolerance proportionality*: the global error falls about as fast as the tolerance. On Kepler's orbit at an
eccentricity of 0.5, after three turns, the error of the position is 30 to 65 times `rtol` from `1e-7` down to
`1e-12`, 270 times at `1e-5` and 320 times at `1e-3`. On a *chaotic* system, as Lorenz's, a small error grows exponentially with time: at `t = 12.5`,
the three solvers of this page give `x` = -11.891, -11.889 and -11.893 at the defaults, and the true value is -11.896.
A smaller `rtol` pushes that horizon later, not away.

### Events

An [ode.Event] watches a function `g(t, y)` along the solution and records each time it crosses 0: a ball reaching the
ground, a planet crossing a plane. `stop = true` ends the solution there; `direction` is `"both"`, `"up"` for `g` going
from below 0 to above, or `"down"`.

```cesia
fall(t, y) = [y[2], -9.81]
ground = ode.Event((t, y) -> y[1], stop = true, direction = "down")
b = result.Unwrap(ode.Solve(fall, [0.0, 10.0], [10.0, 0.0], events = [ground]))
b.Events -->
math.Sqrt(20.0 / 9.81) -->
```

After each step, Solve compares the sign of each `g` at both ends of the step; a change is located by [optimize.Root]
on the dense output of the step, to the last bits of `t`. Each event gives `Event`, its place in the list, `T` and `Y`.
A `g` that is 0 at the first time is no event, as Shampine and Thompson (2000) advise, so that a solve started from an
event doesn't stop at once. Two crossings of the same `g` inside one step cancel and are missed, as in MATLAB and
scipy: `maxStep` makes the steps short enough to see them.

```python
def ground(t, y):
    return y[0]
ground.terminal = True
ground.direction = -1
b = solve_ivp(lambda t, y: [y[1], -9.81], (0, 10), [10, 0], events=ground, rtol=1e-6, atol=1e-9)
b.t_events[0][0]   # 1.4278431229270643
```

```matlab
function [value, isterminal, direction] = ground(t, y)
  value = y(1); isterminal = 1; direction = -1;
end
opts = odeset('RelTol', 1e-6, 'AbsTol', 1e-9, 'Events', @ground);
[t, y, te, ye, ie] = ode45(@(t, y) [y(2); -9.81], [0 10], [10 0], opts);
te   % 1.427843122927064
```

### When it fails

Solve gives an `Err` of kind `"ode"` with `T`, the time it reached, `Message`, and `Partial`, the solution up to `T`,
which can still be plotted:

- the step falls under $16 \epsilon |t|$: the solution blows up, or has a singularity, there;
- `steps` is reached;
- `f` gives a NaN or an infinity: the step is halved and tried again, 10 times, then the message names the component;
- `f` gives a value of another shape than `y0`, or no number;
- the problem looks *stiff*, below.

$y' = y^2$ from $y(0) = 1$ is $1 / (1 - t)$, which goes to infinity at $t = 1$:

```cesia
blow = ode.Solve((t, y) -> y * y, [0.0, 2.0], 1.0)
blow.Error.T -->
p = match blow
  result.Ok(s) -> s
  result.Err(e) -> e.Partial
end
p.Stats.Steps -->
```

MATLAB and scipy give a warning and a solution that ends early; a program that reads only the solution misses it.

A bad argument, as `rtol = 0.0`, times that don't increase or decrease, a `y0` with a NaN, is a bug of the caller: a
panic that names it. So is `s.At(t)` outside the solution.

### Stiff problems

Some systems mix fast and slow changes: a chemical reaction where one species reacts in microseconds and another in
hours. They are *stiff*: once the fast change has died out, the solution is smooth, yet a method like this one must keep
its steps as small as the fast change, or its errors grow without bound. It then takes millions of tiny steps, each
accurate, as if the problem were hard, when it is the method that is wrong for it. Van der Pol's oscillator at
$\mu = 1000$ is the classic example:

```cesia
vdp(t, y) = [y[2], 1000.0 * (1.0 - y[1] * y[1]) * y[2] - y[1]]
v = ode.Solve(vdp, [0.0, 3000.0], [2.0, 0.0])
v.Error.Message -->
v.Error.Partial.Stats.Steps -->
```

MATLAB's `ode45` and scipy's `RK45` say nothing, and take minutes. Solve watches for it: the test of Hairer and Wanner,
after Shampine (1977), estimates $h |\lambda|$, the step times the largest rate of change along the step, from the last
two stages of the step, which are at the same time. Past 3.25 the step is at the edge of what the method can take
without its errors growing; on 15 such steps, without 6 calm steps in a row between them, Solve stops and says so. It
tries the test every 1,000 steps, and at each step once one is past. A method made for stiff problems is the next part
of Cesia's numerical methods.

### The method

Solve uses the method of Dormand and Prince (1980), the one of MATLAB's `ode45` and scipy's `RK45`. It is a
*Runge–Kutta method*: each step from $t$ to $t + h$ evaluates $f$ at 7 *stages*, $k_i = f(t + c_i h, y + h \sum_j a_{ij}
k_j)$, and combines them into $y_1 = y + h \sum_i b_i k_i$, which matches the Taylor series of the solution up to $h^5$:
it is of *order 5*. The numbers $a$, $b$ and $c$ are the paper's. Another combination, $z_1 = y + h \sum_i
\beta_i k_i$, is of order 4, and their difference estimates the error of the step at no cost. The last stage is
$f(t + h, y_1)$, the first stage of the next step, so a step costs 6 calls of `f`.

- **The error test**, as Hairer, Nørsett and Wanner give it (I, §II.4): $\text{err} = \sqrt{\frac{1}{n} \sum_i
  ((y_{1,i} - z_{1,i}) / \text{sc}_i)^2}$ with $\text{sc}_i = \text{atol}_i + \text{rtol} \cdot \max(|y_i|,
  |y_{1,i}|)$; the step is taken when $\text{err} \le 1$.
- **The next step**, by the PI control of Gustafsson (1991) as DOPRI5 has it: $h_\text{new} = h \cdot \min(10,
  \max(0.2, 0.9 \cdot \text{err}^{-0.17} \cdot \text{err}_{\text{prev}}^{0.04}))$, no larger right after a refused step.
  The second factor, from the previous step's error, smooths the sequence of steps; Söderlind (2003) explains why.
- **The first step**, by the rule of Gladwell, Shampine and Brankin (1987): the step over which Euler's method moves `y`
  by 1 % of its scale, then bounded by an estimate of the second derivative, from one more call of `f`.
- **The dense output** of Shampine (1986): a polynomial of degree 4 in each step, from the stages already computed,
  which meets the step's states at both ends; `At` evaluates it, and the error of a state between two steps is of the
  order of the method's own. It needs the stages of every step: $6n + 2$ floats a step, 160 bytes for Lorenz.

Cesia's tests check the method itself: the 17 conditions of order 5 on $b$ and the 8 of order 4 on $\beta$, to the last
bits; the dense output's order 4 at several points of a step; the solver's first step against a step computed here with
the paper's table; and then problems with known solutions: the decay, a rotation, the logistic equation, Kepler's orbits
at eccentricities 0.1 to 0.9, the invariants of a spinning rigid body, the orbit of Arenstorf that closes after
17.0652165601579625588917206249, a solve forward then back.

### In a cell

In a file of [cells](cells.md), each cell runs alone and the graphs show under it in Cemacs. A slider on `rho` would run
the solve and the graph again as it moves:

```cesia norun
use std/num
use std/ode
use std/plot
use std/result

(* %% Lorenz *)
sigma = 10.0
rho = 28.0
beta = 8.0 / 3.0
lorenz(t, y) = [sigma * (y[2] - y[1]), y[1] * (rho - y[3]) - y[2], y[1] * y[2] - beta * y[3]]
s = result.Unwrap(ode.Solve(lorenz, [0.0, 50.0], [1.0, 1.0, 1.0]))
s.Stats

(* %% Graph *)
ts = num.Linspace(0.0, 50.0, 5000)
ys = s.At(ts)
plot.Grid([plot.Of([plot.Line(ts, ys[:, 1])], x = "t", y = "x"),
           plot.Of([plot.Line(ys[:, 1], ys[:, 3])], x = "x", y = "z")], columns = 2)
```

The same graph, made here and drawn to SVG:

```cesia
use std/num
use std/plot
ts = num.Linspace(0.0, 50.0, 5000)
ys = l.At(ts)
g = plot.Grid([plot.Of([plot.Line(ts, ys[:, 1])], x = "t", y = "x"), plot.Of([plot.Line(ys[:, 1], ys[:, 3])], x = "x", y = "z")], columns = 2)
plot.Svg(g) then result.IsOk() -->
```

### Speed of Solve

The Lorenz system on `[0, 100]` at `rtol = 1e-8` and `atol = 1e-10`, and on `[0, 50]` at the defaults, the solve
alone, inside each program: the median of 21 runs of each, alternated, and the 95 % interval of that median, on the
machine of [Speed](speed.md#beside-the-giants), with other work running on it, on 2026-11-13. The programs are in the
text of this section; MATLAB was not measured, as no MATLAB was at hand.

| | `[0, 100]`, `1e-8` | `[0, 50]`, defaults |
|---|---:|---:|
| **Cesia**, `cesia run` | **127 ms** (118 to 145) | **21.1 ms** (20.6 to 24.5) |
| **Cesia**, in a cell of a session | **125 ms** (121 to 139) | |
| scipy 1.18.1, `solve_ivp`, RK45 | 681 ms (624 to 761) | 138 ms (129 to 159) |
| GNU Octave 11.3, `ode45` | 8,827 ms (8,188 to 11,051) | 1,167 ms (1,142 to 1,530) |

The three use the same method, at the same tolerances, and do about the same work: on `[0, 100]`, Cesia takes 11,412
steps and calls `f` 69,002 times, scipy 10,859 steps and 67,214 calls, Octave 12,855 steps and 77,593 calls. Cesia is
5 times faster than scipy and 70 times faster than Octave. On five more problems, the orbits of Arenstorf and Kepler and
Van der Pol's oscillator at $\mu = 10$, Cesia calls `f` within 6 % as often as scipy.

Each step is 6 calls of `f` and about 58 operations on arrays of 3 floats, and both run in the interpreter: the JIT
of [Speed](speed.md#what-becomes-machine-code) doesn't yet make machine code of a loop that makes arrays, as `[a, b, c]`,
or computes on whole arrays, as `y + h * k`, so a top-level `f`, a closure and the `f` of a cell all cost the same:
about 11 µs a step, 1.5 of them in the 6 calls of `f`, each array operation about 75 ns. The aim for the first solve, 60 ms, waits for a JIT that lowers that code.

`use std/ode` adds 3.6 ms to the start of a program (the median of 21 runs: 6.48 ms against 2.63 for a program that
prints 1), the time to read its code and that of std/optimize, which it uses; `use std/optimize` alone adds 0.45 ms. A
program that uses neither starts as before.

## Security

`f`, `g` and the functions given to Root are code of the caller, so the methods check what they give: a value of the
wrong shape, a text, a NaN or an infinity is an `Err` that names it, never a crash inside the solver. Every loop is
bounded: Root by its 60 steps of search and by the bracket, which halves at least every few steps; Solve by `steps`.
Every loop is Cesia code, so [cells.Stop] stops a long solve within a step, and `--limit` applies, as to any program.
The memory of a solve grows with its steps, by blocks of 128 steps; past the memory limit of the program, the program
stops with `Limit "memory" reached.`

## Further reading

- Richard P. Brent. *Algorithms for Minimization without Derivatives*. Prentice-Hall, 1973; Dover, 2002. Chapter 4:
  the zero of a function. The author's page: <https://maths-people.anu.edu.au/~brent/pub/pub011.html>.
- Richard P. Brent. "An algorithm with guaranteed convergence for finding a zero of a function". *The Computer Journal*
  14(4):422–425, 1971. <https://doi.org/10.1093/comjnl/14.4.422>.
- G. E. Alefeld, F. A. Potra, Yixun Shi. "Algorithm 748: Enclosing Zeros of Continuous Functions". *ACM Transactions on
  Mathematical Software* 21(3):327–344, 1995. <https://doi.org/10.1145/210089.210111>. Their test problems.
- J. R. Dormand, P. J. Prince. "A family of embedded Runge-Kutta formulae". *Journal of Computational and Applied
  Mathematics* 6(1):19–26, 1980. <https://doi.org/10.1016/0771-050X(80)90013-3>. The method, RK5(4)7M.
- Lawrence F. Shampine. "Some practical Runge-Kutta formulas". *Mathematics of Computation* 46(173):135–150, 1986.
  <https://doi.org/10.1090/S0025-5718-1986-0815836-3>. The dense output.
- Ernst Hairer, Syvert P. Nørsett, Gerhard Wanner. *Solving Ordinary Differential Equations I: Nonstiff Problems*,
  second edition. Springer, 1993. <https://doi.org/10.1007/978-3-540-78862-1>. The error test, the first step, the dense
  output of DOPRI5, the Arenstorf orbit.
- Ernst Hairer, Gerhard Wanner. *Solving Ordinary Differential Equations II: Stiff and Differential-Algebraic
  Problems*, second edition. Springer, 1996. <https://doi.org/10.1007/978-3-642-05221-7>. The PI control of DOPRI5 and
  its test of stiffness.
- Kjell Gustafsson. "Control theoretic techniques for stepsize selection in explicit Runge-Kutta methods". *ACM
  Transactions on Mathematical Software* 17(4):533–554, 1991. <https://doi.org/10.1145/210232.210242>.
- Gustaf Söderlind. "Digital filters in adaptive time-stepping". *ACM Transactions on Mathematical Software*
  29(1):1–26, 2003. <https://doi.org/10.1145/641876.641877>.
- I. Gladwell, L. F. Shampine, R. W. Brankin. "Automatic selection of the initial step size for an ODE solver". *Journal
  of Computational and Applied Mathematics* 18(2):175–192, 1987. <https://doi.org/10.1016/0377-0427(87)90015-X>.
- L. F. Shampine. "Stiffness and Nonstiff Differential Equation Solvers, II: Detecting Stiffness with Runge-Kutta
  Methods". *ACM Transactions on Mathematical Software* 3(1):44–53, 1977. <https://doi.org/10.1145/355719.355722>.
- L. F. Shampine, S. Thompson. "Event location for ordinary differential equations". *Computers & Mathematics with
  Applications* 39(5–6):43–54, 2000. <https://doi.org/10.1016/S0898-1221(00)00045-6>.

## Next

You can find zeros and solve differential equations. The next chapter, [JSON and CSV](json.md), reads data from other
programs and writes it for them.
