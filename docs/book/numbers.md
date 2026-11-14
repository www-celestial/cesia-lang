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
[math.IsEven] and [math.IsOdd]. Each function of one number also works on an array, element by element.

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
left for a positive count, right for a negative one:

```cesia
math.BitAnd(12, 10) -->
math.BitOr(12, 10) -->
math.BitXor(12, 10) -->
math.BitShift(1, 4) -->
math.BitShift(16, -2) -->
```

```python
print(12 & 10)
print(12 | 10)
print(12 ^ 10)
print(1 << 4)
print(16 >> 2)
```

```r
print(bitwAnd(12L, 10L))
print(bitwOr(12L, 10L))
print(bitwXor(12L, 10L))
print(bitwShiftL(1L, 4L))
print(bitwShiftR(16L, 2L))
```

```matlab
disp(bitand(12, 10))
disp(bitor(12, 10))
disp(bitxor(12, 10))
disp(bitshift(1, 4))
disp(bitshift(16, -2))
```

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

Each with its link in [References](references.md#data-and-numbers).

## Next

You can compute with numbers and structures. The next chapter, [Graphs](graphs.md), draws what you compute.
