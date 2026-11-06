# Words

The words that programmers use for the ideas of this book, in alphabetical order. Each one says what it means in general,
then how Cesia does it, and leads to the chapter that shows it.

## ABI

An application binary interface: how compiled code passes arguments and lays out its data, so that code compiled apart can
call it. C has a stable one on each system and C++ has none, so Cesia reaches C++ through a small C layer: see
[C and C++](c.md).

## Anonymous function

A function without a name, written where it is used; also called a lambda. In Cesia, `x -> x + 1` on one line, or
`defn (x)` up to `end` for several: see [Functions](functions.md#functions-as-values).

## Binding

The link between a name and a value. In Cesia `=` binds a name, and binding it again gives it another value: see
[Values and names](values.md#names).

## Breakpoint

A place in the code where a debugger stops the program, to look at its variables before it goes on. In Cesia, `break FILE
LINE` in the debugger, with `if` and a condition to stop only when it holds: see
[The prompt and the debugger](debug.md#the-debugger).

## Closure

A function together with the names it saw where it was made, which it can still use after that place has ended. A Cesia
closure keeps the values those names had when it was made: see [Functions](functions.md#functions-as-values).

## Columnar data

A table kept as one array per column rather than one record per row, so that a sum or a filter runs down a whole column. A
data frame, as in pandas, is such a table; Cesia's is [std/frame]: see [Data](data.md#a-table-from-a-csv-file).

## Comprehension

A list built from another inside brackets: a value, a `for`, and a condition if needed, as in Python. In Cesia,
`[x * x for x in xs if x > 0]` is short for [list.Map] and [list.Filter]: see [Data](data.md#comprehensions).

## Concurrency and parallelism

Concurrency is several tasks in progress at once, taking turns; parallelism is several tasks running at the same instant,
on several cores. Cesia's fibers are concurrent, and its work on whole arrays and columns is parallel: see
[Fibers](fibers.md) and `CESIA_CORES` in [Environment variables](env.md).

## Dependency

Code from another project that yours uses. In Cesia a `[deps]` table of `cesia.toml` names its repository and its tag, and
`cesia pkg` fetches it into `deps/`: see [Packages](packages.md#code-from-other-projects).

## Destructuring

Taking a value apart into named pieces in one step. In Cesia a pattern of [match] does it: `[a, b]` for a list of two,
`{Name: n}` for a dictionary, `Point(x, y)` for a struct: see [Choices and loops](choices.md#match).

## Doctest

A test written as an example in the documentation of a function, so that the example can't go stale. In Cesia an indented
`call --> value` in a `(**` comment is one, and `cesia test` runs it: see [Tests](tests.md#examples-in-the-documentation).

## Error propagation

Passing an error from the function that met it up to a caller that can handle it. In Cesia `?` after a result does it: it
gives the value of an `Ok`, or returns the `Err` at once: see [Errors](errors.md#passing-an-error-on).

## Error value

An error that a function gives back as its result, so that the code shows where it goes. Cesia's errors are values: an
[result.Err] around what went wrong, beside the [result.Ok] of a success: see [Errors](errors.md).

## Exception

An error that jumps out of the code that raised it, up to a `try` that catches it. Cesia has neither: a failure that can
happen is an [error value](#error-value), and a bug stops the program with a panic: see
[Errors](errors.md#errors-and-bugs).

## Exit code

The number a program gives back to the one that started it: 0 when all went well, another when something failed. In Cesia
[sys.Exit] ends with a code, and a program stopped by a bug ends with 1: see [Files](files.md#standard-input-and-the-exit-code).

## Fiber

A light thread run by the language rather than by the system, also called a green thread: thousands of them cost little.
In Cesia [fiber.Spawn] starts one and [fiber.Wait] waits for its end: see [Fibers](fibers.md).

## Foreign function interface

The way a language calls functions written in another one, most often C; FFI for short. Cesia's is [std/c]: [c.Open] loads
a library and [c.Fn] binds a function by its types, with the `ffi` permission: see [C and C++](c.md).

## Golden test

A test that runs a program and compares all it printed with a saved output, the golden one. Cesia's own sources test the
language this way. A project tests values instead, with doctests and test functions: see [Tests](tests.md).

## Handler

The function that answers one kind of request. In [std/web] it takes the request, a dictionary, and gives the response: see
[HTTP](http.md#an-application).

## Higher-order function

A function that takes a function, or gives one back. [list.Map], [list.Filter] and [list.Reduce] take one, and `adder(n) = x -> x + n`
gives one: see [Functions](functions.md#map-filter-and-reduce).

## Hot reload

New code loaded into a program while it runs, so that it keeps its state. `cesia run --watch` does it at each save: see
[Install and first run](install.md#run-it-again-at-each-save).

## Immutability

A value that never changes once it is made: each operation gives a new value. Every value of Cesia is immutable;
`xs[1] = 5` gives the name `xs` a new list: see [Values and names](values.md#names).

## Interpreter and JIT

An interpreter runs a program step by step; a just-in-time compiler, a JIT, turns the parts that run often into machine
code as the program runs. Cesia's JIT takes the functions and loops that get hot, numbers, arrays, maps and structs: see
[Speed](speed.md).

## Lexical scope

The names a piece of code sees are those written around it, not those of its caller. In Cesia a function sees its
parameters, its own names and those of its file; a name given a value inside it is its own, and `if` and `for` make no
scope: see [Functions](functions.md).

## Lock file

A file that keeps the exact version and fingerprint of each dependency, so that every machine installs the same code.
Cesia's is `cesia.lock`, which `cesia new` and `cesia pkg` write: see [Packages](packages.md#code-from-other-projects).

## Message passing

Tasks that share data by sending it to each other, instead of changing the same memory. In Cesia a [fiber.Channel] carries values
from one fiber to another, with [fiber.Send] and [fiber.Receive]: see [Fibers](fibers.md#channels).

## Method and receiver

A method is a function attached to a type, and its receiver is the value it is called on. `defn (r Rect) Area()` names its
receiver `r` in parentheses before the name, and `r.Area()` calls it: see [Structs](structs.md#methods).

## Middleware

Code between a server and its handlers, which sees each request and each response: a log, a header, a check. [web.Wrap]
puts one in front of an application: see [HTTP](http.md#middleware).

## Null

A value that means "no value": `null`, `nil` or `None` in other languages. Cesia's is `missing`, and a type takes it only
with a `?`, as `Text?`: see [Values and names](values.md#missing) and [Types](types.md#maybe-missing).

## Optional typing

Types that a program may write or leave out. In Cesia types are a plus: code without them runs as fast, and a type that is
written is checked each time a value comes in: see [Types](types.md).

## Package

Code grouped under a name, also called a module, whose names you reach through it: its namespace. In Cesia a package is a
folder of `.ce` files: `use std/sql` brings one in, and `sql.Open` names a public function of it: see
[Packages](packages.md).

## Parameterized query

A query whose values travel apart from its SQL text, so that no input typed by a user can change the query: a SQL
injection. In [std/sql] each `?` takes a value of the list: see
[SQLite](sqlite.md#values-never-go-into-the-text).

## Pattern matching

Comparing a value with shapes, in order, and running the code of the first that fits, with names for its pieces. [match]
does it on values, lists, dictionaries, structs and results: see [Choices and loops](choices.md#match).

## Persistent data structure

A structure that keeps its old version when it changes, and shares most of its memory with the new one. A dictionary of
Cesia is a hash trie, as in Clojure: [dict.Put] gives a new one that shares the rest with the old: see [Maps](maps.md).

## Preemptive scheduling

The scheduler moves from one task to another by itself, without waiting for the task to give way. Cesia moves between
fibers after a number of steps, so a long computation doesn't hold up the others: see [Fibers](fibers.md#what-waits).

## Principle of least privilege

A program gets the rights it needs, and no more. In Cesia, `--allow read=./data` rather than `read`, and `net=:8080` rather
than `net`: see [Permissions](permissions.md#allow).

## Pure function

A function whose result depends on its arguments only, and that does nothing else: no print, no file, no clock. A Cesia
function can't change the values it is given: it is pure when it leaves the outside world alone. See
[Functions](functions.md).

## REPL

Read, eval, print loop: a prompt that runs each expression typed and shows its value. Cesia's runs beside the running
program, `cesia run --repl app.ce`, inside the package of its main file: see
[The prompt and the debugger](debug.md#the-prompt).

## Route

A rule that sends the requests of one method and one path to a handler. [web.Get] and [web.Post] add one, and
`:name` in a path takes any word: see [HTTP](http.md#an-application).

## Sandbox

A place where a program runs with only the rights it was given. A Cesia program starts in one, and each `--allow` gives it
a capability: the right to one kind of thing, within a scope. See
[Permissions](permissions.md).

## Seed

The number a generator of random numbers starts from: the same seed gives the same numbers, so a run can be replayed. A Cesia
run takes one from the system, [random.Seed] tells it, and `cesia run --seed N` gives it: see
[Data](data.md#the-same-numbers-again).

## Short-circuit evaluation

`and` and `or` stop as soon as the answer is known, so their right side may never run: `false and f()` never calls `f`. See
[Values and names](values.md#true-and-false).

## Side effect

What a function does besides giving its result: printing, writing a file, sending a request. In Cesia each one that
touches the machine needs a permission, so the command line says which a program may have: see [Files](files.md).

## Standard input and output

The text a program reads, and the text it writes, in a terminal or a pipe of the shell; the standard error is a second
output, for what went wrong. In Cesia [io.Print] writes to the standard output, [io.PrintError] to the standard error, and
[sys.ReadInput] reads the whole standard input: see [Files](files.md#standard-input-and-the-exit-code).

## String interpolation

Values written inside a text, where they go. In Cesia `"Hello, $name"` and `"$(2 + 2)"`, which are short for [text.Str]: see
[Values and names](values.md#texts).

## Struct

A value with a fixed set of named fields, also called a record. [struct] declares one, with defaults and types, and a field
written wrong is an error: see [Structs](structs.md).

## Structural typing

A value meets a type by what it has, not by a declaration that names the type. A Cesia [interface] is met by every value
that has its methods, as in Go: see [Types](types.md#interfaces).

## Sum type

A type whose values are one of a few cases, each with its own data. Cesia's is the result: either [result.Ok] of a value or [result.Err]
of an error, and [match] takes it apart case by case: see [Errors](errors.md#looking-at-a-result).

## Syntax sugar

A shorter way to write what the language can already say. This book shows each one beside its plain form, checked:
`a..b` is [list.Range]`(a, b)`, and `d.Name` is `d["Name"]`: see [Lists and arrays](lists.md#ranges).

## Transaction

Changes to a database that happen all together or not at all. SQLite's are ACID: atomic, consistent, isolated and durable.
[sql.Transaction] keeps them all on an `Ok`, and undoes them all on an `Err` or a panic: see [SQLite](sqlite.md#transactions).

## Type coercion

A value turned into another type by the language itself. Cesia does it in one case: an `Int` becomes a `Float` where a
`Float` is wanted, or beside one in arithmetic. A text never becomes a number by itself: see
[Types](types.md#an-int-becomes-a-float).

## UTF-8

The usual way to write a text in bytes: `a` takes one, `é` two, an emoji four. A text of Cesia is UTF-8: [value.Len] and [text.Slice]
count characters, [text.ByteLength] and [text.ByteSlice] bytes: see [Texts](texts.md#bytes).

## Value semantics

Giving a value a second name, or passing it to a function, acts as a copy: a change through one name never shows through
the other. Every value of Cesia works this way, lists and dictionaries too: see [Values and names](values.md#names).

## Vectorized operation

One operation on a whole array, run element by element by the machine instead of a loop of the program. In Cesia,
`prices * 2` and `Sqrt(xs)` work on whole arrays, and on the columns of a frame: see
[Lists and arrays](lists.md#whole-arrays-at-once).
