# Texts

In this chapter you take texts apart, search them, and build new ones: the daily work of a script that reads files and writes
reports.

A text is a value like a number, [immutable](glossary.md#immutability): no function changes it, each one gives a new
text. In every function of this chapter, the
text you work on comes last. The part that says what to do comes first.

## Length and case

[Len] counts the characters of a text, accents included. [Upper] and [Lower] change the case, and [Trim] takes away the spaces
and line ends at both ends:

```cesia
Len("café") -->
Upper("hello") -->
Lower("SHOUT") -->
Trim("   padded   ") -->
```

## Cutting

[Split] cuts a text at each separator, and gives a list of the pieces. Two separators in a row leave an empty piece between
them:

```cesia
Split(",", "red,green,blue") -->
Split(",", "a,,b") -->
```

### Lines

[Lines] gives the lines of a text, without their line ends. A last line end opens no empty line, and a Windows line end counts
as one:

```cesia
Lines("first\nsecond\n") -->
Lines("one\r\ntwo") -->
```

### Characters

[Slice] takes the characters from one position to another, both included, from 1. [Chars] gives each character as a text:

```cesia
Slice(1, 4, "Cesia is small") -->
Chars("abc") -->
```

## Joining

[Join] puts a separator between the texts of a list. [Repeat] writes a text several times. And [Str] joins any values, which is
handy for numbers:

```cesia
Join(", ", ["red", "green", "blue"]) -->
Repeat(3, "ab") -->
Str("page ", 3, " of ", 10) -->
```

### With $

Most of the time, a text with `$` reads best:

```cesia
done = 3
total = 10
"page $done of $total" -->
```

### Padding

[PadLeft] and [PadRight] fill a text up to a width, for columns that line up:

```cesia
PadLeft(5, "0", "42") -->
PadRight(8, ".", "name") -->
```

## Searching

[Contains], [StartsWith] and [EndsWith] answer yes or no. [Find] gives the position of a part, from 1, or `missing` when it
isn't there:

```cesia
Contains("ell", "hello") -->
StartsWith("http", "https://example.com") -->
EndsWith(".csv", "data.csv") -->
Find("lo", "hello") -->
Find("z", "hello") -->
```

### Replacing

[Replace] changes every occurrence of a part:

```cesia
Replace("cat", "dog", "cat and cat") -->
```

For patterns, such as "every number in this text", the module [regex] has regular expressions.

## Numbers and texts

[Number] reads a number from a text: an integer or a float. It gives `missing` for a text that isn't a number, so the program
decides what to do instead of stopping:

```cesia
Number("42") -->
Number("3.5") -->
Number("12 apples") -->
```

### The text of a value

[Text] goes the other way: the text of any value, as [Print] shows it.

```cesia
Text(42) -->
Text([1, 2]) -->
```

## A small report

Put together, these functions turn raw lines into something readable. Here, each line of a text holds a name and a score:

```cesia
raw = "ana,12\nbo,7\ncyril,15\n"
for line in Lines(raw)
  parts = Split(",", line)
  Print(PadRight(8, " ", parts[1]), PadLeft(3, " ", parts[2]))
end
```

`for` runs its body once for each line; the chapter [Choices and loops](choices.md) shows it in full. `parts[1]` is the first
piece: lists start at 1.

## Bytes

Underneath, a text is a sequence of bytes in [UTF-8](glossary.md#utf-8), where `é` takes two. Most programs never see them: [Len], [Slice] and
[Find] count characters. For a file format or a network protocol, [ByteLength], [ByteSlice] and [Bytes] work byte by byte:

```cesia
Len("é") -->
ByteLength("é") -->
Bytes("é") -->
```

## Next

You can cut and build texts. The next chapter, [Lists and arrays](lists.md), works with many values at once.
