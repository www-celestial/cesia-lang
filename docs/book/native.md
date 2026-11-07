# Native packages

In this chapter you write a package whose heart is OCaml compiled to machine code: its engine. A database, a solver, a
codec: work that needs its own data structures and every nanosecond. The engine is compiled once, by the package's author,
and Cesia loads it at the first call of one of its natives, as it loads its own JIT. Nobody who uses the package compiles
anything.

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

Its engine is a file of the package, `native/echo-TAG.cmxs`, where `TAG` is what [cesia.Native] gives:
`1-ocaml5.5.0-linux-x86_64`, the version of the native interface, the OCaml that built this Cesia and the system. Like each
file of `deps/`, it loads only as `cesia.lock` says it was installed. An engine made for another Cesia's OCaml is refused,
with what to do; one that is missing names the tags it has:

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
natives = ["reverse", "later"]
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
(** Echo: lists the other way round, and values that come back later. *)

Reverse(items) = reverse(items)  (** A list, the other way round. *)
Later(seconds, v) = later(seconds, v)  (** An Ok of v, after so many seconds. *)
```

The tools read the names from `cesia.toml`, so `cesia check` and the editor know them without running the engine.

### The engine

The engine reaches the values of the program only through the module `Cesia_v1`, whose types are abstract: it makes and
reads values by its functions, never by their shape, which is Cesia's own and changes between releases. That is why an
engine compiled once loads in every later Cesia built with the same OCaml.

```ocaml
module C = Cesia_v1

let reverse ctx a =
  let n = C.length a.(0) in
  C.list ctx (Array.init n (fun i -> C.item ctx a.(0) (n - 1 - i)))

(* The work goes on a domain of the engine; the other fibers run until resume wakes this one. *)
let later ctx a =
  let seconds = C.to_float ctx "echo.Later" a.(0) in
  C.suspend ctx (fun resume -> ignore (Domain.spawn (fun () -> Unix.sleepf seconds; resume ())));
  C.ok ctx a.(1)

let () = C.register [ "reverse", 1, 1, reverse; "later", 2, 2, later ]
```

`register` takes each native's name, its fewest and most arguments, and its code. The names must be those of `[native]`.

### Building it

The engine is compiled against `cesia_v1.cmi` alone, from the Cesia that will load it; a Cesia built from its sources holds
it in `_build/default/src/native/.cesia_native.objs/byte/`. The engine's file holds its own modules, and none of the Stdlib
or of Unix, which Cesia's binary holds:

```bash
ocamlfind ocamlopt -package unix -I CESIA_NATIVE -shared -o native/echo-$(cesia run tag.ce).cmxs engine/echo.ml
```

where `tag.ce` prints [cesia.Native]. The OCaml must be the one that built that Cesia: the tag says which. Then
`cesia test` runs the tests of the Cesia side, on the engine just built.

## The rules of an engine

- **Values.** Between two calls, an engine keeps OCaml data, never a value: Cesia changes in place a list, a map or a struct
  that nothing else holds. A handle names what the engine keeps: `C.handle "echo.thing" 3`, a kind named after the
  package. A handle has no finaliser: the package gives a `Close`.
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

| Function | What it does |
|---|---|
| `missing`, `bool b`, `int i`, `float x`, `text s` | a value; the text is UTF-8, not copied |
| `list ctx values` | a list of these values, counted for `--limit memory` |
| `keys names`, `record ctx keys values` | the field names of maps, made once, and a map with a value for each |
| `handle kind n` | a handle of this kind and number |
| `ok ctx v`, `err ctx v` | `result.Ok(v)` and `result.Err(v)` |
| `kind v` | what a value is: `Missing`, `Bool`, `Int`, `Float`, `Text`, `List`, `Map`, `Struct`, `Function`, `Handle`, or `Other` |
| `to_bool`, `to_int`, `to_float`, `to_text` `ctx name v` | the value, or a panic that names the native: an `Int` is taken as a `Float` |
| `length v`, `item ctx v i`, `field v name` | the items of a list or the fields of a map or a struct; an item from 0; a field, or missing |
| `names v`, `values v` | the field names of a struct, or the text keys of a map, and their values |
| `handle_id ctx name kind v` | the number of a handle of this kind, or a panic |
| `suspend ctx f` | parks the fiber and calls `f resume`; `resume` wakes it once, from any domain |
| `need_read ctx path`, `need_write ctx path` | a panic unless the program may read or write the path |
| `panic ctx message` | stops the fiber, as [bug.Panic] |
| `pay ctx n`, `reserve ctx words` | counts a walk over values for `--limit steps`, and memory the engine holds for `--limit memory` |
| `register natives` | the natives of the engine, once, as it starts |

`cesia_v1.mli` never changes once released, not even a comment: OCaml checks each byte of it in every engine. What comes
later goes in new modules, `Cesia_v1_1` and on, and an engine that needs one says so with the `cesia` of its `[project]`.

## Next

Your packages can bring native code. The last chapter, [A real program](project.md), puts the chapters together: a small
web service on SQLite, with its tests, from `cesia new` to a server that runs.
