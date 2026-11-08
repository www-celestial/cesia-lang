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
order = result.Unwrap(sys.Read("order.json")) then json.Parse() then result.Unwrap()
order.customer -->
order.items[2].product -->
order.note -->
json.Parse("{\"id\": ") -->
```

A number without a dot or an exponent that fits in 63 bits becomes an integer, and any other number a float: so
`12345678901234567890` is read as a float, close to it. A key given twice keeps its last value, as most readers of JSON do.
A text may hold any escape of JSON, `\u00e9` included. JSON nested deeper than half the `nesting` limit, 300 levels by
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
result.Unwrap(sys.Read("user.json")) then json.Parse() then result.AndThen(User.From) -->
json.Parse("{\"Name\": \"Bo\", \"Age\": \"twenty\"}") then result.AndThen(User.From) -->
json.Parse("{\"name\": \"Bo\", \"age\": 20}") then result.AndThen(User.From) -->
json.Parse("{\"Name\": \"Bo\", \"name\": \"Ana\", \"Age\": 20}") then result.AndThen(User.From) -->
json.Parse("{\"Name\": \"Bo\", \"Agee\": 20}") then result.AndThen(User.From) -->
```

### Keys as JSON writes them

A key is the name of a field, or that name as JSON and SQL often write it: `name` gives `Name`, and `created_at` gives
`CreatedAt`, the rule that the chapter [SQLite](sqlite.md) uses for columns. Two keys for one field are refused, and so is a
key that names no field: each message names the key. A field with a default, as `Admin`, may be left out.

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
source = result.Unwrap(sys.Read("people.csv"))
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
io.Print(result.Unwrap(sys.Read("people.json")))
```

## Bytes as text: hexadecimal, Base64 and URLs

[std/encode] writes bytes as text that any channel carries. [encode.Hex] writes each byte as two hexadecimal digits, and
[encode.Unhex] reads them back; [encode.Base64] writes three bytes as four characters of an alphabet of 64, as RFC 4648
says, and [encode.Unbase64] reads both its alphabets, the standard one and the one of URLs, with or without the `=` of
padding. [encode.UrlEncode] writes every byte of a text that a URL can't hold as `%` and two digits, *percent-encoding*,
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

## Next

You can read and write the data of other programs. The next chapter, [HTTP](http.md), gets data from the web, and serves it.
