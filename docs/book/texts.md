# Texts

In this chapter you take texts apart, search them, and build new ones: the daily work of a script that reads files and writes
reports.

A text is a value like a number, [immutable](glossary.md#immutability): no function changes it, each one gives a new
text. In every function of this chapter, the
text you work on comes last. The part that says what to do comes first.

## Length and case

[value.Len] counts the characters of a text, accents included. [text.Upper] and [text.Lower] change the case, and [text.Trim] takes away the spaces
and line ends at both ends:

```cesia
use std/text
use std/value
value.Len("café") -->
text.Upper("hello") -->
text.Lower("SHOUT") -->
text.Trim("   padded   ") -->
```

## Cutting

[text.Split] cuts a text at each separator, and gives a list of the pieces. Two separators in a row leave an empty piece between
them:

```cesia
text.Split(",", "red,green,blue") -->
text.Split(",", "a,,b") -->
```

### Lines

[text.Lines] gives the lines of a text, without their line ends. A last line end opens no empty line, and a Windows line end counts
as one:

```cesia
text.Lines("first\nsecond\n") -->
text.Lines("one\r\ntwo") -->
```

### Characters

[text.Slice] takes the characters from one position to another, both included, from 1. [text.Chars] gives each character as a text:

```cesia
text.Slice(1, 4, "Cesia is small") -->
text.Chars("abc") -->
```

## Joining

[text.Join] puts a separator between the texts of a list. [text.Repeat] writes a text several times. And [text.Str] joins any values, which is
handy for numbers:

```cesia
text.Join(", ", ["red", "green", "blue"]) -->
text.Repeat(3, "ab") -->
text.Str("page ", 3, " of ", 10) -->
```

### With $

Most of the time, a text with `$` reads best:

```cesia
done = 3
total = 10
"page $done of $total" -->
```

### Padding

[text.PadLeft] and [text.PadRight] fill a text up to a width, for columns that line up:

```cesia
text.PadLeft(5, "0", "42") -->
text.PadRight(8, ".", "name") -->
```

## Searching

[text.Contains], [text.StartsWith] and [text.EndsWith] answer yes or no. [text.Find] gives the position of a part, from 1, or `missing` when it
isn't there:

```cesia
text.Contains("ell", "hello") -->
text.StartsWith("http", "https://example.com") -->
text.EndsWith(".csv", "data.csv") -->
text.Find("lo", "hello") -->
text.Find("z", "hello") -->
```

### Replacing

[text.Replace] changes every occurrence of a part:

```cesia
text.Replace("cat", "dog", "cat and cat") -->
```

For patterns, such as "every number in this text", the module [regex] has regular expressions.

## Numbers and texts

[text.Number] reads a number from a text: an integer or a float. It gives `missing` for a text that isn't a number, so the program
decides what to do instead of stopping:

```cesia
text.Number("42") -->
text.Number("3.5") -->
text.Number("12 apples") -->
```

### The text of a value

[value.Text] goes the other way: the text of any value, as [io.Print] shows it.

```cesia
value.Text(42) -->
value.Text([1, 2]) -->
```

### Decimals

[text.Decimals] writes a number with so many digits after the point, rounded to the nearest, for a price or a measure. A
half goes away from zero, as [math.Round] does:

```cesia
text.Decimals(2, 3.14159) -->
text.Decimals(2, 42) -->
text.Decimals(0, 2.5) -->
"$(text.Decimals(1, 1155.25)) hours" -->
```

## A small report

Put together, these functions turn raw lines into something readable. Here, each line of a text holds a name and a score:

```cesia
use std/io
raw = "ana,12\nbo,7\ncyril,15\n"
for line in text.Lines(raw)
  parts = text.Split(",", line)
  io.Print(text.PadRight(8, " ", parts[1]), text.PadLeft(3, " ", parts[2]))
end
```

`for` runs its body once for each line; the chapter [Choices and loops](choices.md) shows it in full. `parts[1]` is the first
piece: lists start at 1.

## Bytes

Underneath, a text is a sequence of bytes in [UTF-8](glossary.md#utf-8), where `é` takes two. Most programs never see them: [value.Len], [text.Slice] and
[text.Find] count characters. For a file format or a network protocol, [text.ByteLength], [text.ByteSlice] and [text.Bytes] work byte by byte:

```cesia
value.Len("é") -->
text.ByteLength("é") -->
text.Bytes("é") -->
```

## Next

You can cut and build texts. The next chapter, [Lists and arrays](lists.md), works with many values at once.
