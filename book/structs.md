# Structs

In this chapter you declare the shape of your data once: a point with `X` and `Y`, a user with a name and an age. A struct
names its fields, gives some of them defaults, and catches a field written wrong. Then you give it methods.

## Declaring a struct

[struct] names a shape and its fields. A field can have a default, used when the value leaves it out:

```cesia
struct Point { X, Y = 0 }
Point(1, 2) -->
Point(5) -->
Point(Y = 4, X = 3) -->
```

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

A field that the struct doesn't have is an error, and so is a call with too many values. A dictionary would take any key
quietly; a struct says what is wrong.

```cesia fails
p.Z
```

```cesia fails
Point(1, 2, 3)
```

## Methods

A method is a function attached to a struct. An instance method writes its value apart, before its name, as in Go. A
static method has the name of the struct before its own, and makes values. A dot calls both:

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

A method gives a new value: `Scaled` leaves `r` as it was. A static method is a function like any other, so it can be passed
along. An instance method is called on a value; to pass one to [Map], write the call with `it`:

```cesia
Map(Rect.Square, [1, 2]) -->
Map(it.Area(), [Rect(1, 2), Rect(3, 4)]) -->
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

[Fields] goes the other way, from a struct to a dictionary:

```cesia
Fields(User("Ana", 31)) -->
```

The chapter [Errors](errors.md) shows how to use the `Ok` and the `Err` that `From` gives.

## Struct or dictionary

| | Struct | Dictionary |
|---|---|---|
| Keys | declared once | any, at any time |
| A wrong name | an error at once | `missing`, or an error with a dot |
| Methods | yes | no |
| For | data you design | data that comes from outside |

Both are as fast: a dictionary whose keys are written in the code is stored as a struct is.

## Next

Your data has a shape. The next chapter, [Errors](errors.md), handles what goes wrong: a file that isn't there, a number that
doesn't parse, a user that `From` refuses.
