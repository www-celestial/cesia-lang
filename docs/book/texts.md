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

Upper and Lower change A to Z only, as the texts of protocols want: header names, hosts, tokens. To search and compare
what people write, `text.Fold` folds the case of every script, Unicode's own way: `text.Fold("ÉLODIE")` and
`text.Fold("Élodie")` both give `"élodie"`, and `text.Fold("ΣΊΣΥΦΟΣ")` gives `"σίσυφοσ"`. Its entry in the reference
says why Lower stays ASCII: two different texts may fold to one.

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

[text.Count] tells how many times a part occurs, without overlaps: once one is found, the search goes on after it, so
`"aa"` occurs twice in `"aaaa"`, not three times. It is the number of pieces [text.Split] would give, less one, without
making them:

```cesia
text.Count("\n", "one\ntwo\nthree\n") -->
text.Count("aa", "aaaa") -->
```

A part of one byte, as a line end, is counted eight bytes at a time, a trick called *SWAR*, SIMD within a register: the
eight bytes are read as one 64-bit word, and a few operations on the word find all the bytes equal to the part at once.
Counting the 2.9 million line ends of a text of 100 MB takes 35 ms, where `value.Len(text.Split("\n", s)) - 1` takes
790 ms, as it makes every line (medians of 3 runs, on the machine of [Speed](speed.md#beside-the-giants)).

### Replacing

[text.Replace] changes every occurrence of a part:

```cesia
text.Replace("cat", "dog", "cat and cat") -->
```

For patterns, such as "every number in this text", [std/regex] has regular expressions, the section
[Regular expressions](#regular-expressions) below.

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

## Regular expressions

A *regular expression*, a regex, is a small text that describes a set of texts: `\d+` is "one digit or more", so it
matches `42` in `"aisle 42"`. [std/regex] searches with them. [regex.Test] asks whether a pattern matches somewhere,
[regex.Find] gives the first match, with its `Text`, its `Start` and `Stop` in characters from 1, and the `Groups`, the
parts that the parentheses of the pattern caught; [regex.FindAll] gives every match, left to right, without overlap:

```cesia
use std/regex
regex.Find("(\\d+)-(\\d+)", "call 555-1234 now") -->
value.Len(regex.FindAll("\\w+", "one two, three")) --> 3
regex.Test("^b", "abc") -->
```

A pattern is a Cesia text, so its `\` is written `\\`: the pattern `\d+` is the text `"\\d+"`. [regex.Replace] changes
every match, `$1` to `$9` standing for the groups and `$$` for a dollar, and [regex.Split] cuts at each match:

```cesia
regex.Replace("(\\w+)@(\\w+)", "$2 at $1", "ana@home") -->
regex.Split("\\s*;\\s*", "a ; b;c") -->
```

### What a pattern can say

| Pattern | Matches |
|---|---|
| `a`, `é` | that character; `\.`, `\(`, `\\`... the character after the `\`, for those that mean something |
| `.` | any character but a line end; any at all with `(?s)` |
| `[abc]`, `[a-z]`, `[^0-9]` | one character of the set, of a range, or out of the set |
| `\d`, `\w`, `\s` | a digit `0-9`; a letter, digit or `_` of ASCII; a space, tab or line end. `\D`, `\W`, `\S` are the others |
| `\n`, `\t`, `\r` | a line end, a tab, a carriage return |
| `^`, `$` | the start and the end of the text; of each line with `(?m)` |
| `\b`, `\B` | a boundary between a word character and another, or no boundary |
| `x*`, `x+`, `x?` | `x` 0 times or more, once or more, 0 or 1 time, as many as possible |
| `x{3}`, `x{2,}`, `x{2,5}` | `x` 3 times, 2 or more, 2 to 5 times |
| `x*?`, `x+?`, `x??`, `x{2,5}?` | the same, as few as possible: they are *lazy* |
| `x\|y` | `x` or `y` |
| `(x)` | `x`, caught as a group; `(?:x)` groups without catching |
| `(?i)`, `(?m)`, `(?s)` | from anywhere in the pattern, for the whole of it: case ignored for A to Z, `^` and `$` at each line, `.` takes line ends |

```cesia
regex.Find("a{2,3}", "aaaa").Text -->
regex.Find("a+?", "aaa").Text -->
regex.Test("(?i)hello", "Say HELLO") -->
regex.Test("(?m)^b", "a\nb") -->
```

A pattern that is wrong, as `"(a"`, is a bug, and its message says what is wrong: `Bad pattern: a parenthesis isn't
closed.` A count is at most 1,000, groups at most 1,000, and a pattern at most 100 levels deep.

### Why no pattern can hang a program

Many regex engines try the ways a pattern can match one after the other, *backtracking*, and a pattern such as `(a+)+$`
on a long line of `a`s then takes a time that doubles with each letter: a server that runs a pattern on what a user sends
can be stalled by one request. [std/regex] is a *Pike machine*: it runs every way the pattern can go at once, step by step
along the text, as Ken Thompson's method of 1968 does, and keeps each state once. Its time is at most the size of the
pattern times the length of the text, *linear* in the text, whatever the pattern. The price: no *backreference*, `\1`
inside a pattern for "the same text as group 1 again", which no linear engine can have, and no *lookahead* or
*lookbehind*, `(?=...)` and `(?<=...)`. Each byte searched counts steps, so `--limit steps` bounds a search too.

## Bytes

Underneath, a text is a sequence of bytes in [UTF-8](glossary.md#utf-8), where `é` takes two. Most programs never see them: [value.Len], [text.Slice] and
[text.Find] count characters. For a file format or a network protocol, [text.ByteLength], [text.ByteSlice] and [text.Bytes] work byte by byte:

```cesia
value.Len("é") -->
text.ByteLength("é") -->
text.Bytes("é") -->
```

[text.Byte] gives one byte, by its position from 1, [text.ByteFind] the byte position of a part, from a byte on, and
[text.FromBytes] the text of a list of bytes. [text.Code] gives the code point of a character, its number in Unicode, and
[text.Char] the character of a code point:

```cesia
text.Byte(1, "é") -->
text.ByteFind("b", 1, "abc") -->
text.FromBytes([195, 169]) -->
text.Code("é") -->
text.Char(233) -->
```

A program reads a text in bytes when a format counts them, as HTTP's `content-length` does: a byte position is found at
once, where a character position must walk the text from its start, as UTF-8 gives each character one to four bytes.

### Searching bytes, with case or without

`fold = true` makes [text.ByteFind] match the ASCII letters in either case, in the part and in the text, as the search
of an editor that ignores case; other bytes, as the two of `é`, match only themselves:

```cesia
text.ByteFind("world", 1, "Hello World", fold = true) -->
text.ByteFind("é", 1, "É and é", fold = true) -->
```

The search first looks for the *rarest* byte of the part, by a table of how common each byte is in English text and in
code (`z` before `e`, a capital or a digit before any small letter), eight bytes at a time as [text.Count] does
([SWAR](glossary.md#swar)), and compares the part whole at each place where that byte is. With `fold`, when that byte is
a letter, the eight bytes are first or'ed with 32, `0x20`: a capital and its small letter differ by that one bit only,
so both become the small one, and no other byte becomes it. A part of 32 bytes or more is searched by the method of
Knuth, Morris and Pratt, whose time is linear in the text whatever the part. A word at the end of a text of 100 MB is
found in 39 ms, 41 ms with `fold`, against 317 ms for a lower-case copy of the text then a search;
[Speed](speed.md#texts-and-files) puts these beside Python, Node and Go.

A search counts against `--limit steps` the bytes it read, from where it started to the end of what it found: finding
the next line end of a large text, line after line, costs each line once, not the whole text each time.

### Valid UTF-8

A text written in a program is always valid UTF-8, but one read from a file or the network holds whatever bytes it was
sent, and [text.FromBytes] makes any. [text.IsUtf8] tells whether a text is valid UTF-8 as
[RFC 3629](references.md#texts-and-formats) defines it. A character takes one to four bytes; the first says how many follow,
and each that follows starts with the bits `10`. A text is invalid if it holds a byte that can't begin or continue a
character, a character cut short, a character written with more bytes than it needs (an *overlong form*, such as `0xC0
0x80` for the character 0, which programs that check texts byte by byte can be tricked by), one of the *surrogates*
U+D800 to U+DFFF, which UTF-16 keeps for itself, or a number past U+10FFFF, the last of Unicode:

```cesia
text.IsUtf8("héllo") -->
text.IsUtf8(text.FromBytes([0xC3, 0xA9])) -->
text.IsUtf8(text.FromBytes([0xC0, 0x80])) -->
text.IsUtf8(text.FromBytes([0xED, 0xA0, 0x80])) -->
text.IsUtf8(text.FromBytes([0xE9, 0x74, 0xE9])) -->
```

The last is `été` in Latin-1, an older encoding of one byte a character, as old files hold. The check reads eight bytes of
ASCII at a time, by one test of their high bits, and decodes a character only where a byte isn't ASCII: 26 ms for a text
of 100 MB of ASCII, 46 ms when one character in 33 has an accent, against 116 ms for OCaml's own `String.is_valid_utf_8`,
which decodes every byte (medians of 3 runs, same machine).

## Further reading

- F. Yergeau, *UTF-8, a transformation format of ISO 10646*, RFC 3629, 2003: what valid UTF-8 is. Randall J. Fisher and
  Henry G. Dietz, *Compiling for SIMD Within a Register*, 1999, and Henry S. Warren, *Hacker's Delight*, 2013, section
  6–1: the work on eight bytes at once of [text.Count], [text.IsUtf8] and [text.ByteFind]. Donald E. Knuth, James H.
  Morris and Vaughan R. Pratt, *Fast Pattern Matching in Strings*, 1977: the search of a long part.
- Ken Thompson, *Regular expression search algorithm*, 1968, and Russ Cox, *Regular Expression Matching Can Be Simple
  And Fast*, 2007, and *the Virtual Machine Approach*, 2009: the method of [std/regex]. See [References](references.md#texts-and-formats).

## Next

You can cut and build texts. The next chapter, [Lists and arrays](lists.md), works with many values at once.
