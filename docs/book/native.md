# Native packages

In this chapter you write a package whose heart is OCaml compiled to machine code, the instructions that the processor runs
directly: its engine. A database, a solver, a codec: work that needs its own data structures and every nanosecond. The
engine is compiled once, by the package's author, and Cesia loads it at the first call of one of its natives, as it loads
its own JIT. Nobody who uses the package compiles anything.

For a library of C that exists already, use [std/c](c.md). A native package is for new native code, in OCaml.

## Total trust

An engine is machine code that runs with the rights of the program: Cesia's permissions and limits stop at its door. So a
program needs `native=LABEL` to run one, where `LABEL` is the label of the package's `[deps]` in its `cesia.toml`, or the
name of the project for its own engine:

```bash
cesia run --allow native=echo main.ce
```

A package that is honest asks Cesia for the permissions of what the program gives it, a path to read for instance. Cesia
can't make a dishonest one ask: `native=` is the trust you give to its author, as `ffi=` is for a C library. `cesia check`,
`doc`, `lsp`, `fmt` and `pkg` never load an engine: opening a project in an editor runs no native code.

## Using one

A native package is used as any package of another project, and its natives are private names of the package, which its
own functions wrap:

```text
use deps/someone/echo/cesia/echo
use std/io
io.Print(echo.Reverse([1, 2, 3]))
```

Its engine is a file of the package, `native/echo-TAG.cmxs`. A `.cmxs` is an OCaml plugin: a shared library (a file of
machine code that a running program loads and links to itself, as a `.so` on Linux or a `.dll` on Windows). `TAG` is what
[cesia.Native] gives: `1-ocaml5.5.0-linux-x86_64`, the version of the native interface, the OCaml that built this Cesia and
the system. Like each file of `deps/`, it loads only as `cesia.lock` says it was installed. An engine made for another
Cesia's OCaml is refused, with what to do; one that is missing names the tags it has:

```text
deps/someone/echo has no engine for 1-ocaml5.5.0-linux-x86_64 (it has 1-ocaml5.4.0-linux-x86_64): run cesia pkg install.
```

The engine stays loaded until the process ends. `cesia run --watch` keeps it from one run to the next, and says so if its
file changed meanwhile.

## Writing one

### The project

The `[native]` table of the package's `cesia.toml` names the Cesia package whose files see the natives, and the natives.
Each one is a private name, with a small first letter: the public names are those of the Cesia side, documented.

```toml
[project]
name = "echo"
src = ["cesia"]

[native]
package = "cesia/echo"
natives = ["echo4", "reverse", "later"]
```

```text
echo/
  cesia.toml
  cesia/echo/echo.ce     the Cesia side: the public functions, documented
  engine/echo.ml         the OCaml side: the natives, on Cesia_v1
  native/                the engines built for each Cesia
```

The Cesia side wraps the natives, as `std/list` wraps its own:

```text
(** Echo: maps made again, lists the other way round, and values that come back later. *)

Echo4(i, x, s, b) = echo4(i, x, s, b)  (** A map of four values, each read and made again by the engine. *)
Reverse(items) = reverse(items)  (** A list, the other way round. *)
Later(seconds, v) = later(seconds, v)  (** An Ok of v, after so many seconds. *)
```

The tools read the names from `cesia.toml`, so `cesia check` and the editor know them without running the engine.

### The engine

The engine reaches the program only through the module `Cesia_v1`, the native interface. It sees each value of the program
as a `Cesia_v1.value`, a variant: an OCaml type whose value is one of a few named cases, each with its own data, as a
[sum type](glossary.md#sum-type) is. The simple values are OCaml's own, `Int 3` or `Text "a"`, so the engine makes and
reads them with OCaml's constructors and `match`, without asking Cesia. A list, a map, a struct or a function is a
`compound`, whose layout is Cesia's own and changes between releases: the engine reads it only through the functions of
`Cesia_v1`. That is why an engine compiled once loads in every later Cesia built with the same OCaml.

```ocaml
module C = Cesia_v1

(* The engine's own readers of arguments: a match each, and Cesia's message for a wrong one. *)
let int ctx name = function C.Int i -> i | v -> C.need ctx name "an Int" v
let float ctx name = function C.Float x -> x | C.Int i -> float_of_int i | v -> C.need ctx name "a Float" v
let text ctx name = function C.Text s -> s | v -> C.need ctx name "a Text" v
let bool ctx name = function C.Bool b -> b | v -> C.need ctx name "a Bool" v

(* The names of the fields, made once: their hashes are computed here, not at each call. *)
let four = C.keys [| "Int"; "Float"; "Text"; "Bool" |]

let echo4 ctx a =
  let name = "echo.Echo4" in
  C.record ctx four
    [| Int (int ctx name a.(0)); Float (float ctx name a.(1)); Text (text ctx name a.(2)); Bool (bool ctx name a.(3)) |]

let reverse ctx a =
  match a.(0) with
  | C.List l -> let n = C.length l in C.list ctx (Array.init n (fun i -> C.item ctx l (n - 1 - i)))
  | v -> C.need ctx "echo.Reverse" "a list" v

(* The work goes on a domain of the engine; the other fibers run until resume wakes this one. *)
let later ctx a =
  let seconds = float ctx "echo.Later" a.(0) in
  C.suspend ctx (fun resume -> ignore (Domain.spawn (fun () -> Unix.sleepf seconds; resume ())));
  C.ok ctx a.(1)

let () = C.register [ "echo4", 4, 4, echo4; "reverse", 1, 1, reverse; "later", 2, 2, later ]
```

```text
echo.Echo4(1, 2, "a", true)    gives {Int: 1, Float: 2.0, Text: "a", Bool: true}
echo.Echo4(1, 2, 3, true)      stops: echo.Echo4 needs a Text, not the number 3.
```

`register` takes each native's name, its fewest and most arguments, and its code: a function of the calling fiber, `ctx`,
and of the arguments, which gives the result. The names must be those of `[native]`. A domain is OCaml's unit of
parallelism, a thread of the system that runs OCaml code beside Cesia's own; a [fiber](glossary.md#fiber) is one of
Cesia's light threads, many to a domain.

### Building it

The engine is compiled against `cesia_v1.cmi` alone: the compiled form of the interface file `cesia_v1.mli`, which holds the
types and the signatures of `Cesia_v1` and no code. A Cesia built from its sources holds it in
`_build/default/src/native/.cesia_native.objs/byte/`. The engine's file holds its own modules, and none of the Stdlib or of
Unix, which Cesia's binary holds:

```bash
ocamlfind ocamlopt -package unix -I CESIA_NATIVE -shared -o native/echo-$(cesia run tag.ce).cmxs engine/echo.ml
```

where `tag.ce` prints [cesia.Native]. The OCaml must be the one that built that Cesia: the tag says which. Then
`cesia test` runs the tests of the Cesia side, on the engine just built.

## The rules of an engine

- **Values.** Between two calls, an engine keeps OCaml data, never a `compound`: Cesia changes in place a list, a map or a
  struct that nothing else holds. A compound that the engine gives back, as a result or inside a list, is marked shared, so
  a later write of the program copies it first. A handle names what the engine keeps: `Handle ("echo.thing", 3)`, a kind
  named after the package, and a number. A handle has no finaliser, the code that a garbage collector would run when it
  frees a value: the package gives a `Close`.
- **Domains.** Only Cesia's domain, the main one, touches values. The engine's domains do the long work, and give the
  hand back by the `resume` of `suspend`, the one function that any domain may call. A native that blocks without
  `suspend` blocks every fiber. An engine never calls `Gc.set`, `Unix.fork` or `Sys.set_signal`.
- **Exceptions.** An OCaml exception that leaves a native becomes a panic that names it:
  `echo.boom raised Not_found: a bug of its native package.` Cesia's own panics and limits cross the engine untouched, so
  it never writes `with _ ->` around a call to `Cesia_v1`. A fiber cancelled while it waits in `suspend` stops at once,
  and the late `resume` does nothing.
- **Modules.** An engine may use the modules of the Stdlib and of Unix that Cesia's binary holds, and brings its own. It
  can't bring a module that the program or another engine holds already, nor one whose name starts with `Cesia`, nor reach
  inside Cesia past `Cesia_v1`: the engine is refused before any of its code runs, and the message names the module.

## Cesia_v1

### The values

| Case | What it is |
|---|---|
| `Missing` | `missing` |
| `Bool b`, `Int i`, `Float x` | `true` and `false`, a whole number of 63 bits, a 64-bit float |
| `Text s` | a text, UTF-8; the string is the program's own, not copied |
| `Handle (kind, n)` | a handle of this kind and number, as `<echo.thing 3>`; a handle of Cesia's own that holds a task is `Other` |
| `List c` | a list, an array of one dimension |
| `Map c`, `Struct c` | a map, a struct |
| `Function c` | a function, which an engine can't call in this version |
| `Other c` | anything else, as a matrix, and whatever later releases add |

### The functions

| Function | What it does |
|---|---|
| `list ctx values` | a list of these values, counted for `--limit memory` |
| `keys names` | the field names of maps, made once at the engine's start, each name once; their hashes computed then |
| `record ctx keys values` | a map with a value for each name of `keys`, in order: a panic if their numbers differ |
| `ok ctx v`, `err ctx v` | `result.Ok(v)` and `result.Err(v)` |
| `length c` | the items of a list, the fields of a map or a struct; 0 for anything else |
| `item ctx c i` | an item of a list, from 0: a panic if `i` is outside it, or if `c` is no list |
| `fields keys c` | the fields of a map or a struct with the names of `keys`, in order, `Missing` for a name it lacks, in one call |
| `names c`, `values c` | the field names of a struct, or the text keys of a map, in order, and their values |
| `need ctx name what v` | a panic that names the native, what it needs and what it got: `echo.Echo4 needs a Text, not the number 3.` |
| `suspend ctx f` | parks the fiber and calls `f resume`; `resume` wakes it once, from any domain |
| `need_read ctx path`, `need_write ctx path` | a panic unless the program may read or write the path |
| `panic ctx message` | stops the fiber, as [bug.Panic] |
| `pay ctx n`, `reserve ctx words` | counts a walk over values for `--limit steps`, and memory the engine holds for `--limit memory` |
| `register natives` | the natives of the engine, once, as it starts |

`cesia_v1.mli` never changes once released, not even a comment. OCaml writes in each compiled file a digest, an MD5
checksum, of every interface it was compiled against, and refuses to load a plugin whose digests differ from the program's:
one byte changed in `cesia_v1.mli` would refuse every engine built before. What comes later goes in new modules, `Cesia_v1_1`
and on, and an engine that needs one says so with the `cesia` of its `[project]`.

## What a call costs

A value crosses the interface by a conversion. Cesia's layout stays private, so `Int 3` in the engine and `3` in the
program are two different blocks of memory, and each crossing makes the other one: an allocation, a few words of the minor
heap, the young part of memory that OCaml's garbage collector empties often. Allocating is cheap but not free: 0.6 to 0.8
ns a word in these loops. Each argument of a native is converted on the way in, and its result on the way out; `record`,
`list` and `fields` convert their values in one call.

Four fields made by `record` and read back by `fields`, against the same work by Cesia's own code (measure 1):

| | 2 MB minor heap | 16 MB, as Cesia runs |
|---|---|---|
| through `Cesia_v1`, against Cesia's own code | +24.7 ns (88.4 against 63.8), 95% interval 24.2 to 25.1, n=40 | +27.8 ns (98.5 against 70.4), 95% interval 26.5 to 28.7, n=40 |
| its first form, never released: a call to Cesia for each value | +60.9 ns (166.2 against 105.9), 95% interval 59.4 to 65.9, n=40 | +64.4 ns (178.7 against 115.7), 95% interval 62.1 to 68.2, n=40 |

From a Cesia program, a million calls (measure 2), against the first form of the interface (never released), which gave
an engine Cesia's own values and a call for each:

| Call | Now | First form | Difference |
|---|---|---|---|
| `math.Near(i, 2.0, 1e-9, 0.0)`, a native of std/math, through a Cesia function | 134 ns | 134 ns | -0.0 ns (-2.1 to +2.6) |
| `mk(i, 2.0, "a", true)`, a Cesia function that makes a map of 4 | 52 ns | 52 ns | +0.6 ns (-0.4 to +1.3) |
| `echo.Echo4(i, 2.0, "a", true)`, a package native that reads 4 arguments and makes a map of 4 | 170 ns | 160 ns | +8.4 ns (+6.9 to +12.8) |
| `echo.Same(i, 2.0, "a", true)`, a package native that gives back its first argument | 118 ns | 91 ns | +26.1 ns (+25.0 to +27.6) |

Cesia's own natives don't cross `Cesia_v1`, and don't move. A package native pays for its arguments: called from OCaml
without the interpreter, converting 4 arguments and the result costs about 20 ns (`same`: 29.8 ns against 10.1). On this
machine a box of two words costs about as much as a call, so for `echo4` the conversions cost a little more than the calls
they save; an engine that reads and makes maps saves the most (measure 1).

The first call of a package's natives loads the plugin of `Cesia_v1` and the engine, and checks the engine's
fingerprint: 548 µs (95% interval 536 to 564, n=1000) for the 45 KB engine of the tests more than a run that calls none.

### Beside the giants

The same task in each system: a function takes an integer, a float, a text and a boolean, reads each, and gives a new
record of the four, called a million times from a loop of the host language. Once written in the host language, once in
native code through the system's native interface; the price is the difference.

| System | Host function | Through its native interface | Price |
|---|---|---|---|
| Cesia, a native package | 50.0 ns | 164.9 ns | +114.3 ns (+113.8 to +115.3) |
| CPython 3.14, a C extension (METH_FASTCALL) | 209.0 ns | 203.8 ns | -3.0 ns (-3.7 to -2.6) |
| Node.js 26, Node-API | 19.2 ns | 1307.8 ns | +1287.3 ns (+1273.3 to +1298.6) |
| Java 21 (HotSpot), JNI | 9.4 ns | 174.0 ns | +165.1 ns (+164.5 to +166.8) |
| OCaml 5.5, an `external` in C | 6.3 ns | 24.2 ns | +17.9 ns (+17.8 to +18.4) |

Where a giant wins, and why:

- **OCaml's `external`** crosses for 18 ns: a direct call to C, which reads and makes OCaml's own values in place. That is
  what `Cesia_v1` refuses an engine on purpose: an engine that knew Cesia's layout would have to be rebuilt at each release.
- **CPython's C extension** costs no more than a Python function, because a Python call is itself slow (209 ns) and the C
  code reads Python's objects in place, at the price of a binary per Python version (but for the limited API).
- **Cesia's** price, 114 ns, is mostly the call of a native from a Cesia program, not `Cesia_v1`: the Cesia function
  `Echo4` that wraps the native, the stub, the count of the arguments, the guard that turns an exception into a panic, and
  the conversion of the 4 arguments and of the result (about 20 ns, measured apart). Making and reading the map through
  `Cesia_v1` costs 25 ns more than Cesia's own code (measure 1).
- **Java's JNI** pays 165 ns because `NewObject` calls the record's constructor from C, a call from native code back into
  Java.
- **Node-API** pays 1.3 µs: each `napi_set_named_property` makes the property's key from a C string and goes through V8's
  handles, while an object made in JavaScript is made inline by V8's JIT in 19 ns.

How these were measured: on one machine, an Intel Core i7-4720HQ (4 cores, 8 threads, 2.6 GHz) under Linux, release
builds, each run under a lock that keeps the machine's other benchmarks out; the host and the native loop alternated by
round, the systems alternated by process; 40 rounds of a million calls each. Each number is a median, and each price the
median of the per-round differences with its 95% interval, by bootstrap. Measure 1 is an OCaml program that loads a real
engine, built against `cesia_v1.cmi` alone, and compares it with the same maps made and read by Cesia's own code, hashes
computed once on both sides.

## Next

Your packages can bring native code. The last chapter, [A real program](project.md), puts the chapters together: a small
web service on SQLite, with its tests, from `cesia new` to a server that runs.
