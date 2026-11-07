# Data

In this chapter you work on many records at once: you compute a value for each, keep some, group them, count them, and rank
them. Then you load a CSV file into a table of columns and ask the same questions in a few lines. The data is a bakery's sales
over four days, in `sales.csv`.

## Records in a list

A list of dictionaries is the simplest table: one dictionary per row, the same keys in each.

```cesia
use std/value
sales = [
  {City: "Lyon", Product: "bread", Units: 12, Price: 1.25},
  {City: "Paris", Product: "bread", Units: 30, Price: 1.5},
  {City: "Lyon", Product: "cake", Units: 3, Price: 8.0},
  {City: "Paris", Product: "cake", Units: 5, Price: 9.0},
  {City: "Lille", Product: "bread", Units: 8, Price: 1.25}
]
value.Len(sales) -->
```

## Comprehensions

A [comprehension](glossary.md#comprehension) builds a list from another: the value for each element, then `for`, then, if you want, `if` and a condition.

```cesia
[s.Units * s.Price for s in sales] -->
[s.City for s in sales if s.Units > 6] -->
```

A comprehension is short for [list.Map] and [list.Filter]:

```cesia
use std/list
[s.City for s in sales if s.Units > 6] --> list.Map(s -> s.City, list.Filter(s -> s.Units > 6, sales))
```

## Sums, counts and ranks

The functions of the chapter on lists work on the values a comprehension gives. [list.Frequencies] counts each value, [list.Unique]
keeps the first of each, and [list.Top] gives the largest, here by a key:

```cesia
list.Sum([s.Units for s in sales]) -->
list.Frequencies([s.City for s in sales]) -->
list.Unique([s.Product for s in sales]) -->
list.Top(2, sales, by = it.Units) -->
```

### MaxBy and Scan

[list.MaxBy] gives the element with the largest value of a function, and [list.Scan] each step of a running total:

```cesia
list.MaxBy(s -> s.Units * s.Price, sales) -->
list.Scan((total, s) -> total + s.Units, 0, sales) -->
```

## Groups

[list.Group] puts together the elements with the same key, in the order the keys first appear. Each group has its `Key`, and the
`Values` that have it:

```cesia
list.Group(it.City, sales) then list.Map(g -> {City: g.Key, Rows: value.Len(g.Values)}) -->
```

### One value per group

With a `summary`, each group becomes one value, so a total per city takes one line:

```cesia
list.Group(it.City, sales, summary = rows -> list.Sum([s.Units for s in rows])) -->
```

### Zip and Zipmap

[list.Zip] pairs two lists, element by element, and [dict.Zipmap] turns two of them into a dictionary:

```cesia
use std/dict
list.Zip(["Lyon", "Paris"], [15, 35]) -->
dict.Zipmap(["Lyon", "Paris"], [15, 35]) -->
```

## A table from a CSV file

For more rows, [std/frame] keeps a table as columns, which is called [columnar data](glossary.md#columnar-data): one list
per column, and a column of numbers stored without boxes, so
that sums and filters run on whole columns at once. [frame.FromCsv] reads the text of a CSV file whose first row names the
columns. An empty cell is `missing`, and a number is read as a number. Here is `sales.csv`:

```text
day,city,product,units,price
2026-10-01,Lyon,bread,12,1.25
2026-10-01,Paris,bread,30,1.5
2026-10-01,Lyon,cake,3,8.0
2026-10-02,Paris,cake,5,9.0
2026-10-02,Lille,bread,8,1.25
2026-10-02,Lyon,bread,15,1.25
2026-10-03,Paris,bread,22,1.5
2026-10-03,Lille,cake,2,7.5
2026-10-03,Lyon,cake,4,8.0
2026-10-04,Paris,cake,6,9.0
```

It reads in one line:

```cesia allow=read
use std/sys
use std/frame
use std/io
use std/result
df = frame.FromCsv(result.Unwrap(sys.Read("sales.csv")))
frame.RowCount(df) -->
frame.Columns(df) -->
io.Print(frame.Show(frame.Head(3, df)))
```

A frame is a value, as everything in Cesia: each function gives a new one, and `df` stays as it was.

## Asking a table

[frame.WithColumn] adds a column computed from each row, [frame.Where] keeps the rows a function accepts, and [frame.Select]
keeps some columns:

```cesia allow=read
withTotal = frame.WithColumn("total", r -> r.units * r.price, df)
lyon = frame.Where(r -> r.city == "Lyon", withTotal)
io.Print(frame.Show(frame.Select(["day", "product", "total"], lyon)))
```

### Groups of rows

[frame.GroupBy] makes one row per value of its columns, and a column for each [frame.Agg]: a new name, the column it reads,
and the function of its values. [frame.SortBy] orders the rows:

```cesia allow=read
byCity = frame.GroupBy(["city"], [frame.Agg("units", "units", list.Sum), frame.Agg("rows", "day", value.Len)], df)
io.Print(frame.Show(frame.SortBy("units", byCity, descending = true)))
```

### Whole columns

A column is a list, and the operators of the language work on a whole list at once, a
[vectorized operation](glossary.md#vectorized-operation): `units * 2` doubles each element, and
`units > 10` gives a list of `true` and `false` that [frame.WhereMask] uses to keep rows:

```cesia allow=read
units = frame.Column("units", df)
units * 2 -->
list.Mean(units) -->
frame.RowCount(frame.WhereMask(units > 10, df)) -->
```

### Back to CSV

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

## Random samples

[std/random] draws numbers for samples, games and simulations. [random.Int] gives a whole number between two, both included,
[random.Float] a float from 0 up to 1, [random.Pick] an element of a list, and [random.Shuffle] the list in another order:

```cesia
use std/random
roll = random.Int(1, 6)
roll >= 1 and roll <= 6 -->
random.Float() < 1 -->
random.Pick(["tea", "coffee"]) in ["tea", "coffee"] -->
list.Sort(random.Shuffle([3, 1, 2])) -->
```

### The same numbers again

Each run takes a new [seed](glossary.md#seed) from the system, so it draws other numbers. [random.Seed] tells the seed of a
run, and `cesia run --seed N` runs again with the seed N, so with the same numbers: a simulation that went wrong can be
replayed. A seed gives the same numbers on every system and every version of Cesia.

```cesia norun
(* dice.ce: how many rolls of two dice until a double six *)
use std/random
use std/io
use std/list
use std/text

defn rolls()
  n = 1
  while random.Int(1, 6) + random.Int(1, 6) != 12
    n = n + 1
  end
  n
end

games = [rolls() for k in 1..10000]
io.Print("seed $(random.Seed()): $(text.Decimals(2, list.Mean(games))) rolls on average")
```

```bash
cesia run dice.ce             # seed 712762694: 35.57 rolls on average
cesia run --seed 42 dice.ce   # the same numbers at each run
```

These numbers are for samples and games, never for secrets: a password or a key comes from [std/crypto].

## Next

You can ask questions of your data. The next chapter, [JSON and CSV](json.md), reads data from other programs and writes it for them,
and checks what comes in.
