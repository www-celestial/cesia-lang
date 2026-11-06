# SQLite

In this chapter you keep data in a database: you make a table, add rows, ask for them, change them in a transaction, and read
them as structs. [std/sql] speaks SQL to SQLite, a database in one file, or in memory, with no server to run.

## Opening a database

[sql.Open] takes a URL: `sqlite:PATH` for a file, `sqlite::memory:` for a database that lives as long as the program. A file
needs the `read` and `write` permissions of its folder; a database in memory needs none:

```cesia
use std/sql
db = Unwrap(sql.Open("sqlite::memory:"))
```

[sql.Script] runs several statements, for a schema:

```cesia
schema = "
  create table notes (
    id integer primary key,
    title text not null unique,
    done boolean not null default false,
    created_at text not null default '2026-11-06 10:00:00'
  )"
sql.Script(schema, db) -->
```

## Adding rows

[sql.Exec] runs one statement that changes rows. Each `?` in the text takes the next value of the list. It gives
`{Changed, LastId}`: how many rows changed, and the id of the last row added.

```cesia
sql.Exec("insert into notes (title) values (?)", ["buy bread"], db) -->
sql.Exec("insert into notes (title) values (?)", ["call Bo"], db) -->
```

A rule of the table that a row breaks is an `Err` with a code, the one SQL gives it: `23505` for a value that must be unique,
`23502` for a missing one.

```cesia
sql.Exec("insert into notes (title) values (?)", ["buy bread"], db) -->
sql.Exec("insert into notes (title) values (?)", [missing], db) -->
```

## Values never go into the text

Write each value as a `?`, never inside the text with `$`. A value put in the text is read as SQL, so a name typed by a user can
change the query: an injection. Through `?`, a value is only ever a value:

```cesia
name = "x' or '1'='1"
sql.Query("select * from notes where title = ?", [name], db) -->
```

A call runs one statement, so a text that hides a second one is refused:

```cesia
sql.Exec("select 1; drop table notes", [], db) -->
```

## Asking

[sql.Query] gives every row, each a dictionary. The names of the columns become public names: `created_at` is read
`CreatedAt`. NULL is `missing`, and a column declared `boolean` is a Bool:

```cesia
rows = Unwrap(sql.Query("select * from notes", [], db))
rows -->
rows[1].CreatedAt -->
```

[sql.One] gives the first row, or `missing` when there is none:

```cesia
sql.One("select title from notes where id = ?", [2], db) -->
sql.One("select title from notes where id = ?", [9], db) -->
```

## Rows as structs

With `as`, each row goes through a function, and `From` of a struct checks it. A row that doesn't fit is an `Err` that says
which:

```cesia
struct Note
  Id Int
  Title Text
  Done Bool
  CreatedAt Text
end
sql.Query("select * from notes where not done", [], db, as = Note.From) -->
```

## Transactions

[sql.Transaction] runs a function with `tx`, which is used as `db` in every call. An `Ok` of the function keeps all its changes;
an `Err`, or a panic, undoes them all:

```cesia
sql.Transaction(tx -> sql.Exec("update notes set done = true where id = ?", [1], tx), db) -->
defn clearAll(tx)
  sql.Exec("delete from notes", [], tx)?
  Err("changed my mind")
end
sql.Transaction(clearAll, db) -->
sql.Query("select id, done from notes", [], db) -->
```

The `delete` was undone: both notes are still there.

## Many rows

[sql.Each] calls a function on each row, with only a batch of rows in memory at a time, whatever the size of the result. The
function gives an `Ok` to go on:

```cesia
sql.Each(r -> Ok(Print(r.Title)), "select title from notes order by id", [], db) -->
```

[sql.Table] gives the result as columns, `{Names, Columns}`, the form [std/frame] works on:

```cesia
sql.Table("select id, title from notes", [], db) -->
```

## A database in a file

A file keeps its data between runs. Here the program makes it, writes to it, and reads it back:

```cesia allow=read,write
defn count(path)
  db = sql.Open("sqlite:$path")?
  sql.Script("create table if not exists visits (at text)", db)?
  sql.Exec("insert into visits values (?)", ["now"], db)?
  n = sql.One("select count(*) as total from visits", [], db)?
  sql.Close(db)
  Ok(n.Total)
end
count("visits.db") -->
count("visits.db") -->
```

```bash
cesia run --allow read=data,write=data visits.ce
```

SQLite writes two files beside the database while it runs, `-wal` and `-shm`: give the permissions on the folder, not on the
file alone. A database in use by another fiber or program is waited for, in this fiber only, so the others go on.

## Next

Your programs keep their data. The next chapter, Tests, checks that they keep doing what they should.
