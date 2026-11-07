# JSON and CSV

In this chapter you read data that other programs wrote, and write data for them. JSON comes from web services and
configuration files, CSV from spreadsheets. You also check what comes in, so that a wrong field stops at the door instead of
deep in your code. The examples read three files: `order.json`, `user.json` and `people.csv`.

## Reading JSON

[json.Parse] reads JSON text. An object becomes a dictionary, an array a list, and `null` becomes `missing`, Cesia's
[null](glossary.md#null). It gives an `Ok`, or an `Err` that says where the text goes wrong. Here is `order.json`:

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

## Next

You can read and write the data of other programs. The next chapter, [HTTP](http.md), gets data from the web, and serves it.
