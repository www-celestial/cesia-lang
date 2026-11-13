# Numerical methods

In this chapter you find where a function is zero, with [optimize.Root], you solve differential equations, with
[ode.Solve], and you compute integrals, with [quad.Integral]: what `fzero`, `ode45` and `integral` do in MATLAB,
`brentq`, `solve_ivp` and `quad` in scipy. Each method comes from a paper,
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
scipy's `brentq` and `fzero`, run in GNU Octave, stop one float away from it at their defaults, and R's `uniroot` needs
`tol` to get there.

### From one start

With one number instead of a bracket, Root looks for a bracket first: points on both sides of the start, 2 % of it away
(0.02 for 0), then twice as far at each step, at most 60 steps, until `f` changes sign. A side where `f` gives no finite
number, as `math.Log` of a negative number, stops there, and the other goes on:

```cesia
optimize.Root(x -> math.Cos(x) - x, 1.0).Value.X -->
optimize.Root(x -> math.Log(x) - 1.0, 0.01).Value.X -->
math.Exp(1.0) -->
```

`fzero(f, x0)` also searches for a bracket from one start; scipy's `brentq` has no search, and needs the bracket.

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
| `Stats` | `Steps`, `Rejected`, `Evaluations`, and with `stiff = true` `Jacobians` and `Factorizations`, 0 otherwise | `sol.stats` | `sol.nfev`, `sol.njev`, `sol.nlu` |

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
- the problem looks *stiff*, below;
- with `stiff = true`, `jacobian` gives a value that is no `n × n` matrix of finite numbers, or a Jacobian by
  differences holds a NaN or an infinity, or the matrix $I - h\gamma J$ of a step stays singular as the step is halved
  10 times.

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
tries the test every 1,000 steps, and at each step once one is past. Its message says what to do: `stiff = true`, a
method made for stiff problems, which takes some hundred steps where this one would take millions:

```cesia
w = result.Unwrap(ode.Solve(vdp, [0.0, 3000.0], [2.0, 0.0], stiff = true))
w.Stats -->
w.At(3000.0) -->
```

The same in Python, R and MATLAB, at the same tolerances. MATLAB's `ode15s` and `ode23s`, and scipy's `Radau`, `BDF`
and `LSODA`, are their methods for stiff problems; Cesia has one, chosen by measure, below.

```python
sol = solve_ivp(lambda t, y: [y[1], 1000 * (1 - y[0] ** 2) * y[1] - y[0]], (0, 3000), [2, 0], method="Radau",
                rtol=1e-6, atol=1e-9)
sol.y[:, -1]   # [-1.51060692e+00, 1.17838003e-03]
```

```r
library(deSolve)
vdp <- function(t, y, p) list(c(y[2], 1000 * (1 - y[1]^2) * y[2] - y[1]))
out <- ode(c(2, 0), c(0, 3000), vdp, NULL, method = "rodas", rtol = 1e-6, atol = 1e-9)
out[2, ]
```

```matlab
vdp = @(t, y) [y(2); 1000 * (1 - y(1)^2) * y(2) - y(1)];
opts = odeset('RelTol', 1e-6, 'AbsTol', 1e-9);
[t, y] = ode15s(vdp, [0 3000], [2 0], opts);
y(end, :)
```

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

### The method for stiff problems

With `stiff = true`, Solve uses Rodas5P (Steinebach 2023), a *Rosenbrock method* (Hairer and Wanner II, §IV.7). Where
an explicit method like Dormand and Prince's takes each stage from the stages before it, a Rosenbrock method solves, at
each stage, a linear system with the matrix $W = I - h\gamma J$, where $J = f_y$ is the *Jacobian* of `f` at the start
of the step: the $n \times n$ matrix of how each component of $f$ changes with each component of $y$. A fast component, which decays at a rate $\lambda$ far below 0, has its change divided by about $1 -
h\gamma\lambda$, so its error dies out whatever the step: the method is *L-stable*, its factor of growth $R(z)$ at most
1 for every $z = h\lambda$ whose real part is below 0, and 0 as $z$ goes to $-\infty$. The steps then follow the slow
part of the solution only.

In the form with the stages $u_i$ that the code RODAS of Hairer and Wanner uses, for a step from $t$ to $t + h$, with
$f_t$ the derivative of $f$ in $t$:

$$
(I - h\gamma J)\, u_i = h\gamma\, f(t + c_i h,\; y + \sum_{j<i} a_{ij} u_j) + h^2 \gamma\, d_i\, f_t + \gamma \sum_{j<i} c_{ij} u_j
$$

Rodas5P has 8 stages and $\gamma = 0.21193756319429014$; its numbers $a$, $c$ and $d$ are those Steinebach publishes
with the Julia package OrdinaryDiffEq.jl. $y_1 = y + \sum_j a_{8j} u_j + u_8$ is of order 5; $y + \sum_j a_{8j} u_j$,
the argument of the last stage, is of order 4, so $u_8$ estimates the error of the step. A step costs one Jacobian, one
factorization of $W$ by [num.Lu], 8 solves with it and 8 calls of `f`. There is no Newton iteration, as in the implicit
methods (`ode15s`, `Radau`, `BDF`), so no iteration that can fail to converge.

- **The Jacobian**: `jacobian = (t, y) -> J` gives it, an `n × n` matrix, or a number for a number `y0`. Without it,
  Solve computes each column $j$ by a forward difference, from one more call of `f` with $y_j$ moved by
  $\delta_j = \sqrt{\epsilon} \max(|y_j|, \text{atol}_j)$: the rule of Dennis and Schnabel (1996) for finite
  differences, with $\text{atol}_j$ as the typical size of $y_j$, under which the error test sees no difference
  ($\sqrt{\epsilon}$ when both are 0). The rule of the code RODAS, $\sqrt{\epsilon \max(|y_j|, 10^{-5})}$, moves
  $y_2$ of Robertson's problem, about $10^{-13}$, by 400 times its own size: the Jacobian comes out 200 times too large in one place, and the solve
  takes 4 times more steps, to an answer 15 % off. $f_t$ comes from one more difference, over
  $\sqrt{\epsilon} |h|$, the scale the step resolves. Without `jacobian`, a step calls `f` $n + 1$ more times.
- **The next step**: $h_\text{new} = h \cdot \min(6, \max(0.2, 0.9 \cdot \text{err}^{-1/5}))$, or smaller by the
  *predictive control* of Gustafsson (1994), as in RODAS, $h \cdot 0.9 \cdot (h / h_\text{prev})^{-1} \cdot
  (\text{err}^2 / \text{err}_\text{prev})^{-1/5}$, which follows the trend of the last two steps. On Van der Pol's
  oscillator at $\mu = 1000$, it refuses 23 steps instead of 176.
- **The dense output**: Steinebach's, a polynomial of degree 4 in each step, from its stages, which meets the states at
  both ends. The error test sees only those ends. Where a fast decay follows a slow forcing, as in $y' = \lambda (y -
  \cos t) - \sin t$ with $\lambda = -10^6$ (Prothero and Robinson 1974), the method puts each end on $\cos t$ whatever
  the step: the steps grow to 3.4 at `rtol = 1e-6`, and `At` between them is off by 5 %. `maxStep` bounds the steps
  where the values between them matter: with `maxStep = 0.05`, `At` is right to `1e-8`.
- **The size**: `y0` has at most 1,000 components with `stiff = true`; $J$, $W$ and its factors are $n \times n$
  matrices, 8 MB each at 1,000.

Cesia's tests check the method itself: both tables, Rodas5P and Rodas4 (Hairer and Wanner 1996: 6 stages, order 4),
against the conditions of order on every rooted tree up to order 5, as Steinebach's Table 2 lists them for Rosenbrock
methods; their embedded methods, of one order less and not more; their dense outputs; the orders seen as the
step halves, 4.0 and 5.9; the solver's first step against a step computed in the test, and Rodas4, written in the test,
as an oracle; then the decay, the problem of Prothero and Robinson, a linear system with rates $-1$, $-10^3$ and
$-10^6$, Robertson's reactions, HIRES and OREGO (Hairer and Wanner II, §IV.10) against references computed for the tests
by scipy's `Radau` at `rtol = 1e-13`, tolerance proportionality, events, shapes and every error.

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

With `stiff = true`, measured the same way: Robertson's problem on `[0, 1e11]` at `rtol = 1e-6` and `atol = 1e-10`
takes 207 steps and **15.2 ms** (14.2 to 25.0), Van der Pol's at $\mu = 1000$ on `[0, 3000]` at `rtol = atol = 1e-6`
536 steps and **29.1 ms** (27.4 to 33.1); scipy's `Radau`, at `atol = 1e-9`, takes 1,292 steps on the second. Solved
again in the same program, once the JIT has made `f` native, a step of Robertson's costs about 38 µs: the Jacobian by
differences, the factorization of $W$ and its 8 solves run as native code in about 10 µs of them, and the rest is the
loop of the stages in the interpreter. On a 1-D diffusion of 100 points, 53 steps take 70 ms with `jacobian` given, and
100 ms by differences, which call `f` 100 more times a step. The comparison with scipy's `Radau`, `BDF` and `LSODA` and
with Octave's `ode15s` waits for the measures made before each release.

`use std/ode` adds to the start of a program the time to read its code and that of std/optimize and std/num, which it
uses: 1.3 ms in the fastest of 21 runs (4.15 ms against 2.86 for a program that prints 1, on 2026-11-13), more on a
busy machine; `use std/optimize` alone adds 0.45 ms. A program that uses neither starts as before.

## Integrals

[quad.Integral] computes the *integral* of a function `f` from `a` to `b`: the area under its curve, counted below 0
where the curve is. It is what `integral` does in MATLAB and `quad` in scipy. Here the integral of $x^{-1/2} \log(1/x)$
from 0 to 1, which is 4, of a function that grows without bound at 0:

```cesia
use std/quad
logRoot(x) = x ^ (-0.5) * math.Log(1.0 / x)
q = result.Unwrap(quad.Integral(logRoot, 0.0, 1.0))
q -->
```

`Value` is the integral, `Error` the estimate of its error, `Evaluations` the calls of `f`, and `Intervals` the pieces
the interval was cut into. `x -> ...` is a function written in place: `quad.Integral(x -> x * x, 0.0, 3.0)` is the same
as defining `square(x) = x * x` and giving `square`. The same in Python, R and MATLAB, at the same tolerances:

```python
import math
from scipy.integrate import quad
y, err, info = quad(lambda x: x**-0.5 * math.log(1 / x), 0, 1, epsabs=1e-12, epsrel=1e-10, full_output=1)
# 4.000000000000071, 2.1582735598713043e-13, info['neval'] 315, info['last'] 8
```

```r
integrate(function(x) x^(-0.5) * log(1 / x), 0, 1, rel.tol = 1e-10, abs.tol = 1e-12)
# 4.0000000000000711, 8 subdivisions
```

```matlab
q = integral(@(x) x.^(-0.5) .* log(1 ./ x), 0, 1, 'RelTol', 1e-10, 'AbsTol', 1e-12)
% 3.999999999976525 in GNU Octave
```

scipy's `quad` and R's `integrate` run QUADPACK's own code, whose method Cesia follows: the same value to the last bit,
from the same 315 calls of `f`. MATLAB's `integral` is another method (Shampine 2008), and GNU Octave's calls `quadcc`,
the rules of Clenshaw and Curtis that Gonnet (2010) made adaptive, which stops here 2.3e-11 from 4.

| Cesia | MATLAB | scipy |
|---|---|---|
| `quad.Integral(f, a, b)` | `integral(f, a, b)` | `quad(f, a, b)` |
| `math.Inf`, `-math.Inf` as a bound | `Inf`, `-Inf` | `np.inf`, `-np.inf` |
| `rtol = 1e-10`, `atol = 1e-12`, the defaults | `'RelTol', 1e-6`, `'AbsTol', 1e-10` | `epsrel=1.49e-8`, `epsabs=1.49e-8` |
| `points = [c1, c2]` | `'Waypoints', [c1 c2]` | `points=[c1, c2]` |
| `limit = 1000` pieces | `'MaxIntervalCount', 650` | `limit=50` |
| `q.Value`, `q.Error` | `[q, errbnd] = quadgk(...)` | `y, abserr = quad(...)` |

`f` takes one number and gives one number, so any function works, one with an `if` too; MATLAB's `integral` calls `f`
on arrays of points instead. `f` can itself call Integral: a double integral is two nested calls, here the area of the
disk of radius 1, $\pi$, the integral from -1 to 1 of its chord at $x$, itself the integral of 1 from $-\sqrt{1 - x^2}$ to
$\sqrt{1 - x^2}$:

```cesia
chord(x) = quad.Integral(y -> 1.0, -math.Sqrt(1.0 - x * x), math.Sqrt(1.0 - x * x)).Value.Value
quad.Integral(chord, -1.0, 1.0).Value.Value -->
```

`quad.Integral(...).Value` is what the `Ok` holds, the struct, so `.Value.Value` is the integral itself; in a program,
`result.Unwrap` or `?` reads better.

### Infinite bounds

A bound can be [math.Inf] or `-math.Inf`, which is `1.0 / 0.0` and its negative:

```cesia
bell(x) = math.Exp(-x * x)
quad.Integral(bell, -math.Inf, math.Inf).Value -->
math.Sqrt(math.Pi) -->
quad.Integral(x -> math.Exp(-x), 0.0, math.Inf).Value.Value -->
```

The change of variable $x = a + (1 - t) / t$ maps $[a, \infty)$ onto $(0, 1]$, with $dx = -dt / t^2$: the integral of
$f(x)$ from $a$ to $\infty$ is the integral of

$$
\frac{1}{t^2} f(a + \frac{1 - t}{t})
$$

from 0 to 1, and the method below works on $(0, 1]$, where it never evaluates $t = 0$. From $-\infty$ to $b$, $x = b - (1 - t) / t$;
from $-\infty$ to $\infty$, $f(x) + f(-x)$ from 0. A function that decays slowly, as $1/x^2$, turns into one with a
singularity at $t = 0$, which the extrapolation below handles. A finite bound far out, as `1e300`, is no infinity: on
$[-10^{300}, 10^{300}]$ the 21 points of the first rule all fall where $e^{-x^2}$ is 0, and Integral gives 0 with an
`Error` of 0. Give `math.Inf` for an infinite interval.

### Places where f jumps

`points` lists the places between `a` and `b` where `f` jumps, has a kink, or is singular: the first pieces end there,
and none of them has the trouble inside. A step at 0.3:

```cesia
step(x) = if x < 0.3 1.0 else 2.0 end
quad.Integral(step, 0.0, 1.0).Value -->
quad.Integral(step, 0.0, 1.0, points = [0.3]).Value -->
```

Without `points` the method finds the jump itself, cutting the pieces around it smaller and smaller: 357 calls of `f`.
With them, the two pieces are exact at once: 42 calls. Points outside the interval are a panic; points equal to `a` or
`b` are left out, and a point given twice counts once. With an infinite bound, split the integral at a point in two
calls.

### What it promises

`Integral` gives an `Ok` when `Error` is at most `max(atol, rtol |Value|)`: with the defaults, 10 digits, or `1e-12`
near 0. `Error` is an estimate, from the method's own test, not a bound. On a smooth function it is pessimistic: the
true error is often far smaller. It can be fooled by a feature that no point of the rule sees, as a peak narrower than
the gaps between them, the way any method that only samples `f` can.

The tests of Cesia check it on 42 integrals of the kinds that the QUADPACK book tests its methods on, each against its
closed form: $x^\alpha \log(1/x)$ and $x^{-1/2}$, singular at an end; $|x - 1/3|^\alpha$, singular inside, with and
without `points`; a peak of width $4^{-\alpha}$, $\alpha$ up to 8; $(1 - x^2)^{-1/2} / (x + 1 + 2^{-\alpha})$, singular at
both ends beside a pole; $\sin^{\alpha - 1} x$ and $\log(1/x)^{\alpha - 1}$, whose integrals are values of the functions
[special.Beta] and [special.Gamma]; $x^\alpha e^{-x}$ and $e^{-x^2}$ on infinite intervals; an oscillation, $x \sin 30x
\cos x$ on $[0, 2\pi]$; a jump; reversed intervals. On each, the true error is within the tolerance and within `Error`;
and each takes exactly as many calls of `f`, and as many pieces, as scipy's `quad` at the same tolerances, with the same
value and the same `Error` to the last bit. GNU Octave's `integral` misses 10 of the 42 by more than the tolerance asked: on $|x - 1/3|^{-0.8}$
by 0.0039, on $(1 + x)^{-1} x^{-1/2}$ over $[0, \infty)$ by 1.3e-8.

### When it fails

An `Err` of kind `"quad"` carries `Value` and `Error`, the best estimates found, and a message that says what to change.
QUADPACK's own tests decide each case:

```cesia
quad.Integral(x -> 1.0 / x, 0.0, 1.0, limit = 20).Error.Message -->
quad.Integral(x -> x ^ (-1.1), 0.0, 1.0).Error -->
quad.Integral(x -> 1.0 / math.Abs(x - (1.0e10 + 1.0 / 3.0)), 1.0e10, 1.0e10 + 1.0).Error.Message -->
quad.Integral(x -> math.Sin(x), 0.0, math.Inf).Error.Message -->
```

- **The limit**: the sum of the errors is still above the tolerance after `limit` pieces.
- **Roundoff**: cutting a piece in two changed its integral by less than $10^{-5}$ of it while its error didn't fall,
  10 times, or made the error grow, 20 times: the tolerance is below what floats can give. `rtol` can't go below
  50 eps, $1.1 \cdot 10^{-14}$, with `atol = 0.0`.
- **A bad place**: a piece became so small that its two halves can't be told apart in floats, as near
  $10^{10} + 1/3$ above, where floats are $2 \cdot 10^{-6}$ apart: $1/|x - s|$ isn't integrable there.
- **The extrapolation**: the table of the epsilon algorithm keeps changing by more than its own estimates, as for
  $\sin x$ on $[0, \infty)$, whose integral has no limit.
- **Divergence**: the extrapolated value and the sum of the pieces differ by more than a factor of 100, or the error is
  above the area. The integral of $x^{-1.1}$ from 0 to 1 is infinite; the extrapolation gives $-10 = 1 / (1 - 1.1)$,
  the value that $1 / (p + 1)$, the integral of $x^p$ for $p > -1$, takes at $p = -1.1$, and the test of divergence
  refuses it. scipy and R give the same
  $-10$ with a warning.
- **What `f` gives**: a NaN, an infinity, a text or anything but a number is an `Err` that names the place:
  `f(0.5) is "a", not a finite number.` A panic inside `f` stays a panic.

Not every non-integrable function is caught. With `points = [1.0 / 3.0]`, $1 / (x - 1/3)$ on $[0, 1]$ gives an `Ok`
of about 0: each side diverges, and the extrapolation of their sum settles on a number, as it does in QUADPACK's code.
Integrate only what has an integral.

### The method of Integral

Integral is QUADPACK's QAGS (Piessens, de Doncker-Kapenga, Überhuber and Kahaner 1983), the method of de Doncker
(1978); with `points`, QAGP; with an infinite bound, QAGI.

- **The rule**: on a piece $[a, b]$, the *Gauss–Kronrod rule* of 21 points, $K = \sum_i w_i f(x_i)$. Ten of its points
  are those of the Gauss rule $G$ of 10 points, the most precise rule on 10 points: it integrates exactly every
  polynomial of degree 19 or less. Kronrod (1965) added 11 points so that the 21 integrate exactly every polynomial of
  degree 31 or less, and $G$ comes free, from 10 of the same values of `f`. The new points are the zeros of the
  *Stieltjes polynomial* $E_{11}$, which is orthogonal to $x^k P_{10}(x)$ for $k = 0, \dots, 10$, $P_{10}$ the Legendre
  polynomial whose zeros are Gauss's points. Cesia's points and weights were computed for it from $E_{11}$ in exact
  rational numbers, its zeros to 100 digits; its tests compute them again by the algorithm of Laurie (1997), as the
  eigenvalues of a tridiagonal matrix, and agree to 2 eps.
- **The error estimate**: $|K - G|$ would be an estimate of the error of $G$; the error of $K$ is far smaller. QUADPACK
  takes $E = I_\text{asc} \min(1, (200 |K - G| / I_\text{asc})^{3/2})$, where $I_\text{asc}$, the integral of $|f - m|$
  over the piece, $m$ the mean of `f` there, measures how much `f` varies: the power $3/2$ makes $E$ fall faster than
  $|K - G|$ as the rule converges, and the factor 200 keeps it on the safe side. $E$ is at least $50 \epsilon$ times the
  integral of $|f|$, what roundoff leaves.
  The terms are added in pairs, $f(c - h x) + f(c + h x)$, so an odd `f` on an interval centred on 0 gives exactly 0.
- **The strategy**: keep the pieces in the order of their errors; cut the one with the largest in two; stop when the
  sum of the errors is at most the tolerance. Near a singularity the pieces get smaller and smaller, and their sums
  converge slowly.
- **The extrapolation**: when the piece of largest error is one of the smallest, as next to a singularity, the method
  first cuts the larger pieces until their errors are below the tolerance, then adds the sum of all the pieces to a
  sequence $S_1, S_2, \dots$, one level of cutting closer to the singularity each time, and estimates its limit by
  the *epsilon algorithm* of Wynn (1956):
  $$
  \epsilon^{(n)}_{-1} = 0, \quad \epsilon^{(n)}_0 = S_n, \quad
  \epsilon^{(n)}_{k+1} = \epsilon^{(n+1)}_{k-1} + \frac{1}{\epsilon^{(n+1)}_k - \epsilon^{(n)}_k}
  $$
  Its even columns $\epsilon_{2k}$ are Shanks's transforms of the sequence: $\epsilon_2$ is Aitken's
  $\Delta^2$, exact on a sequence whose error shrinks by the same factor at each step, and the higher columns remove
  several such terms at once. Near an end singularity such as $x^\alpha$, each level of cutting divides the error of
  the piece at the end by about $2^{\alpha + 1}$: such a sequence. Cesia builds the even
  columns alone by Wynn's *cross rule* (1966), as QUADPACK does, keeps at most 50 sums, and takes as the error of the
  extrapolation the distance to the last three extrapolated values.
- **Infinite bounds**: the change of variable above, and the Gauss–Kronrod rule of 15 points (7 of Gauss's), on
  pieces of $(0, 1]$.

The method runs as native code that calls `f` back, each step as QUADPACK's code takes it, in the same order: the same
method written in Cesia spent six times as long on its own steps as on `f`, and the interpreter can't yet make machine
code of them.

Cesia's tests check, besides the 42 integrals: Laurie's points and weights for both rules; the degrees of the rules,
$x^k$ exact to 4 eps up to $k = 31$ and not at 32, and $G$'s exactness up to 19 seen in the estimate; each `Err` above;
what `f` gives; the bound of the calls of `f` by `limit`, $21 (2\,\text{limit} - 1)$; every bad argument.

### In a cell

In a file of [cells](cells.md), the area under a curve and the curve itself:

```cesia norun
use std/math
use std/num
use std/plot
use std/quad
use std/result

(* %% Integral *)
h(x) = math.Exp(-x * x)
q = result.Unwrap(quad.Integral(h, 0.0, 1.0))
q.Value

(* %% Graph *)
us = num.Linspace(0.0, 1.0, 100)
xs = num.Linspace(-0.5, 1.5, 200)
plot.Of([plot.Area(us, 0.0 * us, h(us), label = "$(q.Value) ± $(q.Error)"), plot.Line(xs, h(xs))])
```

`q.Value` shows 0.7468241328124271, $\frac{\sqrt{\pi}}{2} \text{erf}(1)$. The same graph, made here and drawn to SVG:

```cesia
use std/special
h(x) = math.Exp(-x * x)
qh = result.Unwrap(quad.Integral(h, 0.0, 1.0))
math.Near(qh.Value, math.Sqrt(math.Pi) / 2.0 * special.Erf(1.0)) -->
us = num.Linspace(0.0, 1.0, 100)
xs = num.Linspace(-0.5, 1.5, 200)
plot.Svg(plot.Of([plot.Area(us, 0.0 * us, h(us), label = "$(qh.Value) ± $(qh.Error)"), plot.Line(xs, h(xs))])) then result.IsOk() -->
```

### Speed of Integral

The integral of $x^{-1/2} \log(1/x)$ from 0 to 1 at the defaults, `rtol = 1e-10` and `atol = 1e-12`, 315 calls of `f` in each
language: the median of 21 runs of each, alternated, and the 95 % interval of that median, on the machine of
[Speed](speed.md#beside-the-giants), with other work running on it, on 2026-11-13. A first call is the first in a fresh
program; then the mean of 1,000 calls in the same program.

| | first call | then, each call |
|---|---:|---:|
| **Cesia** | 135 µs (129 to 144) | **46.7 µs** (45.3 to 47.7) |
| scipy 1.18.1, `quad` | **116 µs** (112 to 118) | 82.3 µs (80.0 to 85.6) |
| GNU Octave 11.3, `integral` | | 2,309 µs (2,283 to 2,330) |

Cesia is 1.8 times as fast as scipy once its code is read, and 49 times as fast as Octave, whose `integral` also stops
further from 4, 2.3e-11 away. scipy wins the first call: Cesia reads and prepares the code of std/quad then. The time
goes to the calls of `f`: with `math.Sqrt` as `f`, its integral from 0 to 1 takes 231 calls in 21 µs, about 90 ns each
for the call and the method's own work, and `f`'s own work comes on top. MATLAB was not measured, as no MATLAB was at
hand. `use std/quad` adds no time a program can measure to its start, 2.84 ms against 2.89 for a program
that prints 1, and a program that doesn't use it starts as before.

### Security of Integral

`f` is code of the caller, so Integral checks what it gives: anything but a finite number is an `Err` that names the
place, never a NaN inside the sums. Every loop is bounded: `limit` bounds the pieces, so `f` is called at most
$21 (2\,\text{limit} - 1)$ times, $15 (2\,\text{limit} - 1)$ with one infinite bound and $30 (2\,\text{limit} - 1)$
with two, and a function that never converges ends with the `Err` of the limit, the roundoff, the bad place or the
extrapolation; the table of the epsilon algorithm keeps 50 sums at most. Keeping the pieces in order costs up to `limit`
steps each, so a large `limit` costs time as its square: at 100,000, a function that never settles, $\sin(1/x)$, takes
5 seconds. The memory grows with the pieces, six numbers each, in arrays that double as they fill, from 16: at the
default `limit`, 48 KB. Past the memory limit of the program, the program stops with `Limit "memory" reached.`, as any.
The native code counts its work against `--limit` as it goes, and each call of `f` is Cesia code, so `--limit` and
[cells.Stop] stop a long integral within a few calls of `f`. It reads only the numbers Integral gives it, keeps no state
outside one call, so `f` can call Integral again, and a panic in `f` goes up as a panic. Bad arguments, a NaN bound, a
negative tolerance, `points` outside the interval, are panics that name them, before `f` is called.

### Reading for integrals

- Robert Piessens, Elise de Doncker-Kapenga, Christoph W. Überhuber, David K. Kahaner. *QUADPACK: A Subroutine Package
  for Automatic Integration*. Springer, 1983. <https://doi.org/10.1007/978-3-642-61786-7>. QAGS, QAGP, QAGI, their rules
  and tests; the package's own page: <https://www.netlib.org/quadpack/readme>.
- Elise de Doncker. "An adaptive extrapolation algorithm for automatic integration". *ACM SIGNUM Newsletter*
  13(2):12–18, 1978. <https://doi.org/10.1145/1053402.1053403>. The strategy of QAGS.
- P. Wynn. "On a device for computing the $e_m(S_n)$ transformation". *Mathematical Tables and Other Aids to
  Computation* 10(54):91–96, 1956. <https://doi.org/10.2307/2002183>. The epsilon algorithm.
- P. Wynn. "Upon systems of recursions which obtain among the quotients of the Padé table". *Numerische Mathematik*
  8:264–269, 1966. <https://doi.org/10.1007/BF02162562>. The cross rule.
- A. S. Kronrod. *Nodes and Weights of Quadrature Formulas: Sixteen-Place Tables*. Consultants Bureau, 1965. The rules.
- Dirk P. Laurie. "Calculation of Gauss-Kronrod quadrature rules". *Mathematics of Computation* 66(219):1133–1145, 1997.
  <https://doi.org/10.1090/S0025-5718-97-00861-2>. The rules as eigenvalues, as the tests compute them.
- L. F. Shampine. "Vectorized adaptive quadrature in MATLAB". *Journal of Computational and Applied Mathematics*
  211(2):131–140, 2008. <https://doi.org/10.1016/j.cam.2006.11.021>. MATLAB's `integral`.
- Pedro Gonnet. "Increasing the reliability of adaptive quadrature using explicit interpolants". *ACM Transactions on
  Mathematical Software* 37(3), 2010. <https://doi.org/10.1145/1824801.1824804>. GNU Octave's `quadcc`.

## Security

`f`, `g` and the functions given to Root are code of the caller, so the methods check what they give: a value of the
wrong shape, a text, a NaN or an infinity is an `Err` that names it, never a crash inside the solver. Every loop is
bounded: Root by its 60 steps of search and by the bracket, which halves at least every few steps; Solve by `steps`.
Every loop is Cesia code, so [cells.Stop] stops a long solve within a step, and `--limit` applies, as to any program.
The memory of a solve grows with its steps, by blocks of 128 steps; past the memory limit of the program, the program
stops with `Limit "memory" reached.`

With `stiff = true`, `jacobian` is code of the caller too: what it gives must be an `n × n` matrix of finite numbers,
and a Jacobian by differences is checked the same way, so a NaN never reaches the factorization. `y0` has at most 1,000
components, so its three `n × n` matrices stay under 24 MB; a bigger one is a panic that says so, before anything is
allocated. The elimination of [num.Lu] runs as native code, which counts its work, about $n^3 / 3$ operations, against
`--limit` before it starts, and reads only matrices of numbers whose shape it checks first; a factorization at
$n = 1000$ takes under a second, so `cells.Stop` still answers within a step.

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
- Gerd Steinebach. "Construction of Rosenbrock–Wanner method Rodas5P and numerical benchmarks within the Julia
  Differential Equations package". *BIT Numerical Mathematics* 63:27, 2023. <https://doi.org/10.1007/s10543-023-00967-x>.
  Rodas5P, its dense output, and where its numbers and those of Rodas4 are published. Open access.
- Ernst Hairer, Gerhard Wanner, as above, §IV.7: Rosenbrock methods, their conditions of order and the method Rodas4;
  §IV.10: the stiff test problems, Robertson's, HIRES and OREGO.
- Kjell Gustafsson. "Control-theoretic techniques for stepsize selection in implicit Runge-Kutta methods". *ACM
  Transactions on Mathematical Software* 20(4):496–517, 1994. <https://doi.org/10.1145/198429.198437>. The predictive
  control of the step.
- J. E. Dennis Jr., Robert B. Schnabel. *Numerical Methods for Unconstrained Optimization and Nonlinear Equations*.
  SIAM, 1996 (first published by Prentice-Hall, 1983). <https://doi.org/10.1137/1.9781611971200>. The step of a
  forward difference.
- A. Prothero, A. Robinson. "On the stability and accuracy of one-step methods for solving stiff systems of ordinary
  differential equations". *Mathematics of Computation* 28(125):145–162, 1974.
  <https://doi.org/10.1090/S0025-5718-1974-0331793-2>. Their test problem.

## Next

You can find zeros, solve differential equations and compute integrals. The next chapter, [Statistics](statistics.md), works with
the laws of probability.
