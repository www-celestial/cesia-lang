# SQLite

In this chapter you keep data in a database: you make a table, add rows, ask for them, change them in a transaction, and read
them as structs. [std/sql] speaks SQL to SQLite, a database in one file, or in memory, with no server to run.

## Opening a database

[sql.Open] takes a URL: `sqlite:PATH` for a file, `sqlite::memory:` for a database that lives as long as the program. A file
needs the `read` and `write` permissions of its folder; a database in memory needs none:

```cesia
use std/sql
use std/result
db = result.Unwrap(sql.Open("sqlite::memory:"))
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
`Changed`, how many rows changed, and `LastId`, the id of the last row added.

```cesia
sql.Exec("insert into notes (title) values (?)", ["buy bread"], db) -->
sql.Exec("insert into notes (title) values (?)", ["call Bo"], db) -->
```

### Broken rules

A rule of the table that a row breaks is an `Err` with a code, the one SQL gives it: `23505` for a value that must be unique,
`23502` for a missing one, `23514` for a `check` that fails.

```cesia
sql.Exec("insert into notes (title) values (?)", ["buy bread"], db) -->
sql.Exec("insert into notes (title) values (?)", [missing], db) -->
```

## Values never go into the text

Write each value as a `?`, never inside the text with `$`. A value put in the text is read as SQL, so a name typed by a user can
change the query: an injection. Through `?`, a value is only ever a value, in a
[parameterized query](glossary.md#parameterized-query):

```cesia
name = "x' or '1'='1"
sql.Query("select * from notes where title = ?", [name], db) -->
```

### One statement per call

A call runs one statement, so a text that hides a second one is refused:

```cesia
sql.Exec("select 1; drop table notes", [], db) -->
```

## Asking

[sql.Query] gives every row, each a dictionary. The names of the columns become public names: `created_at` is read
`CreatedAt`. NULL is `missing`, and a column declared `boolean` is a Bool:

```cesia
rows = result.Unwrap(sql.Query("select * from notes", [], db))
rows -->
rows[1].CreatedAt -->
```

### One row

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

A [transaction](glossary.md#transaction) makes several changes as one: all of them, or none. [sql.Transaction] runs a
function with `tx`, which is used as `db` in every call. An `Ok` of the function keeps all its changes;
an `Err`, or a panic, undoes them all:

```cesia
sql.Transaction(tx -> sql.Exec("update notes set done = true where id = ?", [1], tx), db) -->
defn clearAll(tx)
  sql.Exec("delete from notes", [], tx)?
  result.Err("changed my mind")
end
sql.Transaction(clearAll, db) -->
sql.Query("select id, done from notes", [], db) -->
```

The `delete` was undone: both notes are still there.

### Inside a transaction

A [sql.Transaction] inside another, on its `tx`, is a *savepoint*: undone alone when its function gives an `Err`, while
the outer one goes on. `read = true` opens a transaction that only reads. A transaction runs in a fiber of its own, so
that a [fiber.Cancel] of the fiber that began it can't leave it open: it ends as its function says.

### What a transaction guarantees

SQLite's transactions are *ACID*: *atomic*, all their changes or none; *consistent*, every rule of the tables holds after
each one; *isolated*, as below; and *durable*, a change confirmed stays, even after a crash or a loss of power. Durable
needs the log to reach the disk at each commit: SQLite's `synchronous` setting is `FULL`, 2, on the databases Cesia opens,
which SQLite's documentation calls ACID in WAL mode, where `NORMAL` could lose the last commits to a loss of power. Cesia opens every database
file in *WAL* mode, a [write-ahead log](glossary.md#write-ahead-log): each change is first written to the file `-wal` beside
the database, then copied into it later, so that after a crash SQLite replays the log and loses nothing confirmed. With
it, readers don't wait for the writer, nor the writer for them.

The isolation is exact. Each transaction that reads sees the database as it was when its first read began, whatever the
others commit meanwhile: *snapshot isolation*. And SQLite lets one writer at a time, so the transactions that write run
one after the other: the result is always that of some order of the transactions, which is *serializable* isolation, the
strongest of the SQL standard. A transaction of [sql.Transaction] that writes takes the write lock at its start, with
`BEGIN IMMEDIATE`, so two of them never both read, then find that only one may write: the second waits at its start.

Cesia also turns on *foreign keys*, so a column declared `references` another table refuses a row that points nowhere,
and opens each file with SQLite's defensive settings: no extension loaded, nothing attached, no text or BLOB over 100 MB.

### Waiting and the fibers

A pool of connections, 8 by default, `max` of [sql.Open], serves the fibers: each call takes one, and gives it back. When
the database is busy, held by a writer of another program, a call waits in its fiber, 1 ms, then twice as long each time
up to 50 ms, for at most `wait` seconds, 5 by default, so the other fibers run meanwhile. A query that runs, though, runs
to its end inside SQLite before any other fiber gets its turn, as any function of `std/` written in OCaml or C does: a
query of seconds holds a server for seconds, and belongs in a background task, or in an index that makes it short.

## Many rows

[sql.Each] calls a function on each row, with only a batch of rows in memory at a time, whatever the size of the result. The
function gives an `Ok` to go on:

```cesia
use std/io
sql.Each(r -> result.Ok(io.Print(r.Title)), "select title from notes order by id", [], db) -->
```

### As columns

[sql.Table] gives the result as columns: the `Names` of the columns, and the `Columns` of values, the form [std/frame] works
on:

```cesia
sql.Table("select id, title from notes", [], db) -->
```

## A database in a file

A file keeps its data between runs. Here the program keeps it in the folder `data`, makes it, writes to it, and reads it
back:

```cesia allow=read,write
use std/sys

defn count(path)
  db = sql.Open("sqlite:$path")?
  sql.Script("create table if not exists visits (at text)", db)?
  sql.Exec("insert into visits values (?)", ["now"], db)?
  n = sql.One("select count(*) as total from visits", [], db)?
  sql.Close(db)
  result.Ok(n.Total)
end
sys.Mkdir("data")
count("data/visits.db") -->
count("data/visits.db") -->
```

```bash
cesia run --allow read=data,write=data visits.ce
```

SQLite writes two more files beside the database while it runs, `visits.db-wal` and `visits.db-shm`. So the permissions
are on the folder that holds them all, `data`: a permission on `data/visits.db` alone is denied, with the name of the file
it lacks. A database in use by another fiber or program is waited for, in this fiber only, so the others go on.

## Further reading

- Kevin P. Gaffney and others, *SQLite: Past, Present, and Future*, 2022: how SQLite is built.
- SQLite's pages on write-ahead logging and isolation, <https://www.sqlite.org/wal.html> and
  <https://www.sqlite.org/isolation.html>: what this chapter's guarantees rest on.
- Hal Berenson and others, *A Critique of ANSI SQL Isolation Levels*, 1995: snapshot isolation and serializability,
  defined.

Each with its link in [References](references.md#databases).

## Next

Your programs keep their data. The next chapter, [Tests](tests.md), checks that they keep doing what they should.
