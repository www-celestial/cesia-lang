# JSON and CSV

In this chapter you read data that other programs wrote, and write data for them. JSON comes from web services and
configuration files, CSV from spreadsheets. You also check what comes in, so that a wrong field stops at the door instead of
deep in your code. The examples read `order.json`, `user.json` and `people.csv`.

## Reading JSON

[json.Parse] reads JSON text. An object becomes a dictionary, an array a list, and `null` becomes `missing`. It gives an `Ok`,
or an `Err` that says where the text goes wrong:

```cesia allow=read
use std/sys
use std/json
order = Unwrap(sys.Read("order.json")) then json.Parse(it) then Unwrap(it)
order.customer -->
order.items[2].product -->
order.note -->
json.Parse("{\"id\": ") -->
```

From there, the data is plain values, and every chapter before this one applies:

```cesia allow=read
Sum([i.units * i.price for i in order.items]) -->
[i.product for i in order.items if i.units > 1] -->
```

## Writing JSON

[json.Text] writes a value as JSON on one line, and [json.Pretty] on several lines, indented. A dictionary keeps its keys
as they are, `missing` becomes `null`, and a struct writes its public fields:

```cesia
Print(json.Text({Name: "Ana", Tags: ["admin"], Phone: missing}))
Print(json.Pretty({Name: "Ana", Tags: ["admin", "ops"]}))
```

A small field of a struct is private, and never written. A password hash kept in a small field can't leak into a reply:

```cesia
struct Account { Name, hash }
Print(json.Text(Account("ana", "8f2c...")))
```

## Checking what comes in

Data from outside can hold anything: a missing field, a number written as a text, a key with a typo. `From`, which every
struct has, turns a dictionary into a struct, and checks it against the fields and their types. With [AndThen], reading and
checking are one chain:

```cesia allow=read
struct User
  Name Text
  Age Int
  Admin Bool = false
end
Unwrap(sys.Read("user.json")) then json.Parse(it) then AndThen(User.From) -->
json.Parse("{\"Name\": \"Bo\", \"Age\": \"twenty\"}") then AndThen(User.From) -->
json.Parse("{\"name\": \"Bo\", \"age\": 20}") then AndThen(User.From) -->
json.Parse("{\"Name\": \"Bo\", \"name\": \"Ana\", \"Age\": 20}") then AndThen(User.From) -->
json.Parse("{\"Name\": \"Bo\", \"Agee\": 20}") then AndThen(User.From) -->
```

A key is the name of a field, or that name as JSON and SQL often write it: `name` gives `Name`, and `created_at` gives
`CreatedAt`, the rule that the chapter [SQLite](sqlite.md) uses for columns. Two keys for one field are refused, and so is a
key that names no field: each message names the key. A field with a default, as `Admin`, may be left out.

## Reading CSV

[std/csv] reads CSV as spreadsheets write it: a field with a comma or a line end sits between quotes. [csv.Parse] gives each
row as a list of texts, and [csv.Records] each row after the first as a dictionary, by the names of the first:

```cesia allow=read
use std/csv
text = Unwrap(sys.Read("people.csv"))
csv.Parse(text) -->
people = csv.Records(text)
people[1].city -->
```

Every field of a CSV is a text, since the format says nothing more. [Number] turns one into a number, and an empty field is
the empty text:

```cesia allow=read
[Number(p.age) for p in people] -->
[p.name for p in people if p.city == ""] -->
```

For a table to compute on, [frame.FromCsv] of the chapter [Data](data.md) reads the numbers as numbers, and the empty fields as
`missing`.

## Writing CSV

[csv.Write] writes rows of values, and puts quotes where they are needed:

```cesia
Print(csv.Write([["name", "note"], ["Ana", "says \"hi\""], ["Bo", "a,b"]]))
```

## A small converter

The pieces fit in a few lines. This reads the CSV of people, checks each row, and writes the result as JSON, ready for another
program:

```cesia allow=read,write
struct Person
  Name Text
  City Text?
  Age Int
end

defn person(row)
  age = Number(row.age)
  if not IsInt(age)
    return Err("$(row.name): the age must be a whole number")
  end
  city = if row.city == "" missing else row.city end
  Person.From({Name: row.name, City: city, Age: age})
end

checked = Collect(Map(person, people))
match checked
  Ok(list) -> sys.Write("people.json", json.Text(list))
  Err(e) -> Print("refused:", e)
end
Print(Unwrap(sys.Read("people.json")))
```

## Next

You can read and write the data of other programs. The next chapter, [HTTP](http.md), gets data from the web, and serves it.
