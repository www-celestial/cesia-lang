# Values and names

In this chapter you meet the values a program works with: numbers, texts, true and false, and `missing`. You give them names,
change them, and see which names other files can use.

In the examples of this book, a line that ends with `-->` shows the value on its left, as Cesia prints it. A line with a value
after its `-->` checks it: the book would not build if `2 + 2` were not `4`.

```cesia
2 + 2 --> 4
"Cesia" -->
```

## Numbers

A number is an integer, such as `42`, or a float, with a dot: `1.5`. The usual operators work on both, and `^` is the power:

```cesia
2 + 3 * 4 -->
(2 + 3) * 4 -->
2 ^ 10 -->
```

Each operator is also a function, for the times you pass it to another function: `2 + 3` is [Add]`(2, 3)`.

```cesia
Add(2, 3) --> 2 + 3
Mul(4, 5) --> 4 * 5
```

`/` always gives a float, even when the division falls right. For the whole part of a division, [Div] rounds down, and [Mod]
gives what is left:

```cesia
7 / 2 -->
10 / 2 -->
Div(7, 2) -->
Mod(7, 2) -->
```

An integer and a float mix: the result is a float. And they compare by their value:

```cesia
1 + 0.5 -->
1 == 1.0 -->
```

Floats are those of your processor, so a decimal fraction is close, not exact. [Round] and [Floor] give whole numbers back:

```cesia
0.1 + 0.2 -->
Round(2.5) -->
Floor(2.7) -->
```

## Texts

A text sits between double quotes. A `$` puts a value inside it: a name after the `$`, or any expression in `$( )`.

```cesia
name = "Ana"
"Hello, $name" -->
"Two and two make $(2 + 2)" -->
```

A `$` is short for [Str], which joins the texts of its arguments:

```cesia
"Hello, $name" --> Str("Hello, ", name)
```

A text never adds to a number with `+`: write the number inside the text, or join the parts with [Str]:

```cesia
Str("Total: ", 3) -->
```

A `\` starts a character that a text can't hold as it is: `\"` is a quote, `\n` a line end, `\t` a tab, and `\\` the `\`
itself. A `$` is written twice:

```cesia
Print("She said \"yes\"")
Print("one\ttwo\nthree")
Print("It costs 5 $$")
Len("\"") -->
```

The chapter [Texts](texts.md) shows how to cut, search and join them.

## True and false

`true` and `false` come from comparisons, and combine with `and`, `or` and `not`:

```cesia
3 > 2 -->
3 != 3 -->
1 < 2 and not (2 < 1) -->
"apple" < "banana" -->
```

`and` and `or` stop as soon as the answer is known: in `false and f()`, `f` is never called.

## Missing

`missing` means that there is no value: a key that isn't in a dictionary, a text that isn't a number. [IsMissing] asks, and
[IsSome] asks the opposite:

```cesia
Number("12") -->
Number("twelve") -->
IsMissing(Number("twelve")) -->
```

`missing` goes through arithmetic: a sum that has a missing part is missing. A total over data with a hole in it shows the hole,
instead of a wrong number:

```cesia
1 + missing -->
```

## Names

`=` gives a name to a value. The same name can take another value later, of any kind. `+=`, `-=`, `*=` and `/=` change a number
with its own value:

```cesia
count = 1
count += 2
count *= 10
count -->
```

`count += 2` is short for `count = count + 2`:

```cesia
total = 10
total = total + 2
total --> 12
```

A value never changes behind your back. When two names hold the same list and you change one, the other keeps what it had:

```cesia
a = [1, 2, 3]
b = a
b[1] = 100
a -->
b -->
```

So a function that gets your list can't change it: it gives a new one back. The chapter [Lists and arrays](lists.md) comes back
to this.

## Public and private

The first letter of a name says who can see it, as in Go:

- A capital makes it public: `Print`, `LineCount`, `Area`. Other files can use it.
- A small letter makes it private to its package: `count`, `chunk`. Local names, parameters and files are small.

A name joins its words with capitals: `byteLength` or `ByteLength`, never `byte_length`. The lone `_` means "any value" in a
pattern, as the chapter [Choices and loops](choices.md) shows.

## Comments

`(*` and `*)` hold a comment, on one line or several. `(**` opens a documentation comment: it describes the name it follows or
the one under it, and `cesia doc` shows it. The reference of this site is made from such comments.

```cesia
(* A comment for the reader of the code. *)
double(x) = x * 2   (** Twice x. *)
double(21) -->
```

## Next

You know the values and how names hold them. The next chapter, [Texts](texts.md), takes texts apart and puts them back together.
