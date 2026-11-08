# Lists and arrays

In this chapter you hold many values in one: a list of names, a column of numbers, a matrix. You read them, add to them,
sort them, and compute with whole arrays at once.

## Lists

A list sits between square brackets. Its elements can be of any kind, and the first one is at position 1:

```cesia
use std/value
names = ["Ana", "Bo", "Cyril"]
names[1] -->
names[3] -->
value.Len(names) -->
```

`names[1]` is short for [list.Nth]`(1, names)`:

```cesia
use std/list
list.Nth(1, names) --> names[1]
```

### Outside the list

A position outside the list is an error, which names the size of the list:

```cesia fails
names[5]
```

[list.First] and [list.Last] read the ends, and give `missing` for an empty list instead of stopping.

```cesia
list.Last(names) -->
list.First([]) -->
```

## Adding and taking

[list.Append] gives a new list with one more element at the end. [list.Concat] joins two lists, [list.Take] keeps the first elements and
[list.Skip] leaves them out:

```cesia
list.Append("Dee", names) -->
list.Concat([1, 2], [3, 4]) -->
list.Take(2, names) -->
list.Skip(1, names) -->
```

As with every value, the list you give is unchanged, [immutable](glossary.md#immutability):

```cesia
more = list.Append("Dee", names)
value.Len(names) -->
value.Len(more) -->
```

### Building a list in a loop

A list grows well one element at a time, so building one in a loop is the usual way. A list that nothing else holds
keeps free cells behind its last element, doubled when they run out, so each [list.Append] costs a constant time on
average, an *amortized* constant:

```cesia
squares = []
for n in 1..5
  squares = list.Append(n * n, squares)
end
squares -->
```

### Changing one element

To change one element, give its position. Only this name sees the change:

```cesia
scores = [10, 20, 30]
scores[2] = 25
scores -->
```

## Ranges

`a..b` is the list of the integers from `a` to `b`, both included. It is short for [list.Range]`(a, b)`, which also takes a step:

```cesia
1..5 -->
list.Range(1, 5) --> 1..5
list.Range(0, 1, step = 0.25) -->
list.Sum(1..100) -->
```

### A part of a list

In the brackets of a list, a range takes a part of it, and `end` is its last position. These are short for [list.Take] and
[list.Skip]:

```cesia
names[1..2] --> list.Take(2, names)
names[2..end] --> list.Skip(1, names)
```

## Sorting

[list.Sort] puts the elements in increasing order, numbers or texts. [list.SortBy] sorts by what a function gives for each element, here
the length of each name. [list.Reverse] turns a list around:

```cesia
list.Sort([3, 1, 2]) -->
list.Sort(["pear", "apple", "fig"]) -->
list.SortBy(value.Len, ["pear", "apple", "fig"]) -->
list.Reverse([1, 2, 3]) -->
```

Both keep equal elements in the order they had.

### Unique and IndexOf

[list.Unique] leaves out repeats, and [list.IndexOf] finds where a value is, or gives `missing`:

```cesia
list.Unique([1, 2, 1, 3, 2]) -->
list.IndexOf("Bo", names) -->
```

### in

`x in xs` asks whether a value is an element of a list. It is short for asking [list.IndexOf] for a position:

```cesia
"Bo" in names -->
"Zoe" in names -->
"Bo" in names --> value.IsSome(list.IndexOf("Bo", names))
```

## Whole arrays at once

An array of numbers computes element by element, a [vectorized operation](glossary.md#vectorized-operation): no loop
to write. An operator between two arrays of the same size works on
each pair, and a number with an array works on each element:

```cesia
use std/math
prices = [10, 20, 30]
prices * 2 -->
prices + [1, 2, 3] -->
math.Sqrt([1, 4, 9]) -->
```

### Comparing whole lists

A comparison works on each pair too: `==` between two lists gives a list of `true` and `false`. To ask whether two lists
are the same as a whole, [value.Equal] gives one answer:

```cesia
prices == [10, 25, 30] -->
value.Equal(prices, [10, 20, 30]) -->
```

### One number from an array

[list.Sum], [list.Mean], [list.Min] and [list.Max] reduce an array to one number:

```cesia
list.Sum(prices) -->
list.Mean(prices) -->
list.Max(prices) -->
```

This is also the fast way: the work runs in a loop of the machine, not one step of the program per element.

## Matrices

A matrix writes its rows separated by `;`. Two positions read one element: the row, then the column. [value.Size] gives the rows and
the columns:

```cesia
use std/matrix
m = [1, 2; 3, 4]
m[2, 1] -->
value.Size(m) -->
matrix.Transpose(m) -->
```

[matrix.Matmul] is the matrix product, in floats:

```cesia
matrix.Matmul(m, m) -->
```

For more, such as solving a system of equations, the library `std/num` has [num.Solve] and its friends; the chapter on data
comes back to it.

## Arrays of more dimensions

A field of temperatures in space, or a stack of images, is an array of three dimensions or more. [matrix.Zeros],
[matrix.Ones] and [list.Fill] take one size for each dimension, and an element takes one position for each:

```cesia
a = matrix.Zeros(2, 3, 4)
a[1, 2, 3] = 5.0
a[1, 2, 3] -->
value.Size(a) -->
```

The elements follow each other column by column: the first position moves fastest. This is *column-major order*, as in
Fortran, MATLAB, R and Julia; C and numpy keep rows together instead, *row-major*. One position alone counts in that
order, as in a matrix:

```cesia
a[15] -->
```

Such an array isn't written in the code: [matrix.Reshape] gives the elements of a list the shape of a list of sizes. It
shows each matrix of its first two dimensions, then `;;;` before the next along the third, and `;;;;` along the fourth:

```cesia
c = matrix.Reshape([2, 2, 2], 1..8)
c -->
matrix.Reshape([2, 4], c) -->
```

A wrong count of positions says how many the array takes:

```cesia fails
c[1, 2]
```

Arithmetic and comparisons work element by element, as on a matrix, between arrays of the same sizes or with a number:

```cesia
c * 2 -->
c > 4 -->
```

### Sums along a dimension

[list.Sum] with `dim` adds along that dimension, which the result no longer has: along the third dimension of a 2 by 2
by 2 array, a 2 by 2 matrix. On a matrix, `dim = 1` gives the sum of each column and `dim = 2` of each row, both as lists.
[list.Mean] takes `dim` too:

```cesia
list.Sum(c, dim = 3) -->
list.Sum(m, dim = 1) -->
list.Sum(m, dim = 2) -->
list.Mean(c, dim = 1) -->
```

[matrix.Matmul] and [matrix.Transpose] stay on matrices. [json.Text] writes an array of more dimensions as lists in lists,
the first position outermost.

## More of std/list

| To | Use |
|---|---|
| read | [list.Second], [list.TakeLast], [list.DropLast], [list.TakeWhile], [list.DropWhile] |
| add | [list.Prepend] at the front, [list.Interleave] two lists in turn, [list.Interpose] a separator between elements, [list.Flatten] lists of lists into one |
| make | [list.Repeatedly] the results of a function, [list.Iterate] `x`, `f(x)`, `f(f(x))`... |
| change | [list.MapIndexed] with the position, [list.FlatMap] and join, [list.Keep] the results that aren't `missing`, [list.Remove] the elements a test refuses |
| ask | [list.Any] of a list of booleans, [list.MinBy] by a function, [list.Order] the positions that sort it |

```cesia
use std/text
list.Prepend(0, [1, 2]) -->
list.Interpose(", ", ["a", "b", "c"]) -->
list.Flatten([[1, 2], [3]]) -->
list.Iterate(it * 2, 1, 5) -->
list.MapIndexed((k, x) -> "$k:$x", ["a", "b"]) -->
list.Keep(text.Number, ["1", "x", "3"]) -->
list.Order([30, 10, 20]) -->
list.Any([false, true]) -->
```

### What each costs

| Operation | Cost |
|---|---|
| `xs[k]`, `value.Len(xs)` | constant |
| `xs[k] = v`, [list.Append] on a list nothing else holds | constant, amortized for Append |
| the same on a list that is shared | a copy of the list, once, then constant |
| [list.Concat], [list.Take], [list.Skip], [list.Map], [list.Filter] | linear: a new list |
| [list.Sort], [list.SortBy], [list.Order] | `O(n log n)`, stable: equal elements keep their order |
| `x in xs`, [list.IndexOf] | linear: a search from the start |

## Next

You can hold and compute with many values. The next chapter, [Choices and loops](choices.md), decides what runs and how often.
