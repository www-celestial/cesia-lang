# Data

In this chapter you work on many records at once: you compute a value for each, keep some, group them, count them, and rank
them. Then you load a CSV file into a table of columns and ask the same questions in a few lines. The data is a bakery's sales
over four days, in `sales.csv`.

## Records in a list

A list of dictionaries is the simplest table: one dictionary per row, the same keys in each.

```cesia
sales = [
  {City: "Lyon", Product: "bread", Units: 12, Price: 1.25},
  {City: "Paris", Product: "bread", Units: 30, Price: 1.5},
  {City: "Lyon", Product: "cake", Units: 3, Price: 8.0},
  {City: "Paris", Product: "cake", Units: 5, Price: 9.0},
  {City: "Lille", Product: "bread", Units: 8, Price: 1.25}
]
Len(sales) -->
```

## Comprehensions

A comprehension builds a list from another: the value for each element, then `for`, then, if you want, `if` and a condition.

```cesia
[s.Units * s.Price for s in sales] -->
[s.City for s in sales if s.Units > 6] -->
```

A comprehension is short for [Map] and [Filter]:

```cesia
[s.City for s in sales if s.Units > 6] --> Map(s -> s.City, Filter(s -> s.Units > 6, sales))
```

## Sums, counts and ranks

The functions of the chapter on lists work on the values a comprehension gives. [Frequencies] counts each value, [Unique]
keeps the first of each, and [Top] gives the largest, here by a key:

```cesia
Sum([s.Units for s in sales]) -->
Frequencies([s.City for s in sales]) -->
Unique([s.Product for s in sales]) -->
Top(2, sales, by = it.Units) -->
```

[MaxBy] gives the element with the largest value of a function, and [Scan] each step of a running total:

```cesia
MaxBy(s -> s.Units * s.Price, sales) -->
Scan((total, s) -> total + s.Units, 0, sales) -->
```

## Groups

[Group] puts together the elements with the same key, in the order the keys first appear. Each group is a `{Key, Values}`:

```cesia
Group(it.City, sales) then Map(g -> {City: g.Key, Rows: Len(g.Values)}, it) -->
```

With a `summary`, each group becomes one value, so a total per city takes one line:

```cesia
Group(it.City, sales, summary = rows -> Sum([s.Units for s in rows])) -->
```

[Zip] pairs two lists, element by element, and [Zipmap] turns two of them into a dictionary:

```cesia
Zip(["Lyon", "Paris"], [15, 35]) -->
Zipmap(["Lyon", "Paris"], [15, 35]) -->
```

## A table from a CSV file

For more rows, [std/frame] keeps a table as columns: one list per column, and a column of numbers stored without boxes, so
that sums and filters run on whole columns at once. [frame.FromCsv] reads the text of a CSV file whose first row names the
columns. An empty cell is `missing`, and a number is read as a number:

```cesia allow=read
use std/sys
use std/frame
df = frame.FromCsv(Unwrap(sys.Read("sales.csv")))
frame.Rows(df) -->
frame.Columns(df) -->
Print(frame.Show(frame.Head(3, df)))
```

A frame is a value, as everything in Cesia: each function gives a new one, and `df` stays as it was.

## Asking a table

[frame.WithColumn] adds a column computed from each row, [frame.Where] keeps the rows a function accepts, and [frame.Select]
keeps some columns:

```cesia allow=read
withTotal = frame.WithColumn("total", r -> r.units * r.price, df)
lyon = frame.Where(r -> r.city == "Lyon", withTotal)
Print(frame.Show(frame.Select(["day", "product", "total"], lyon)))
```

[frame.GroupBy] makes one row per value of its columns, and a column for each [frame.Agg]: a new name, the column it reads,
and the function of its values. [frame.SortBy] orders the rows:

```cesia allow=read
byCity = frame.GroupBy(["city"], [frame.Agg("units", "units", Sum), frame.Agg("rows", "day", Len)], df)
Print(frame.Show(frame.SortBy("units", byCity, descending = true)))
```

A column is a list, and the operators of the language work on a whole list at once: `units * 2` doubles each element, and
`units > 10` gives a list of `true` and `false` that [frame.WhereMask] uses to keep rows:

```cesia allow=read
units = frame.Column("units", df)
units * 2 -->
Mean(units) -->
frame.Rows(frame.WhereMask(units > 10, df)) -->
```

[frame.ToCsv] writes a frame back as CSV text, for [sys.Write]:

```cesia allow=read
frame.ToCsv(frame.Head(2, byCity)) -->
```

## Numbers

For numerical work, [std/num] adds what numpy gives in Python: statistics such as [num.Median] and [num.Std], linear algebra
such as [num.Solve], and fits such as [num.Polyfit].

```cesia allow=read
use std/num
num.Median(units) -->
num.Std(units) -->
num.Polyfit(1, [1.0, 2.0, 3.0], [3.0, 5.0, 7.0]) -->
```

## Next

You can ask questions of your data. The next chapter, JSON and CSV, reads data from other programs and writes it for them,
and checks what comes in.
