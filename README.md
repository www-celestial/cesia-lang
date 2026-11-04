# Kepler

A small interpreted language, written in OCaml. Fast, safe by default, with fibers, files, processes, HTTP and C calls.

## Install

```bash
dune build --profile release
ln -s "$PWD/_build/default/src/bin/main.exe" ~/.local/bin/kepler
```

## Write and run a program

```bash
kepler new hello       # creates hello/, with kepler.toml and src/main.k
cd hello
kepler do run

kepler run src/main.k           # or run any file directly
kepler run --watch src/main.k   # reloads the code at each save
```

`examples/tour.k` shows the language in one file. `examples/notes.k` is a web app in 23 lines. `examples/stats.k` works on a table.

## Permissions

A program can touch nothing outside itself until the command line allows it.

| Permission | Allows |
|---|---|
| `read`, `read=./data` | reading files |
| `write`, `write=./out` | writing files |
| `net`, `net=:8080` | the network |
| `exec`, `exec=git` | running commands |
| `env`, `env=HOME` | environment variables |
| `ffi=NAME` | loading a C library, which is total trust |
| `all` | everything |

```bash
kepler run --allow read=./data,net=:8080 server.k
kepler run --limit memory=512M,steps=1000000 program.k
```

## A project

A `kepler.toml` next to the code declares what can be run, and which C libraries are used:

```toml
[project]
name = "notes"

[tasks.serve]
file = "notes.k"
allow = ["read=notes.txt", "write=notes.txt", "net=:8080"]
```

```bash
kepler do          # lists the tasks
kepler do serve    # runs one, and shows the exact command
```

## Names

A name says by its first letter whether it is public, as in Go.

- A capital is public: `rope.LineCount`, `ui.Dark`, `Print`. So is a field: `date.Year`, `err.Kind`, `Ok(Value = 1)`.
- A small first letter is private, and visible only in its package: `chunk`. So is a small field, and using one from another
  package is an error at load time.
- Local variables, parameters and named arguments are small: `sdl.Open("t", 1, 2, f, size = 13)`. So are modules and files: `use rope`. A file name separates its words with `-`: `material-scene.k`.
- A name has no `_`: words join by capitals, `byteLength` or `ByteLength`. The lone `_` is the wildcard of a pattern.
- A test is a private function with no parameter, `is` then a capital: `isGrows()`.
- Dictionary keys and texts are data: `{"a": 1}`, `{Kind: "box"}`. `json.Text` writes the fields of a record as they are, with their
  capitals: a dictionary gives other keys.

## Methods

A struct holds its fields on one line, or in a block with one field per line, until `end`, which leaves room for a comment on
each. Both forms build the same values, with the same defaults, named arguments, patterns and methods.

```kepler
struct Point { X, Y = 0 }

-- A car on the road.
struct Car
  Mass
  Speed = 0.0   -- metres per second
end
```

A struct can have methods. An instance method writes its object apart, as in Go, and a static method has the name of the struct
before its own. A dot calls both.

```kepler
struct Rect { X, Y, Width, Height }

defn Rect.Square(side)                 -- static: no object
  Rect(0, 0, side, side)
end

defn (r Rect) Area()                   -- instance: the object is written apart
  r.Width * r.Height
end

(r Rect) IsEmpty() = r.Width == 0      -- the short form
(r Rect) Moved(dx, dy) = Rect(r.X + dx, r.Y + dy, r.Width, r.Height)
(r Rect) center() = r.X + r.Width / 2  -- private: a small first letter
Rect.Unit() = Rect(0, 0, 1, 1)

r = Rect.Square(10)
Print(r.Area())
Print(r.Moved(1, 2).Area())
Print(r then it.Area())
```

- The parameters of a definition are those of the call: `defn (r Rect) Moved(dx, dy)` is called `r.Moved(1, 2)`.
- A method belongs to a `struct` of the same package. Text, arrays and records have none.
- Values don't change in place: `r` is a copy, and a method gives a new value, like a value receiver in Go.
- `r.Area()` looks at a field first, then at the methods of the struct of `r`, so a field that holds a function still works:
  `look.Width("M", "code")`. A method goes with its value: `d.Year()` works on any value of that struct, made in any file.
- A small method is private: it can only be called in the package of its struct. A capital one is public, and needs a comment.
- Through a module: `date.Date.Parse("...")`. `:` is only a range, as in `1:n`, and has nothing to do with methods.
- An instance method is called, and is not a value: `r.Area` alone is an error, and `Map(it.Area(), rects)` is how to pass one
  along. A static method is a function like any other: `Map(Rect.Square, sizes)`.

`Rect.Area()` on an instance method and `r.Square(2)` on a static one are errors that say what to write. So are `(r Rect) Area`
with `Rect.Area` in one struct, and a method named like a field.

## Types

A field or a parameter can have a type, written after its name. Code without types runs as before, and costs the same.

```kepler
struct Point { X Int, Y Int = 0 }
struct Line { From Point, To Point = Point(0) }

-- A car on the road.
struct Car
  Mass Float
  Speed Float = 0.0   -- metres per second
  Name Text?          -- missing unless it is given
end

defn Describe(l Line, prefix Text = "")
  "$prefix$(l.From.X)"
end

(r Rect) Scaled(by Number) = Rect(r.X, r.Y, r.Width * by, r.Height * by)   -- the Rect above
```

- The types are `Int`, `Float`, `Number` (an `Int` or a `Float`), `Bool`, `Text`, `Array`, `Dict`, `Function`, the structs,
  `Point`, or `geo.Point` for one of a package the file uses, and the interfaces below. `?` also takes `missing`: `Text?`, and a
  field of such a type without a default has `missing` as its default. As a type, `Text` and `Dict` are not the functions of
  those names.
- Where: the fields of a struct, in both forms, and the parameters of `defn`, of a short definition and of a method. Not on a
  lambda: `(p Point) -> p.X` is an error, and `defn (p Point) p.X end` the way to write it.
- When: each time a value enters its place. At construction for a field, at each call for a parameter, once its default is put
  in, and at each write of a typed field, also inside a path: `d.Lines[2].From = p`.
- An `Int` where a `Float` is wanted becomes a `Float`: `Car(1500).Mass` is `1500.0`. `Number` keeps either.
- A wrong value is a bug: the program stops, `Line: From must be a Point, found an Int.`, at the call or the write. A type that
  names nothing, `Pont`, is an error before the program starts.
- Under `--watch`, a changed type applies at the next call, construction or write; values made before are not checked again.
- When two structs have one name, the message names their packages: `r must be a geo.Rect, found a shapes.Rect.`

## Interfaces

An interface lists methods, with no code. A value meets it when it has each of them with that number of parameters, written
apart from the object: nothing declares it, as in Go.

```kepler
-- Something with an area and a perimeter.
interface Shape
  Area()
  Perimeter()
end

interface Named { Name() }

(r Rect) Perimeter() = 2 * (r.Width + r.Height)   -- the Rect above, which has its Area()

(s Shape) Describe() = "area $(s.Area()), perimeter $(s.Perimeter())"

defn Total(shapes Array)
  sum = 0
  for s in shapes
    sum += Measured(s)
  end
  sum
end

Measured(s Shape) = s.Area() + s.Perimeter()

Print(Rect.Square(2).Describe())
Print(Total([Rect.Square(1), {Area: () -> 2, Perimeter: () -> 6}]))
```

- Both forms, as for a struct: one method per line until `end`, or `{ Area(), Perimeter() }`. A method has no body. Its
  parameters may have types, `Scaled(by Number)`, and only their number counts to meet the interface.
- A struct meets an interface through its methods, or through fields that hold functions; a record through fields that hold
  functions. The answer is kept for each shape of value, and forgotten when a file reloads.
- An interface is a type: `s Shape`, `Inner Shape?`, `s geo.Shape`. A value that doesn't meet it stops the program, and the
  message names what it lacks: `Measured: s must be a Shape, found a Circle, which has no Perimeter().`
- A method on an interface, `(s Shape) Describe()`, is a method of every value that meets it, records too. A field or a method
  of the value itself wins over it. A call looks at the interfaces of its package and of the packages its file uses; when two of
  them give the method to a value that meets both, the call stops and names them.
- A small interface or method is private to its package, as any name, and a public interface needs a comment.
- Not there: an interface made of others, `match` on an interface, types with parameters.

## Packages

A package is a folder, as in Go: there is no import by file, and no `package` line.

```
myproject/
  kepler.toml
  src/
    main.k
    geometry/
      rect.k
      circle.k
      shapes/
        square.k
  tests/
```

```kepler
-- src/main.k
use geometry
use geometry/shapes

r = geometry.Rect(2, 3)
Print(r.Area(), shapes.Square(2))
```

- The code of a project goes in `src/`. A `use` is absolute: it looks in the `src` folder of the root of the project, then at the root
  itself, so `use geometry` finds `src/geometry/` from any file, and `use tests/helpers` a folder out of `src/`. If both exist, `src/`
  wins. The root is the folder of the nearest `kepler.toml` above the program or, without one, the folder of the file that runs. A
  `use` takes no `./`, no `../` and no quotes.
- The name in the code is the last part of the path: `use geometry/shapes` gives `shapes.Square`, and `as` renames it. Two uses of
  a file can't give one name.
- A package is all the `.k` files of its folder, in the order of their names. Its subfolders are other packages, and its `.test.k`
  files aren't part of it.
- The files of a package need no `use` to see each other, and share their small names, fields and methods. Each file keeps its own
  `use`. Two files of a package can't define one name, but the variable of a loop stays in its file.
- The standard library doesn't change: `use rope`. A folder of the project with the name of one of its modules is an error, once used.
- `kepler run file.k` runs that file alone, and it can `use` packages. `kepler run .` runs all the files of a folder as one program,
  and a task of `kepler.toml` can say `file = "."`.
- `kepler test` sees a folder as a package: the examples of its files run together, and each `.test.k` sees its private names. In a
  `tests` folder and in `std/` each file stands alone, and so does a file named on the command line, except a `.test.k`.
- With `--watch`, a change in any file reloads its whole package. A new file needs a restart.
- `kepler doc geometry` and `DocNames("geometry")` see a package as one module.

## Editors

Neovim and Vim: copy `tools/editors/nvim/` into `~/.config/nvim/`.

Emacs: add `(load "/path/to/kepler/tools/editors/kepler-mode.el")` to your `init.el`.

## What's there

In every program, with no `use`:

- Functions: `Map`, `Filter`, `Reduce`, `Scan`, `Group`, `Top`, `Range`, `Count`, `FlatMap`, `Sort`, `SortBy`, `Order`, `Reverse`, `Unique`.
- Lists: `Append`, `Concat`, `Take`, `Skip`, `IndexOf`, `Flatten`, `Zip`, `Len`.
- Dictionaries: `{"a": 1}`, `d["a"]`, `d["a"] = 2`, `Get`, `GetOr`, `Has`, `Put`, `Drop`, `Keys`, `Values`, `Pairs`, `MapValues`.
- Texts: `Split`, `Join`, `Replace`, `Slice`, `Trim`, `Lower`, `Upper`, `Contains`, `StartsWith`, `EndsWith`, `Find`, `Repeat`, `Chars`, `Lines`, `PadLeft`, `PadRight`, `Number`, `Text`, and for bytes `Bytes`, `FromBytes`, `Byte`, `ByteSlice`, `ByteFind`.
- Numbers: arrays and matrices compute element by element, with `Sum`, `Mean`, `Min`, `Max`, `Matmul`, `Transpose`, `Sqrt`, `Exp`, `Log`, `Sin`, `Cos`, `BitAnd`, `BitOr`, `BitXor`.
- Results: `Ok`, `Err`, `?`, `Unwrap`, `UnwrapOr`, `MapOk`, `AndThen`. Fibers: `Spawn`, `Wait`.

With `use`:

| Module | What it gives |
|---|---|
| `sys` | files, `Stat`, `Rename`, environment, `Run`, processes in a stream with `Start`, clock |
| `net`, `http` | TCP, HTTP server and client |
| `web` | routes, `:params`, middleware, JSON, forms, cookies, static files, templates, WebSocket |
| `tls` | TLS through OpenSSL, server and client, for `http` and `web` |
| `crypto` | SHA-256, SHA-512, BLAKE2b, HMAC, encryption, public keys, signatures, Argon2, through libsodium |
| `encode` | hexadecimal, Base64, URLs, queries |
| `json`, `csv`, `regex`, `date` | parsing and writing; `regex` stays linear on any pattern |
| `set`, `queue`, `heap`, `algo` | data structures, search, graphs, permutations, Levenshtein |
| `num` | numpy-like: statistics, linear algebra, QR, eigenvalues, FFT, random numbers |
| `frame` | pandas-like: tables, `Where`, `SortBy`, `GroupBy`, `JoinOn`, CSV |
| `rope`, `history` | a large text with fast edits, and undo |
| `c` | C libraries: 60 arguments, structures by value, variadic functions, callbacks |
| `cpp` | C++: classes and functions through a generated layer, exceptions become panics |
| `sdl` | a native window: text, rectangles, keys, mouse, clipboard |

## A web server

```kepler
use web

defn hello(request)
  web.SendJson({"hello": request.Params["name"]})
end

app = web.Get("/hello/:name", hello, web.App())
Print(web.Serve(app, port = 8080))
```

```bash
kepler run --allow net=:8080 server.k
```

## C and C++

```kepler
use c

defn main()
  m = c.Open("m", version = 6)?
  cos = c.Fn("cos", ["f64"], "f64", m)?
  Print(cos(0.0))
  Ok(missing)
end

Print(main())
```

C++ has no stable binary interface, so `cpp.Wrap` generates a small C layer and compiles it once: see `std/cpp.k`.

Calling C is total trust: it ignores every permission and limit, and a wrong signature can crash the program.

## Windows and interfaces

A window is a value, and a frame an array of commands. `sdl` draws them: rounded surfaces, fine edges, soft shadows, images, icons and
curves. `ui` builds them, with pure functions: dark and light themes, rectangles that follow the window, panels, sliders, lists, code
and graphs of nodes.

```bash
kepler do material    # a material editor: drag a node, turn the light, move the sliders, press t
```

```kepler
use sdl
use ui

look = ui.Look(ui.Dark, sdl.Measure(window).Width, sdl.Measure(window).Height)
frame = Flatten([ui.Panel("Details", area, look), ui.Slider(0.5, bar, look)])
```

`Update` gets a `tick` while `moving(state)` is true, and `ui.Ease` moves a value at the same speed at any frame rate. A window with
nothing moving draws nothing. The interface font is Adwaita Sans, titles use Noto Sans Medium, and code JetBrains Mono: all three are in
`examples/fonts/`, under the SIL Open Font License.

## Documentation

Comments are `--` for a line and `(* ... *)` for several, which can hold one another. A `(** ... *)` above a definition documents it,
like `--` lines:

```kepler
(** The next number.
      Next(1) --> 2 *)
Next(x) = x + 1
```

The documentation comes from the language. A comment just above a definition documents it, and the examples in it run under
`kepler test`.

```kepler
-- The square of a number.
--
--   Square(3) --> 9
Square(x) = x * x
```

`kepler doc` lists the modules, `kepler doc num` the names of a module, and `kepler doc num.Solve` shows one, as `kepler doc
date.Date.Year` shows a method. A program, or an editor, asks the same way: `Doc("num.Solve")` or `Doc(Sort)` give the text or
`missing`, and `DocNames("num")` the names. An instance method has no value to pass, so `Doc("Rect.Area")` also finds those of the program.

## Large data

`frame` and `num` work on whole columns in OCaml. A column of integers or floats is stored without a box, and `GroupBy`,
`SortBy`, `JoinOn`, `WhereMask` and `FromCsv` are native. As with pandas, the data stays in memory.

Large work uses half of the logical cores, or the number in `KEPLER_CORES`. The results are the same to the last bit, whatever
that number.

`num.Solve`, `num.Inverse`, `num.Det`, `num.Qr` and `num.Eigen` go through LAPACK when the machine has it, and `Matmul` through
a fast BLAS such as OpenBLAS. They are found at run time, and without them the same functions work, more slowly. Install
OpenBLAS for speed.
`num.Backend()` names the library in use, and `KEPLER_BLAS` chooses one, or `none`.

## Limits

- Arrays have two dimensions at most.
- Linux on x86-64 is the verified platform. `.github/workflows/ci.yml` also runs the tests on macOS, and only builds on Windows.

## License

Kepler is under the MIT License: see `LICENSE`.

The fonts in `examples/fonts/` keep their own license, the SIL Open Font License, with its text next to them: `AdwaitaSans-OFL.txt`,
`NotoSans-OFL.txt`, and `OFL.txt` for JetBrains Mono.
