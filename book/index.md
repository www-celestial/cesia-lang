# Cesia

Cesia is a small language for solving real problems directly. Use it for:

- a script that cleans a CSV;
- a web server on a database;
- a program that drives other programs.

It starts at once and is safe by default, and when something goes wrong it says what to write.

```cesia
Print("Hello from Cesia")
```

This book teaches Cesia from the start. Every example on these pages ran when the site was built, and the text under it is what
it printed. When the site builds, an example that gives another result stops the build, so the book can't drift from the
language.

## How to read it

- Read the chapters in order the first time: each one uses what the ones before it showed.
- Type the examples yourself, in a file or in your editor. Change them and run them again: that is the fastest way to learn.
- A name in the text leads to its page in the reference: [Print], for instance, or the keyword [match].
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
13. [Files](files.md): reading, writing, folders, arguments, other programs and the clock.
14. [Data](data.md): comprehensions, groups, counts and ranks, tables of columns from a CSV file.
15. [JSON and CSV](json.md): reading, writing, and checking what comes in.
16. [HTTP](http.md): a web server with routes and JSON, tested without the network, and the client.
17. [Fibers](fibers.md): several things at once, `Spawn`, `Wait`, `Pmap` and channels.
18. [SQLite](sqlite.md): tables, rows, queries with `?`, transactions and rows as structs.
19. [Tests](tests.md): examples in the documentation, test functions, `cesia test`, and a site for your project.
20. [C and C++](c.md): libraries of the system, their types, memory, callbacks, and C++ through a C layer.
21. [Cemacs](cemacs.md): the editor written in Cesia, its keys, its band of hints, and how to change it.
22. [A real program](project.md): a web service of notes on SQLite, with its tests, from `cesia new` to a server.

The reference, under [Reference](ref/index.html), lists every module, every name and every keyword, each with its examples.
