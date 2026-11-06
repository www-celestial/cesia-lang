# Errors

In this chapter you handle what can go wrong: a file that isn't there, a text that isn't a number, input that `From` refuses.
In Cesia an error is a value that a function gives back, as any other result. There is no `try`: you see in the code where
each error goes.

## Ok and Err

A function that can fail gives a result: [Ok] around its value when all went well, or [Err] around what went wrong. `.Value`
reads the one, `.Error` the other:

```cesia
Ok(42) -->
Ok(42).Value -->
Err("no such user").Error -->
```

[sys.Read], for instance, gives the text of a file in an `Ok`, or an `Err` that says why it couldn't. Its error is a dictionary
with a `Kind` and a `Message`:

```cesia allow=read
use std/sys
sys.Read("nowhere.txt") -->
```

Your own functions do the same. Here [Number] gives `missing` for a text that isn't a number, and `age` turns that into an
`Err` with a message for the user:

```cesia
defn age(t)
  n = Number(t)
  if IsMissing(n)
    return Err("not a number: $t")
  end
  Ok(n)
end
age("31") -->
age("old") -->
```

`missing` suits a value that may simply not be there, as a key of a dictionary. An `Err` says that something failed, and why.

## Looking at a result

[match] takes a result apart: `Ok(v)` gives the value its name, `Err(e)` the error.

```cesia
defn describe(t)
  match age(t)
    Ok(n) -> "$n years"
    Err(e) -> "refused: $e"
  end
end
describe("31") -->
describe("old") -->
```

[IsOk] and [IsErr] only ask:

```cesia
IsOk(age("31")) -->
IsErr(age("old")) -->
```

## A default

[UnwrapOr] gives the value of an `Ok`, or a default for an `Err`. Use it when an error has an obvious answer:

```cesia
UnwrapOr(0, age("31")) -->
UnwrapOr(0, age("old")) -->
```

## Passing an error on

Most of the time, a function that meets an error can't do better than give it to its caller. `?` after a result does that: for
an `Ok`, it gives the value, and the function goes on; for an `Err`, the function stops at once and gives that `Err`.

```cesia
defn ageNextYear(t)
  n = age(t)?
  Ok(n + 1)
end
ageNextYear("31") -->
ageNextYear("old") -->
```

`n = age(t)?` is short for these lines, which you can write yourself:

```cesia
defn ageNextYearLong(t)
  r = age(t)
  if IsErr(r)
    return r
  end
  n = r.Value
  Ok(n + 1)
end
ageNextYearLong("31") --> ageNextYear("31")
ageNextYearLong("old") --> ageNextYear("old")
```

`?` works inside a function only, since it leaves one. Used on a value that is no result, it stops the program: the message
says to give a result.

```cesia fails
defn wrong(t)
  n = Number(t)?
  n
end
wrong("3")
```

## Steps on results

A few functions work on a result without taking it apart, and chain with [then]. [MapOk] changes the value of an `Ok`, and
[MapErr] the error of an `Err`. Each leaves the other kind as it is:

```cesia
age("31") then MapOk(it * 12) -->
age("old") then MapOk(it * 12) -->
age("old") then MapErr("age: $it") -->
```

[AndThen] chains a step that can fail too. It runs the function on the value of an `Ok`, and passes an `Err` along:

```cesia
defn adult(n)
  if n < 18
    return Err("too young: $n")
  end
  Ok(n)
end
age("31") then AndThen(adult) -->
age("12") then AndThen(adult) -->
age("old") then AndThen(adult) -->
```

[Collect] turns a list of results into one: an `Ok` of all the values, or the first `Err`. Here a whole column of input is
checked at once:

```cesia
Collect(Map(age, ["31", "12", "40"])) -->
Collect(Map(age, ["31", "old", "?"])) -->
```

## Errors and bugs

An `Err` is for what can happen while the program is right: the user typed a word, the file was deleted. A mistake in the
program itself is a bug, and a bug stops the program at once, with the line and the advice to fix it. You don't handle a bug:
you fix the code.

[Unwrap] takes the value of an `Ok`. Use it only where an `Err` would be a bug, as a file that comes with your program:

```cesia
Unwrap(age("31")) -->
```

```cesia fails
Unwrap(age("old"))
```

[Panic] stops the program with your message, and [Assert] stops it when a condition is false. Both are for what must never
happen:

```cesia fails
Assert(Len([1, 2]) == 3, "the list should have three elements")
```

A reading of a dictionary key that isn't there, a field a struct doesn't have, a denied permission: each of these is a bug too,
and stops the program in the same way.

## Next

Your programs say what went wrong, and where it goes. The next chapter, [Types](types.md), writes down what kind of
value each name holds, and Cesia checks it.
