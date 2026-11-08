# Structs

In this chapter you declare the shape of your data once: a point with `X` and `Y`, a user with a name and an age. A struct
names its fields, gives some of them defaults, and catches a field written wrong. Then you give it methods.

## Declaring a struct

[struct] names a shape and its fields, what other languages call a [record](glossary.md#struct). A field can have a
default, used when the value leaves it out:

```cesia
struct Point { X, Y = 0 }
Point(1, 2) -->
Point(5) -->
Point(Y = 4, X = 3) -->
```

### The block form

For more fields, or a comment on each, the block form has one field per line, up to `end`. Both forms make the same values:

```cesia
struct User
  (** Someone who signed up. *)
  Name
  Age = 0   (** in years *)
end
User("Ana", 31) -->
```

## Fields

A dot reads a field. Setting one changes this name's value only, as for every value of Cesia:

```cesia
p = Point(1, 2)
p.X -->
q = p
q.X = 10
p -->
q -->
```

### A wrong field

A field that the struct doesn't have is an error, and so is a call with too many values. A dictionary would take any key
quietly; a struct says what is wrong.

```cesia fails
p.Z
```

```cesia fails
Point(1, 2, 3)
```

## Methods

A method is a function attached to a struct. An instance method names its receiver, the value it is called on, in
parentheses before the name: `(r Rect) Area()`, as in Go ([method and receiver](glossary.md#method-and-receiver)). A static
method has the name of the struct before its own, `Rect.Square`, and makes values. A dot calls both:

```cesia
struct Rect { Width, Height }

defn Rect.Square(side)
  Rect(side, side)
end

defn (r Rect) Area()
  r.Width * r.Height
end

(r Rect) Scaled(k) = Rect(r.Width * k, r.Height * k)

r = Rect.Square(3)
r.Area() -->
r.Scaled(2).Area() -->
```

### The short form

A method of one line has the short form of a function: `(r Rect) Scaled(k) = Rect(r.Width * k, r.Height * k)` is
`defn (r Rect) Scaled(k) Rect(r.Width * k, r.Height * k) end`. A method gives a new value: `Scaled` leaves `r` as it was.

```cesia
r.Scaled(2) --> Rect(6, 6)
r -->
```

### Methods as values

A static method is a function like any other, so it can be passed
along. An instance method is called on a value; to pass one to [list.Map], write the call with `it`:

```cesia
use std/list
list.Map(Rect.Square, [1, 2]) -->
list.Map(it.Area(), [Rect(1, 2), Rect(3, 4)]) -->
```

A method whose name starts with a small letter is private to its package, as any name.

## Structs in patterns

A struct is a pattern of [match]: `Point(x, y)` takes a point apart, in the order of its fields. A dictionary doesn't fit a
struct's pattern, even with the same keys:

```cesia
describe(v) = match v
  Point(x, y) -> "a point at $x, $y"
  else -> "not a point"
end
describe(Point(3, 4)) -->
describe({X: 3, Y: 4}) -->
```

## From a dictionary and back

Data from outside, such as JSON, arrives as dictionaries. Every struct has `From`, which builds one from a dictionary and checks
it: an `Ok` of the value, or an `Err` that names the key too many or the field missing.

```cesia
User.From({Name: "Bo", Age: 20}) -->
User.From({Name: "Bo", Agee: 20}) -->
User.From({Age: 3}) -->
```

### Back to a dictionary

[dict.Fields] goes the other way, from a struct to a dictionary:

```cesia
use std/dict
dict.Fields(User("Ana", 31)) -->
```

The chapter [Errors](errors.md) shows how to use the `Ok` and the `Err` that `From` gives.

## Struct or dictionary

| | Struct | Dictionary |
|---|---|---|
| Keys | declared once | any, at any time |
| A wrong name | an error at once | an error; [dict.Get] gives `missing` |
| Methods | yes | no |
| For | data you design | data that comes from outside |

Both are read the same way. A struct holds its *shape*, the list of its field names shared by every struct of its kind,
and an array of its values; a dictionary of up to 32 keys written in the code holds an array of keys shared by every
dictionary made at that place. A field read keeps, at its line, the last shape it met and the place of the field in it,
so in a loop it costs one comparison and one load: see [How Cesia works](internals.md#caches-at-each-site). A struct is
also checked: its fields are known, so a typo is an error, and a type written on a field is checked at each write.

A struct is a *nominal* type: a value is a `Point` because `Point` made it, not because it has an `X` and a `Y`. So a
dictionary with the same keys doesn't fit the pattern `Point(x, y)`. Interfaces, in [Types](types.md#interfaces), are
the other way round: *structural*, met by whatever has their methods.

## Next

Your data has a shape. The next chapter, [Errors](errors.md), handles what goes wrong: a file that isn't there, a number that
doesn't parse, a user that `From` refuses.
