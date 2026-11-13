# Cesia

Cesia is a small language for solving real problems directly. Use it for:

- a script that cleans a CSV;
- a web server on a database;
- a program that drives other programs.

It starts at once and is safe by default, and when something goes wrong it says what to write.

```cesia
use std/io
io.Print("Hello from Cesia")
```

This book teaches Cesia from the start. Every example on these pages ran when the site was built, and the text under it is what
it printed. When the site builds, an example that gives another result stops the build, so the book can't drift from the
language.

## How to read it

- Read the chapters in order the first time: each one uses what the ones before it showed.
- Type the examples yourself, in a file or in your editor. Change them and run them again: that is the fastest way to learn.
- A name in the text leads to its page in the reference: [io.Print], for instance, or the keyword [match].
- Press `/` to search, `n` and `p` to turn the pages, and `?` to see every key.

## Contents

1. [Install and first run](install.md): Cesia on your machine, a first program, a project.
2. [Values and names](values.md): numbers, texts, true and false, missing, and how names work.
3. [Texts](texts.md): cutting, joining and searching texts.
4. [Lists and arrays](lists.md): from 1, ranges, sorting, sums and matrices.
5. [Choices and loops](choices.md): `if`, `for`, `while` and `match`.
6. [Functions](functions.md): your own functions, and those that take functions.
7. [Maps](maps.md): values under names, counting, nested dictionaries.
8. [Structs](structs.md): shapes declared once, defaults, methods, `From` and `Fields`.
9. [Errors](errors.md): `Ok` and `Err`, `?`, steps on results, and bugs.
10. [Types](types.md): types on fields, parameters and results, `?` for missing, interfaces.
11. [Packages](packages.md): `use`, folders as packages, `cesia.toml`, tasks, code from other projects.
12. [Permissions](permissions.md): `--allow`, `--limit`, and the permissions of a task.
13. [Files](files.md): reading, writing, folders and paths, arguments and flags, other programs, the clock and local time.
14. [Data](data.md): comprehensions, groups, counts and ranks, tables of columns from a CSV file, random samples.
15. [Numbers and algorithms](numbers.md): std/math, std/num and LAPACK, the classic algorithms, sets, queues and heaps,
    and what each costs.
16. [Graphs](graphs.md): lines, points, bars, histograms, heatmaps and densities as values, drawn to SVG, and the
    methods each step follows.
17. [Numerical methods](numerical.md): the zero of a function and differential equations, as `fzero` and `ode45`,
    with what each method promises, beside scipy and Octave.
18. [Statistics](statistics.md): the laws of probability as values, their densities, tails, quantiles and draws, Monte
    Carlo means with their intervals, the special functions under them, with what each method promises, beside R and
    scipy.
19. [JSON and CSV](json.md): reading, writing, and checking what comes in.
20. [HTTP](http.md): a web server with routes and JSON, tested without the network, live screens, and the client.
21. [Cryptography](crypto.md): hashes, passwords, encryption with a key or for someone, signatures, through libsodium.
22. [Fibers](fibers.md): several things at once, `Spawn`, `Wait`, `Pmap` and channels.
23. [SQLite](sqlite.md): tables, rows, queries with `?`, transactions and rows as structs.
24. [Tests](tests.md): examples in the documentation, test functions, properties, snapshots, `cesia test`, and a site
    for your project.
25. [The prompt and the debugger](debug.md): `--repl` beside a running program, breakpoints, stops on errors, fix and continue.
26. [Cells](cells.md): a notebook in a `.ce` file, cells that run again when what they read changes, a session, and
    a page to share.
27. [Speed](speed.md): what becomes machine code as a program runs, and Cesia beside Python, Node, Java, Go, OCaml, Lua
    and LuaJIT, measured: start-up, loops, maps, fibers and a server.
28. [C and C++](c.md): libraries of the system, their types, memory, callbacks, and C++ through a C layer.
29. [Native packages](native.md): a package's engine in OCaml, compiled once, its permission, and how to write one.
30. [A real program](project.md): a web service of notes on SQLite, with its tests, from `cesia new` to a server.
31. [Solving a real problem](duplicates.md): which files of a folder are duplicates, in seven steps, from the first
    measure to the proof that it is solved: properties, the birthday bound, and the times beside Python.
32. [How Cesia works](internals.md): the lexer, the parser, closures, values in memory, the hash trie of maps, the JIT,
    fibers and their scheduler, channels, the server on every core, the garbage collector and start-up, with their numbers.

Appendices, to look things up:

- [Commands](commands.md): every command of `cesia` and every option.
- [Editors](editors.md): the errors, the documentation and the definitions in Neovim, Helix and Emacs, through `cesia lsp`.
- [cesia.toml](toml.md): every table and key of a project's file.
- [Environment variables](env.md): those that Cesia reads.
- [Error messages](messages.md): every message Cesia can print, where it comes from, and what to do.
- [Modules for tools](tools.md): std/cesia, std/syntax, std/columns, std/sqlite3 and std/debug, which Cesia's own tools
  are written with.
- [Words](glossary.md): the names of the ideas of this book, as programmers say them, each with its chapter.
- [References](references.md): the papers, standards and books Cesia follows, each with what it took from them.

The reference, under [Reference](ref/index.html), lists every module, every name and every keyword, each with its examples.
