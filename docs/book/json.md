# JSON and CSV

In this chapter you read data that other programs wrote, and write data for them. JSON comes from web services and
configuration files, CSV from spreadsheets. You also check what comes in, so that a wrong field stops at the door instead of
deep in your code. The examples read three files: `order.json`, `user.json` and `people.csv`.

## Reading JSON

[json.Parse] reads JSON text, as RFC 8259 defines it. An object becomes a dictionary, an array a list, and `null` becomes
`missing`, Cesia's [null](glossary.md#null). It gives an `Ok`, or an `Err` that says where the text goes wrong. Here is
`order.json`:

```text
{
  "id": 17,
  "customer": "Ana",
  "items": [
    {"product": "bread", "units": 2, "price": 1.25},
    {"product": "cake", "units": 1, "price": 8.0}
  ],
  "note": null
}
```

```cesia allow=read
use std/sys
use std/json
use std/result
order = sys.Read("order.json")! then json.Parse()!
order.customer -->
order.items[2].product -->
order.note -->
json.Parse("{\"id\": ") -->
```

A number without a dot or an exponent that fits in 63 bits becomes an integer, and any other number with them a float. An
integer past 63 bits, as `12345678901234567890`, an ID or a hash, is kept as the text of its digits, exact: a float would
lose some, and no number of Cesia holds it. A key given twice keeps its last value, as most readers of JSON do. A text may
hold any escape of JSON, `\u00e9` included; JSON is UTF-8, as RFC 8259 asks, and bytes that aren't are an `Err`, as a
text of such bytes is an error of `json.Text`. JSON nested deeper than half the `nesting` limit, 300 levels by
default, is an `Err`, `Too deep`, so a hostile input of ten thousand `[` can't overflow the reader.

```cesia
json.Parse("12345678901234567890") -->
json.Parse("{\"a\": 1, \"a\": 2}") -->
json.Parse("\"caf\\u00e9\"") -->
```

From there, the data is plain values, and every chapter before this one applies:

```cesia allow=read
use std/list
list.Sum([i.units * i.price for i in order.items]) -->
[i.product for i in order.items if i.units > 1] -->
```

## Writing JSON

[json.Text] writes a value as JSON on one line, and [json.Pretty] on several lines, indented. A dictionary keeps its keys
as they are, `missing` becomes `null`, and a struct writes its public fields:

```cesia
use std/io
io.Print(json.Text({Name: "Ana", Tags: ["admin"], Phone: missing}))
io.Print(json.Pretty({Name: "Ana", Tags: ["admin", "ops"]}))
```

### Private fields stay out

A small field of a struct is private, and never written. A password hash kept in a small field can't leak into a reply:

```cesia
struct Account { Name, hash }
io.Print(json.Text(Account("ana", "8f2c...")))
```

## Checking what comes in

Data from outside can hold anything: a missing field, a number written as a text, a key with a typo. `From`, which every
struct has, turns a dictionary into a struct, and checks it against the fields and their types. With [result.AndThen], reading and
checking are one chain. `user.json` holds one line:

```text
{"Name": "Bo", "Age": 20, "Admin": true}
```

```cesia allow=read
struct User
  Name Text
  Age Int
  Admin Bool = false
end
sys.Read("user.json")! then json.Parse() then result.AndThen(User.From) -->
json.Parse("{\"Name\": \"Bo\", \"Age\": \"twenty\"}") then result.AndThen(User.From) -->
json.Parse("{\"name\": \"Bo\", \"age\": 20}") then result.AndThen(User.From) -->
json.Parse("{\"Name\": \"Bo\", \"name\": \"Ana\", \"Age\": 20}") then result.AndThen(User.From) -->
json.Parse("{\"Name\": \"Bo\", \"Agee\": 20}") then result.AndThen(User.From) -->
```

### Keys as JSON writes them

A key is the name of a field, or that name as JSON and SQL often write it: `name` gives `Name`, and `created_at` gives
`CreatedAt`, the rule that the chapter [SQLite](sqlite.md) uses for columns. Two keys for one field are refused, and so is a
key that names no field: each message names the key. A field with a default, as `Admin`, may be left out.

### Shapes: bounds and messages for each field

`From` checks types. What a visitor sends needs bounds too: a name of at most 120 bytes, a quantity from 1 to 1,000,000,
an e-mail address, a list of at most 50 lines. [std/check] says it with a *shape*, a map that describes a value, and
[check.Read] gives an `Ok` of the value made clean, or an `Err` of a map from each wrong field, by its path, to a message
that a form can show beside it:

```cesia
use std/check
Line = check.Record({Label: check.Text(1, 200), Qty: check.Int(1, 1000000), Price: check.Money(2)})
Order = check.Record({Email: check.Email(), Due: check.Date(), Lines: check.List(Line, 1, 50)})
check.Read(Order, {Email: " Bo@Example.com", Due: "2026-12-01", Lines: [{Label: "Bread", Qty: 4, Price: 1.25}]}) --> result.Ok({Email: "bo@example.com", Due: 1796083200, Lines: [{Label: "Bread", Qty: 4, Price: 1.25}]})
check.Read(Order, {Email: "bo", Due: "2026-12-01", Lines: [{Label: "", Qty: 0, Price: 1}]}) then result.IsErr() --> true
```

- Every text is valid UTF-8 without control characters, trimmed, bounded in bytes; every number has its range (an `Int`
  from -(2^30 - 1) to 2^30 - 1 unless it says otherwise, which a page in WebAssembly holds too); every list its most items.
- A day is a `check.Date()`, `"2026-12-01"`, and an instant a `check.Time()`, `"2026-12-01T08:30:00Z"` or with an offset:
  both are read as seconds since 1970, as Cepheus keeps them, and written back as text by `check.Out`.
- A field the shape doesn't declare is dropped by `Read`: a sender who adds `Admin: true` adds nothing. An optional field
  that he leaves out is there, as its default or `missing`, so that `x.Note` never fails.
- `check.Read(shape, query, texts = true)` reads values written as texts, as a query string or the environment gives
  them: `"42"` for an `Int`, `""` for an absent field.
- [check.Out] gives a value back to the outside by its shape: the declared fields only, dates as text, never a
  `check.Secret()`; [check.Masked] writes each secret `(secret)`, for a log; [check.Schema] gives the JSON Schema of a
  shape, as OpenAPI describes a body.
- It is pure Cesia: the page checks a form as one types with the same shape that the server checks again.

## Reading CSV

[std/csv] reads CSV as spreadsheets write it: a field with a comma or a line end sits between quotes. [csv.Parse] gives each
row as a list of texts, and [csv.Records] each row after the first as a dictionary, by the names of the first. Here is `people.csv`:

```text
name,city,age
Ana,"Lyon, France",31
Bo,Paris,20
Cyril,,45
```

```cesia allow=read
use std/csv
source = sys.Read("people.csv")!
csv.Parse(source) -->
people = csv.Records(source)
people[1].city -->
```

### Every field is a text

Every field of a CSV is a text, since the format says nothing more. [text.Number] turns one into a number, and an empty field is
the empty text:

```cesia allow=read
use std/text
[text.Number(p.age) for p in people] -->
[p.name for p in people if p.city == ""] -->
```

For a table to compute on, [frame.FromCsv] of the chapter [Data](data.md) reads the numbers as numbers, and the empty fields as
`missing`.

## Writing CSV

[csv.Text] writes rows of values, and puts quotes where they are needed:

```cesia
io.Print(csv.Text([["name", "note"], ["Ana", "says \"hi\""], ["Bo", "a,b"]]))
```

A list of lists is written in one pass, natively. Measured on 2026-11-13, 100,000 rows of 7 cells, the median of 5
runs of the best of 5 (`bench/csv.ce`, `bench/csv.py`): Cesia 0.81 µs a row, 3.89 µs before; Python 3.14's
`csv.writer` 1.12 µs. For dates, Python wins: [date.FormatDate] takes 0.61 µs, `date.isoformat` 0.34 µs.

## A small converter

The pieces fit in a few lines. This reads the CSV of people, checks each row, and writes the result as JSON, ready for another
program:

```cesia allow=read,write
use std/value
struct Person
  Name Text
  City Text?
  Age Int
end

defn person(row)
  age = text.Number(row.age)
  if not value.IsInt(age)
    return result.Err("$(row.name): the age must be a whole number")
  end
  city = if row.city == "" missing else row.city end
  Person.From({Name: row.name, City: city, Age: age})
end

checked = result.Collect(list.Map(person, people))
match checked
  result.Ok(all) -> sys.Write("people.json", json.Text(all))
  result.Err(e) -> io.Print("refused:", e)
end
io.Print(sys.Read("people.json")!)
```

## Bytes as text: hexadecimal, Base64 and URLs

[std/encode] writes bytes as text that any channel carries. [encode.Hex] writes each byte as two hexadecimal digits, and
[encode.Unhex] reads them back; [encode.Base64] writes three bytes as four characters of an alphabet of 64, as RFC 4648
says, and [encode.Unbase64] reads both its alphabets, the standard one and the one of URLs, with or without the `=` of
padding, one or two at the end of a text of a multiple of four. [encode.UrlEncode] writes every byte of a text that a URL can't hold as `%` and two digits, *percent-encoding*,
and [encode.UrlDecode] reads it back, a `+` as a space as forms write it; [encode.ParseQuery] reads the fields of a query
or a form. [encode.Sha1] is the SHA-1 hash that the WebSocket handshake asks for, and nothing else: SHA-1 is broken for
signatures, and [std/crypto] has the hashes for security.

```cesia
use std/encode
encode.Hex("hi") -->
encode.Unhex("6869") -->
encode.Base64("hi") -->
encode.Unbase64("aGk") -->
encode.UrlEncode("a b&c") -->
encode.UrlDecode("a+b%26c") -->
encode.ParseQuery("product=bread&units=2") -->
```

## Markdown

[std/markdown] turns Markdown, the text format of READMEs, into HTML: the part of CommonMark that GitHub shows the same way,
and its tables. [markdown.Parse] gives the blocks, each a dictionary with its `Kind` and its `Line`; [markdown.Html] writes
them, and asks its hooks for the colors of code, the target of a name in brackets and the anchor of a heading;
[markdown.Plain] are hooks that add nothing. Everything a page shows is escaped, raw HTML included, and a link leads only
to `http`, `https`, `mailto` or a page of the site: a text from anyone is safe in it. The pages of this book are made this
way.

```cesia
use std/markdown
markdown.Html(markdown.Parse("# Prices\n\nBread is *cheap*."), markdown.Plain) -->
markdown.Html(markdown.Parse("<script>alert(1)</script>"), markdown.Plain) -->
markdown.Parse("# Prices")[1].Kind -->
```

## Speed

[json.Parse] reads the scene of a surface of 100 by 100 quads, 192 KB of JSON made mostly of numbers, as a session of
[cells](cells.md) sends it to an editor: the mean of 20 parses after a first one, inside each program, the median of
101 runs alternated and the 95 % interval of that median, on the machine of [Speed](speed.md#beside-the-giants), on
2026-11-19:

| | 192 KB |
|---|---:|
| **Cesia**, [json.Parse] | **3.36 ms** (3.34 to 3.36) |
| Python 3.14.10, `json.loads` | 3.34 ms (3.34 to 3.35) |
| Node 26.13, `JSON.parse` | 1.06 ms (1.05 to 1.06) |

```cesia allow=read,write
use std/plot
parsers = plot.Bars(["Cesia", "Python", "Node"], [3.36, 3.34, 1.06])
parsing = plot.Of([parsers], title = "Parsing 192 KB of JSON: milliseconds, median of 101 runs", y = "milliseconds",
  size = [640, 300])
plot.Save(parsing, "json-parse.svg") -->
```

Cesia's parser is OCaml, in its binary: it looks at a text eight bytes at a time for the end of a string, and reads a
decimal of 15 digits or fewer, with a power of ten from $10^{-22}$ to $10^{22}$, by one product or one quotient of two
doubles that hold them exactly, which IEEE 754 rounds correctly: the *fast path* of Clinger (1990). Rows of a document
with the same keys share them. Python's `json.loads` runs the scanner of its `_json` module, written in C: the two take
the same time, within half a percent. **Where Node wins, and why:** V8's `JSON.parse` is C++ inside the engine, which
makes JavaScript's own objects and numbers as it reads, 3.2 times faster than both.

## Further reading

RFC 8259 for JSON, RFC 4180 for CSV, RFC 4648 for Base64 and hexadecimal, RFC 3986 for the escapes of URLs, and the
CommonMark specification for Markdown: see [References](references.md#texts-and-formats).

## Next

You can read and write the data of other programs. The next chapter, [HTTP](http.md), gets data from the web, and serves it.
