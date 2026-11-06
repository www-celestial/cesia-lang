# Functions

In this chapter you write your own functions, short and long, and give them defaults and named arguments. Then you pass
functions to other functions, which is how Cesia works on lists: [Map], [Filter] and [Reduce].

## The short form

A function that fits on one line is written as an equation: its name, its parameters, `=`, and the value it gives.

```cesia
double(x) = x * 2
area(width, height) = width * height
double(21) -->
area(3, 4) -->
```

A function is called with its arguments in parentheses, in the order of its parameters. A name that starts with a small letter
is private to its file's package; a capital makes it public, as for any name.

## The long form

[defn] starts a function of several lines, which ends at `end`. It gives the value of its last line. The short form is the
same thing on one line: `double(x) = x * 2` is `defn double(x) x * 2 end`.

```cesia
defn describe(n)
  kind = if Mod(n, 2) == 0 "even" else "odd" end
  "$n is $kind"
end
describe(7) -->
```

[return] gives a value at once, and leaves the function. It suits a search that can stop early:

```cesia
defn firstLong(words)
  for w in words
    if Len(w) > 4
      return w
    end
  end
  missing
end
firstLong(["a", "tree", "forest", "sea"]) -->
firstLong(["a"]) -->
```

A function can call itself:

```cesia
factorial(n) = if n <= 1 1 else n * factorial(n - 1) end
factorial(10) -->
```

## Defaults and named arguments

A parameter can have a default, used when the call leaves it out. A call can also name its arguments, in any order: this keeps a
call with many of them readable.

```cesia
greet(name, greeting = "Hello") = "$greeting, $name!"
greet("Ana") -->
greet("Bo", greeting = "Hi") -->
greet(greeting = "Welcome", name = "Cyril") -->
```

## Functions as values

A function is a value: you can name it, keep it in a list, and pass it to another function. `x -> x + 1` is a function without
a name. Its parameters come before `->`, and its value after it:

```cesia
inc = x -> x + 1
inc(4) -->
add = (a, b) -> a + b
add(2, 3) -->
```

A function made inside another one keeps the names it saw there. Here `adder` makes functions that each remember their `n`:

```cesia
adder(n) = x -> x + n
addTen = adder(10)
addTen(5) -->
adder(100)(1) -->
```

## Map, Filter and Reduce

These three take a function first, and the list last. [Map] applies the function to each element, [Filter] keeps the elements
for which it gives true, and [Reduce] folds the list into one value, from a start:

```cesia
numbers = [1, 2, 3, 4, 5]
Map(double, numbers) -->
Filter(x -> x > 2, numbers) -->
Reduce((total, x) -> total + x, 0, numbers) -->
```

Many more work the same way: [SortBy], [Count], [FindFirst], [Group], [Every]. Each has its page in the reference.

```cesia
Count(x -> x > 2, numbers) -->
FindFirst(x -> x > 2, numbers) -->
```

## it

For a short function of one parameter, [it] saves writing it: an argument that holds `it` is a function of `it`.
`Map(it * 2, numbers)` is short for `Map(x -> x * 2, numbers)`:

```cesia
Map(it * 2, numbers) -->
Map(it * 2, numbers) --> Map(x -> x * 2, numbers)
Filter(it > 3, numbers) --> Filter(x -> x > 3, numbers)
```

## then

[then] passes the value on its left to the call on its right. The value takes the place of an argument that is `it` alone;
when there is none, it becomes the last argument. As the list comes last in these functions, a step only names what to do:

```cesia
numbers then Filter(IsOdd) then Map(it * 10) then Sum(it) -->
```

A chain of steps reads from left to right, in the order they happen. It is short for calls inside calls, which read from
the inside out:

```cesia
numbers then Filter(IsOdd) then Map(it * 10) then Sum(it) --> Sum(Map(x -> x * 10, Filter(IsOdd, numbers)))
```

## A small program

Functions make a program out of small parts. Here, a few lines of scores become a ranking:

```cesia
raw = "ana 12\nbo 7\ncyril 15\ndee 9"
defn parse(line)
  parts = Split(" ", line)
  {Name: parts[1], Score: Number(parts[2])}
end
players = Map(parse, Lines(raw))
best = SortBy(p -> -p.Score, players)
for p in Take(3, best)
  Print(PadRight(6, " ", p.Name), p.Score)
end
```

`{Name: ..., Score: ...}` is a dictionary, and `p.Score` reads one of its keys: the next chapter is about them.

## Next

You can write functions and pass them around. The next chapter, Maps, holds values under names: `{Name: "Ana", Age: 31}`.
