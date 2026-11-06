# Types

In this chapter you write down what kind of value a name holds: a mass that is a `Float`, a name that is a `Text` or
`missing`, a parameter that must be a shape. Types are a plus in Cesia, which is called
[optional typing](glossary.md#optional-typing). You can leave them out everywhere, and code without
them runs just as fast. Where you write one, Cesia checks it each time a value comes in, and the type tells the reader what
goes there.

## A type after a name

A type comes after the name of a field or of a parameter. The type of a function's result comes after its parameters, as in
Go:

```cesia
struct Car
  Mass Float
  Speed Float = 0.0   (** metres per second *)
end

Half(x Float) Float = x / 2

defn Describe(c Car, unit Text = "kg") Text
  "$(c.Mass) $unit"
end

Describe(Car(1200.5)) -->
Half(3.0) -->
```

The types are `Int`, `Float`, `Number` for an `Int` or a `Float`, `Bool`, `Text`, `Array`, `Dict`, `Function`, your structs,
and the interfaces further down.

## Checked when a value comes in

A field is checked when the struct is built and each time the field is written. A parameter is checked at each call, and a
result each time the function gives one. A value of the wrong type is a bug: the program stops and says which name wanted
what.

```cesia fails
Half("ten")
```

```cesia fails
c = Car(1000.0)
c.Mass = "heavy"
```

```cesia fails
defn label(n Int) Text
  n * 2
end
label(4)
```

### A type that names nothing

A type that names nothing is caught before the program starts:

```cesia fails
weigh(c Cr) = c.Mass
```

## An Int becomes a Float

An `Int` where a `Float` is wanted becomes a `Float`, a [type coercion](glossary.md#type-coercion), so `Car(1500)` needs
no `.0`. `Number` keeps either:

```cesia
Car(1500).Mass -->
Half(3) -->
Twice(x Number) Number = x * 2
Twice(3) -->
Twice(1.5) -->
```

## Maybe missing

A `?` after a type also takes `missing`, the [null](glossary.md#null) of Cesia. A field of such a type, without a default, is `missing` when the value leaves it
out:

```cesia
struct Person
  Name Text
  Nickname Text?
end
Person("Ana") -->
Person("Bo", "Bobby").Nickname -->
```

### A result that may be missing

A function that can end without a value gives `missing` there, so its result type needs the `?`:

```cesia
use std/value
defn position(x, xs Array) Int?
  for k in 1..value.Len(xs)
    if xs[k] == x
      return k
    end
  end
end
position("b", ["a", "b"]) -->
position("z", ["a", "b"]) -->
```

## Data from outside

`From`, from the chapter [Structs](structs.md), checks the types too. The `Err` names the field and what it found, so a JSON
body with a wrong field is refused before your code reads it:

```cesia
Car.From({Mass: 900}) -->
Car.From({Mass: "heavy"}) -->
```

## Interfaces

An interface lists methods, without code. A value meets it when it has each of these methods: nothing declares it, as in Go. This is
[structural typing](glossary.md#structural-typing).
An interface is a type like the others:

```cesia
interface Shape
  (** Something with an area and a perimeter. *)
  Area()
  Perimeter()
end

struct Rect { Width Number, Height Number }
(r Rect) Area() = r.Width * r.Height
(r Rect) Perimeter() = 2 * (r.Width + r.Height)

Measured(s Shape) = s.Area() + s.Perimeter()
Measured(Rect(2, 3)) -->
```

### A dictionary meets it too

A dictionary whose keys hold functions meets an interface too, which suits a quick test value:

```cesia
Measured({Area: () -> 2, Perimeter: () -> 6}) -->
```

### A missing method

A value that lacks a method stops the program, and the message names the method:

```cesia fails
struct Circle { R Float }
(c Circle) Area() = 3.14 * c.R * c.R
Measured(Circle(1.0))
```

### A method for every Shape

A method written for an interface belongs to every value that meets it:

```cesia
(s Shape) Describe() = "area $(s.Area()), perimeter $(s.Perimeter())"
Rect(1, 2).Describe() -->
```

## When to write types

- On the fields of a struct that holds data you keep: they say what each field is, and `From` checks input against them.
- On the parameters of a public function: its page in the reference shows them, and a wrong call stops at the call.
- Not on every local name: Cesia doesn't need them, and a type never makes code faster.

## Next

Your code says what it expects. The next chapter, [Packages](packages.md), splits a program into folders, uses code from other projects, and
describes a project in `cesia.toml`.
