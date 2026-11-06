# Lists and arrays

In this chapter you hold many values in one: a list of names, a column of numbers, a matrix. You read them, add to them,
sort them, and compute with whole arrays at once.

## Lists

A list sits between square brackets. Its elements can be of any kind, and the first one is at position 1:

```cesia
names = ["Ana", "Bo", "Cyril"]
names[1] -->
names[3] -->
Len(names) -->
```

A position outside the list is an error, which names the size of the list:

```cesia fails
names[5]
```

[First] and [Last] read the ends, and give `missing` for an empty list instead of stopping.

```cesia
Last(names) -->
First([]) -->
```

## Adding and taking

[Append] gives a new list with one more element at the end. [Concat] joins two lists, [Take] keeps the first elements and
[Skip] leaves them out:

```cesia
Append("Dee", names) -->
Concat([1, 2], [3, 4]) -->
Take(2, names) -->
Skip(1, names) -->
```

As with every value, the list you give is unchanged:

```cesia
more = Append("Dee", names)
Len(names) -->
Len(more) -->
```

A list grows well one element at a time, so building one in a loop is the usual way:

```cesia
squares = []
for n in 1:5
  squares = Append(n * n, squares)
end
squares -->
```

To change one element, give its position. Only this name sees the change:

```cesia
scores = [10, 20, 30]
scores[2] = 25
scores -->
```

## Ranges

`a:b` is the list of the integers from `a` to `b`, both included. [Range] takes a step:

```cesia
1:5 -->
Range(0, 1, 0.25) -->
Sum(1:100) -->
```

## Sorting

[Sort] puts the elements in increasing order, numbers or texts. [SortBy] sorts by what a function gives for each element, here
the length of each name. [Reverse] turns a list around:

```cesia
Sort([3, 1, 2]) -->
Sort(["pear", "apple", "fig"]) -->
SortBy(Len, ["pear", "apple", "fig"]) -->
Reverse([1, 2, 3]) -->
```

Both keep equal elements in the order they had. [Unique] leaves out repeats, and [IndexOf] finds where a value is:

```cesia
Unique([1, 2, 1, 3, 2]) -->
IndexOf("Bo", names) -->
```

## Whole arrays at once

An array of numbers computes element by element: no loop to write. An operator between two arrays of the same size works on
each pair, and a number with an array works on each element:

```cesia
prices = [10, 20, 30]
prices * 2 -->
prices + [1, 2, 3] -->
Sqrt([1, 4, 9]) -->
```

[Sum], [Mean], [Min] and [Max] reduce an array to one number:

```cesia
Sum(prices) -->
Mean(prices) -->
Max(prices) -->
```

This is also the fast way: the work runs in a loop of the machine, not one step of the program per element.

## Matrices

A matrix writes its rows separated by `;`. Two positions read one element: the row, then the column. [Size] gives the rows and
the columns:

```cesia
m = [1, 2; 3, 4]
m[2, 1] -->
Size(m) -->
Transpose(m) -->
```

[Matmul] is the matrix product, in floats:

```cesia
Matmul(m, m) -->
```

For more, such as solving a system of equations, the library `pkg/num` has [num.Solve] and its friends; the chapter on data
comes back to it.

## Next

You can hold and compute with many values. The next chapter, [Choices and loops](choices.md), decides what runs and how often.
