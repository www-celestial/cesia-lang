# Modules for tools

Five modules of `std/` are for the tools around programs rather than for programs: Cesia's own tools, `cesia pkg`,
`cesia fmt`, `cesia lsp`, the site of the docs, the debugger and the prompt, are written in Cesia with them, and so can
yours. Each name has its page in the reference, with its examples; this page says what each module is for.

## std/cesia: Cesia about itself

[std/cesia] tells a tool what Cesia knows: [cesia.Version] its version, [cesia.IsDev] whether it was built from its
sources, [cesia.Binary] the path of the running binary, [cesia.Libraries] the libraries of `std/` it holds, and
[cesia.Keywords] the reserved words, for a highlighter. [cesia.IsVersion] and [cesia.Compare] read and order versions as
tags, `v1.2.0` before `v1.10.0`; [cesia.Fingerprint] gives the BLAKE2b-256 of a text, as `cesia.lock` keeps them.

```cesia
use std/cesia
cesia.Compare("v1.2.0", "v1.10.0") < 0 -->
cesia.IsVersion("v2.0") -->
cesia.Fingerprint("abc") -->
```

The others read code without running it. [cesia.Check] gives what `cesia check` finds in files; [cesia.Uses] the uses of a
source, [cesia.Definitions] what it defines at its top, [cesia.Reads] the names it reads and doesn't define, with the
compiler's own resolver, which [std/cells] links the cells of a notebook with; [cesia.SameTree] tells whether two sources read as the same program
whatever their spaces and comments, which `cesia fmt` asks before it writes a file; [cesia.Toml] reads a `cesia.toml` or a
`cesia.lock` as tables. [cesia.Doc], [cesia.DocNames] and [cesia.DocEntry] give the documentation as `cesia doc` and the
site read it, and [cesia.Asset] the files of the site's look held in the binary.

```cesia
cesia.Uses("use std/io\nuse src/shop\nio.Print(1)") -->
cesia.SameTree("x = 1  (* one *)", "x = 1") -->
[r.Name for r in cesia.Reads("use std/io\nio.Print(price * n)").Value] -->
```

## std/syntax: the colors of code

[std/syntax] reads one line of Cesia at a time and gives its words, each with its role: [syntax.Keyword], [syntax.Name]
of a call, [syntax.Field] after a dot, [syntax.Number], [syntax.Text], [syntax.Comment] or [syntax.Plain]. A line is read
in one pass, by *states*: a text or a comment that doesn't end on its line carries its state to the next one, which is
all a line needs from the lines before it. [syntax.Tokens] reads a line from a state, [syntax.FirstState] is the state at
the start of a file. Nothing in it panics, whatever the line.

```cesia
use std/syntax
syntax.Tokens("n = 2 (* two", syntax.FirstState).Tokens -->
```

For an editor that colors a long file and changes one line of it, [syntax.BlankColors], [syntax.ColoredTo] and
[syntax.ForgetFrom] keep the colors of the lines already read, and read again only from the line changed. The site of the
docs colors its code with it.

## std/columns: work on whole columns

[std/columns] is the OCaml under [std/frame] and [std/sql]: work on whole columns, which runs on several cores for a large
one. [columns.ReadCsv] reads CSV with a header into named columns, numbers as numbers, and [columns.Csv] into rows of
texts; [columns.Groups] numbers the groups of rows that share their keys, and [columns.Split] gives the values of each
group; [columns.Join] matches two key columns, the hash join of [frame.JoinOn]; [columns.Pick], [columns.Positions] and
[columns.Present] take values by position, by mask, or without the missing ones; [columns.Rows] makes rows as maps that
share their keys, so a row costs its values only; [columns.Kind] tells how a column is stored, `"int"`, `"float"` or
`"value"`; and [columns.Cores] how many cores heavy work may use.

```cesia
use std/columns
columns.Kind([1, 2, 3]) -->
columns.Kind([1, "a"]) -->
columns.Positions([true, false, true]) -->
columns.Groups([["a", "b", "a"]]) -->
```

## std/sqlite3: SQLite's natives

[std/sqlite3] is the OCaml side of [std/sql]: [sqlite3.Pool] opens a pool of connections, [sqlite3.Take] and
[sqlite3.Give] take one and put it back, [sqlite3.Run] prepares a statement, from a cache of 128 by its text, and binds its
values, [sqlite3.Next] gives the next rows by batches, [sqlite3.Query], [sqlite3.One] and [sqlite3.Exec] run one
statement, [sqlite3.Script] several, [sqlite3.Close] closes a cursor, a connection or a pool, and [sqlite3.Version] tells
the version of SQLite. A program uses [std/sql], which checks what these leave to it; a tool that needs the cursors
themselves uses these.

## std/debug: the engine of a debugger

[std/debug] gives a debugger given to `cesia run --debugger` its breakpoints, [debug.SetBreak], [debug.ClearBreak] and
[debug.Breaks]; its watches, [debug.Watch], [debug.Unwatch] and [debug.Watches]; [debug.Eval], which runs code in a frame of
the stopped program; [debug.Reload]; and [debug.ReadLine] and [debug.IsComplete] for its prompt. They need the `debug`
permission. [The prompt and the debugger](debug.md#your-own-debugger) writes a debugger with them.

## Next

The [Commands](commands.md) list what each of these tools does from the command line.
