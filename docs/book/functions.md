# Functions

In this chapter you write your own functions, short and long, and give them defaults and named arguments. Then you pass
functions to other functions, [higher-order functions](glossary.md#higher-order-function), which is how Cesia works on lists: [list.Map], [list.Filter] and [list.Reduce].

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
use std/math
defn describe(n)
  kind = if math.Mod(n, 2) == 0 "even" else "odd" end
  "$n is $kind"
end
describe(7) -->
```

### return

[return] gives a value at once, and leaves the function. It suits a search that can stop early:

```cesia
use std/value
defn firstLong(words)
  for w in words
    if value.Len(w) > 4
      return w
    end
  end
  missing
end
firstLong(["a", "tree", "forest", "sea"]) -->
firstLong(["a"]) -->
```

### A function that calls itself

A function can call itself, which is called *recursion*:

```cesia
factorial(n) = if n <= 1 1 else n * factorial(n - 1) end
factorial(10) -->
```

Each call waits for the one it made, so the calls pile up: 10,000 at most by default, the `depth` limit of
[Permissions](permissions.md#limit), past which the program stops at the line of the call. A call whose result is the
function's own result, with nothing left to do after it, is in *tail position*: `countDown(n - 1)` below. A function that
calls itself there runs as a loop, in one frame, so it has no depth limit. In `factorial`, the `n * ...` is left to do
after the call, so that call is not in tail position.

```cesia
countDown(n) = if n == 0 "done" else countDown(n - 1) end
countDown(1000000) -->
```

## Names inside a function

A name given a value inside a function is its own: a name of the same spelling outside keeps its value. A function sees its
parameters, its own names and the names of its file, the ones written around it: this is called
[lexical scope](glossary.md#lexical-scope). An `if` or a `for` makes no scope of its own.

```cesia
kind = "none"
describe(4) -->
kind -->
```

A function that only computes from its arguments, as `double`, is a [pure function](glossary.md#pure-function): the same
arguments always give the same value.

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
a name, an [anonymous function](glossary.md#anonymous-function). Its parameters come before `->`, and its value after it:

```cesia
inc = x -> x + 1
inc(4) -->
add = (a, b) -> a + b
add(2, 3) -->
```

### Several lines

A function without a name can hold several lines: `defn`, its parameters in parentheses, and its lines up to `end`. It is
the long form of `->`, as `defn` is the long form of `=`:

```cesia
longInc = defn (x)
  y = x + 1
  y
end
longInc(4) --> inc(4)
```

### Closures

A function made inside another one keeps the names it saw there, with the values they had: it is a
[closure](glossary.md#closure). Here `adder` makes functions that each remember their `n`:

```cesia
adder(n) = x -> x + n
addTen = adder(10)
addTen(5) -->
adder(100)(1) -->
```

A closure keeps the *values* of those names, as they were when it was made, which is called *capture by value*. A name
given another value later doesn't change the closure. In JavaScript and Python, a closure captures the *variable* itself,
and sees its later values: there, the last line below would give 2.

```cesia
count = 1
show = () -> count
count = 2
show() --> 1
```

## Map, Filter and Reduce

These three take a function first, and the list last. [list.Map] applies the function to each element, [list.Filter] keeps the elements
for which it gives true, and [list.Reduce] folds the list into one value, from a start:

```cesia
use std/list
numbers = [1, 2, 3, 4, 5]
list.Map(double, numbers) -->
list.Filter(x -> x > 2, numbers) -->
list.Reduce((total, x) -> total + x, 0, numbers) -->
```

### More of them

Many more work the same way: [list.SortBy], [list.Count], [list.FindFirst], [list.Group], [list.TakeWhile]. Each has its page in the reference.

```cesia
list.Count(x -> x > 2, numbers) -->
list.FindFirst(x -> x > 2, numbers) -->
```

### Functions of functions

[std/fn] makes functions from functions. [fn.Compose] chains them, the last first; [fn.Complement] gives the opposite of a
test; [fn.Juxt] gives the results of several functions on one value; [fn.Constantly] makes a function that gives one
value whatever its argument, and [fn.Identity] gives its argument back:

```cesia
use std/fn
fn.Compose(math.Inc, it * 2)(3) --> math.Inc(3 * 2)
list.Filter(fn.Complement(math.IsOdd), numbers) -->
fn.Juxt(list.Min, list.Max)(numbers) -->
list.Map(fn.Constantly(0), numbers) -->
fn.Identity(5) -->
```

## it

For a short function of one parameter, [it] saves writing it, as `it` does in Kotlin: an argument that holds `it` is a function of `it`.
`list.Map(it * 2, numbers)` is short for `list.Map(x -> x * 2, numbers)`:

```cesia
list.Map(it * 2, numbers) -->
list.Map(it * 2, numbers) --> list.Map(x -> x * 2, numbers)
list.Filter(it > 3, numbers) --> list.Filter(x -> x > 3, numbers)
```

## then

[then] passes the value on its left to the call on its right: a *pipeline operator*, as `|>` in F#, Elixir and
OCaml. The value takes the place of an argument that is `it` alone;
when there is none, it becomes the last argument. As the list comes last in these functions, a step only names what to do,
so `it` alone is needed only where the value doesn't go last:

```cesia
numbers then list.Filter(math.IsOdd) then list.Map(it * 10) then list.Sum() -->
100 then math.Div(it, 7) --> math.Div(100, 7)
```

A chain of steps reads from left to right, in the order they happen. It is short for calls inside calls, which read from
the inside out:

```cesia
numbers then list.Filter(math.IsOdd) then list.Map(it * 10) then list.Sum() --> list.Sum(list.Map(x -> x * 10, list.Filter(math.IsOdd, numbers)))
```

## A small program

Functions make a program out of small parts. Here, a few lines of scores become a ranking:

```cesia
use std/io
use std/text
raw = "ana 12\nbo 7\ncyril 15\ndee 9"
defn parse(line)
  parts = text.Split(" ", line)
  {Name: parts[1], Score: text.Number(parts[2])}
end
players = list.Map(parse, text.Lines(raw))
best = list.SortBy(p -> -p.Score, players)
for p in list.Take(3, best)
  io.Print(text.PadRight(6, " ", p.Name), p.Score)
end
```

The braces in `parse` make a dictionary with the keys `Name` and `Score`, and `p.Score` reads one of its keys: the next
chapter is about them.

## Next

You can write functions and pass them around. The next chapter, [Maps](maps.md), holds values under names: `{Name: "Ana", Age: 31}`.
