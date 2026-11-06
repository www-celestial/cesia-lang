# Choices and loops

In this chapter you decide what a program does: with `if`, a part runs only when a condition holds. With `for` and `while`,
a part runs many times. And `match` picks among shapes of data.

## if

[if] runs its body when its condition is true, and `else` runs otherwise. Each part ends at `end`:

```cesia
use std/io
temperature = 31
if temperature > 30
  io.Print("Hot")
else
  io.Print("Fine")
end
```

### else if

`else if` chains more conditions. The first one that holds wins:

```cesia
grade = 72
if grade >= 90
  io.Print("A")
else if grade >= 70
  io.Print("B")
else
  io.Print("C")
end
```

## if gives a value

An `if` is also a value: that of the part that ran. It fits on one line, which replaces the `? :` of other languages:

```cesia
use std/math
n = 4
kind = if math.Mod(n, 2) == 0 "even" else "odd" end
kind -->
```

With no `else`, an `if` whose condition is false gives `missing`:

```cesia
if 1 > 2 "never" end -->
```

## for

[for] runs its body once for each element of a list or a range, in order:

```cesia
for fruit in ["apple", "pear", "fig"]
  io.Print("I like", fruit)
end
```

### Positions

A range gives the positions, when you need them:

```cesia
use std/value
names = ["Ana", "Bo"]
for k in 1..value.Len(names)
  io.Print(k, names[k])
end
```

A name that the loop changes keeps its last value after the loop:

```cesia
total = 0
for x in [5, 10, 15]
  total += x
end
total -->
```

### Building a list with for

In brackets, a `for` builds a list, a [comprehension](glossary.md#comprehension): each element is the value before the `for`. An `if` after it keeps only some of them:

```cesia
[x * x for x in 1..5] -->
[x for x in 1..10 if math.Mod(x, 3) == 0] -->
```

A list built this way is short for [list.Map], and with an `if`, for [list.Filter]. The chapter [Functions](functions.md) shows both:

```cesia
use std/list
[x * x for x in 1..5] --> list.Map(x -> x * x, 1..5)
[x for x in 1..10 if math.Mod(x, 3) == 0] --> list.Filter(x -> math.Mod(x, 3) == 0, 1..10)
```

## while and break

[while] runs its body as long as its condition holds. It checks the condition before each turn:

```cesia
n = 1
while n < 100
  n *= 2
end
n -->
```

### break

[break] leaves the loop at once, from `for` or `while`. Here the loop stops at the first number over 10:

```cesia
for x in [3, 8, 12, 5, 20]
  if x > 10
    io.Print("First over 10:", x)
    break
  end
end
```

## match

[match] compares a value with patterns, in order, and gives the value of the first one that fits: this is
[pattern matching](glossary.md#pattern-matching). A pattern can be a value,
and `else` takes what no pattern took:

```cesia
day(n) = match n
  6 -> "Saturday"
  7 -> "Sunday"
  else -> "a weekday"
end
day(7) -->
day(3) -->
```

### Shapes

A pattern can also be a shape. It takes the value apart and gives names to its pieces, which is called
[destructuring](glossary.md#destructuring). `[a, b]` fits a list of two elements,
and `{Name: n}` a dictionary with that key:

```cesia
describe(x) = match x
  [] -> "an empty list"
  [a, b] -> "a pair: $a and $b"
  {Name: n} -> "someone called $n"
  else -> "something else"
end
describe([1, 2]) -->
describe({Name: "Ana"}) -->
describe(42) -->
```

### Conditions and _

An `if` after a pattern adds a condition, and `_` fits anything without naming it:

```cesia
sign(n) = match n
  0 -> "zero"
  x if x < 0 -> "negative"
  _ -> "positive"
end
sign(-5) -->
sign(8) -->
```

A name in a pattern always takes a new value: it never compares with a variable of the same name. To compare with a variable,
use an `if`.

### When nothing fits

When no pattern fits and there is no `else`, the program stops, and names the value that nothing took. A forgotten case shows at
once, instead of giving a wrong answer later:

```cesia fails
match 7
  1 -> "one"
  2 -> "two"
end
```

`match` also takes the results of the chapter on errors apart: `result.Ok(value)` and `result.Err(e)` are patterns too.

## Next

You can choose and repeat. The next chapter, [Functions](functions.md), gives a name to a piece of work, so that you can call
it again.
