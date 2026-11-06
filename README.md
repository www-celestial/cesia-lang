# Cesia

A small interpreted language, written in OCaml. Fast, safe by default, with fibers, files, processes, HTTP and C calls.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/www-celestial/cesia-lang/main/install.sh | sh    # Linux and macOS
irm https://raw.githubusercontent.com/www-celestial/cesia-lang/main/install.ps1 | iex         # Windows, in PowerShell
cesia upgrade              # later: the newest release, after its notes and a question
cesia upgrade --nightly    # a build of main between releases, made by hand
```

A release holds the binary and every C library its libraries use, in `~/.cesia/lib/`: OpenBLAS for BLAS and LAPACK (macOS has
its own), libsodium, SDL3 and SDL3_ttf, and OpenSSL on macOS and Windows (Linux keeps the system's, for its security fixes).
Nothing else is installed by hand. In `0.x` the middle number of a version rises when a change can break a program, the last one
for a fix, and the notes of a release come from the messages of its commits.

From the sources, with OCaml 5.5 and dune:

```bash
dune build --profile release
ln -s "$PWD/_build/default/src/bin/main.exe" ~/.local/bin/cesia
ln -s "$PWD/_build/default/src/bin/main.exe" ~/.local/bin/ce      # optional: the short name of the same binary
```

Such a binary says `cesia 0.2.0+dev`: `git pull` and `dune build` update it, not `cesia upgrade`. `ce` and `cesia` are one
program, as `vi` and `vim`: `ce run file.ce` is `cesia run file.ce`.

## Write and run a program

```bash
cesia new hello       # creates hello/, with cesia.toml and src/main.ce
cd hello
cesia do run

cesia run src/main.ce           # or run any file directly
cesia run --watch src/main.ce   # reloads the code at each save
```

`examples/tour.ce` shows the language in one file. `examples/notes.ce` is a web app in 23 lines. `examples/stats.ce` works on a table.

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
cesia run --allow read=./data,net=:8080 server.ce
cesia run --limit memory=512M,steps=1000000 program.ce
```

## A project

A `cesia.toml` next to the code declares what can be run, and which C libraries are used:

```toml
[project]
name = "notes"
cesia = "0.2"     # the oldest Cesia it needs: an older one stops at once, and says to run cesia upgrade

[tasks.serve]
file = "notes.ce"
allow = ["read=notes.txt", "write=notes.txt", "net=:8080"]
```

```bash
cesia do          # lists the tasks
cesia do serve    # runs one, and shows the exact command
```

`cesia new notes` makes a project: its `cesia.toml`, `.gitignore`, `src/main.ce`, `pkg/`, which holds a copy of each library of
Cesia (`pkg/rope/rope.ce`, `pkg/ui/ui.ce`...), and `cesia.lock`, which keeps the fingerprint of each of its files. `pkg/` is read
only: `cesia pkg` says whether each library is as installed, and `cesia pkg install` makes it again, after a clone (git keeps
neither `pkg/` nor `deps/`) or a change by hand. `cesia test .` leaves `pkg/` out: `cesia test pkg/rope` runs its examples.

The code can live in more than `src/`: `src = ["src", "apps"]` under `[project]` makes `use emacs` find `apps/emacs/`. A use
looks in these folders in order, then at the root.

## Names

A name says by its first letter whether it is public, as in Go.

- A capital is public: `rope.LineCount`, `ui.Dark`, `Print`. So is a field: `date.Year`, `err.Kind`, `Ok(Value = 1)`.
- A small first letter is private, and visible only in its package: `chunk`. So is a small field of a struct: reading or writing
  one from another package stops the program, and a static method of another package, `geo.Rect.make()`, is an error at load
  time.
- Local variables, parameters and named arguments are small: `sdl.Open("t", 1, 2, f, size = 13)`. So are modules and files: `use pkg/rope`. A file name separates its words with `-`: `material-scene.ce`.
- A name has no `_`: words join by capitals, `byteLength` or `ByteLength`. The lone `_` is the wildcard of a pattern.
- A test is a private function with no parameter, `is` then a capital: `isGrows()`.
- Dictionary keys and texts are data, never private: `{"a": 1}`, `{Kind: "box"}`, `data.name`. `json.Text` writes the keys of a
  dictionary as they are, and the public fields of a struct, so that a small field, a password hash, never leaks.

## Methods

A struct holds its fields on one line, or in a block with one field per line, until `end`, which leaves room for a comment on
each. Both forms build the same values, with the same defaults, named arguments, patterns and methods.

```cesia
struct Point { X, Y = 0 }

struct Car
  (** A car on the road. *)
  Mass
  Speed = 0.0   (** metres per second *)
end
```

A struct can have methods. An instance method writes its object apart, as in Go, and a static method has the name of the struct
before its own. A dot calls both.

```cesia
struct Rect { X, Y, Width, Height }

defn Rect.Square(side)                 (* static: no object *)
  Rect(0, 0, side, side)
end

defn (r Rect) Area()                   (* instance: the object is written apart *)
  r.Width * r.Height
end

(r Rect) IsEmpty() = r.Width == 0      (* the short form *)
(r Rect) Moved(dx, dy) = Rect(r.X + dx, r.Y + dy, r.Width, r.Height)
(r Rect) center() = r.X + r.Width / 2  (* private: a small first letter *)
Rect.Unit() = Rect(0, 0, 1, 1)

r = Rect.Square(10)
Print(r.Area())
Print(r.Moved(1, 2).Area())
Print(r then it.Area())
```

- The parameters of a definition are those of the call: `defn (r Rect) Moved(dx, dy)` is called `r.Moved(1, 2)`.
- A method belongs to a `struct` of the same package. Text, arrays and dictionaries have none.
- Every struct has `User.From(d)`: an `Ok` of a `User` built from the keys of a dictionary, or an `Err` that names the key in
  excess, the field missing or the wrong type. Outside its package, a small field is no key. `Fields(u)` gives the fields back
  as a dictionary, its small ones only inside its package. A static method can't be named `From`.
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

A field or a parameter can have a type, written after its name, and a function the type of its result, after its parameters
as in Go. Code without types runs as before, and costs the same.

```cesia
struct Point { X Int, Y Int = 0 }
struct Line { From Point, To Point = Point(0) }

struct Car
  (** A car on the road. *)
  Mass Float
  Speed Float = 0.0   (** metres per second *)
  Name Text?          (** missing unless it is given *)
end

defn Describe(l Line, prefix Text = "") Text
  "$prefix$(l.From.X)"
end

(r Rect) Scaled(by Number) Rect = Rect(r.X, r.Y, r.Width * by, r.Height * by)   (* the Rect above *)
Half(x Float) Float = x / 2
```

- The types are `Int`, `Float`, `Number` (an `Int` or a `Float`), `Bool`, `Text`, `Array`, `Dict`, `Function`, the structs,
  `Point`, or `geo.Point` for one of a package the file uses, and the interfaces below. `?` also takes `missing`: `Text?`, and a
  field of such a type without a default has `missing` as its default. As a type, `Text` and `Dict` are not the functions of
  those names.
- Where: the fields of a struct, in both forms, and the parameters and the result of `defn`, of a short definition and of a
  method. After a `defn`, the type of the result ends the line: `defn (p Point) Text(p.X) end` is a function whose body is
  `Text(p.X)`. Not on a lambda: `(p Point) -> p.X` is an error, and `defn (p Point) p.X end` the way to write it.
- When: each time a value enters its place. At construction for a field, at each call for a parameter, once its default is put
  in, at each write of a typed field, also inside a path: `d.Lines[2].From = p`, and for a result at each way out of the
  function, its last expression and each `return`. An `Err` that `?` passes on leaves as it is.
- A function that ends with no value, or a `return` alone, gives `missing`: its type needs `?`, as `Int?`.
- An `Int` where a `Float` is wanted becomes a `Float`: `Car(1500).Mass` is `1500.0`, and a function of type `Float` that
  gives `2` gives `2.0`. `Number` keeps either.
- A wrong value is a bug: the program stops, `Line: From must be a Point, found an Int.`, at the call or the write, and
  `Half: the result must be a Float, found a Text.` at the way out. A type that names nothing, `Pont`, is an error before the
  program starts.
- Under `--watch`, a changed type applies at the next call, construction or write; values made before are not checked again.
- When two structs have one name, the message names their packages: `r must be a geo.Rect, found a shapes.Rect.`

## Interfaces

An interface lists methods, with no code. A value meets it when it has each of them with that number of parameters, written
apart from the object: nothing declares it, as in Go.

```cesia
interface Shape
  (** Something with an area and a perimeter. *)
  Area()
  Perimeter()
end

interface Named { Name() }

(r Rect) Perimeter() = 2 * (r.Width + r.Height)   (* the Rect above, which has its Area() *)

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
  parameters may have types, `Scaled(by Number)`, and only their number counts to meet the interface. Its result may have one,
  `Area() Number`, which documents it: no result is known before a call.
- A struct meets an interface through its methods, or through fields that hold functions; a dictionary through keys that hold
  functions. The answer is kept for each shape of value, and forgotten when a file reloads.
- An interface is a type: `s Shape`, `Inner Shape?`, `s geo.Shape`. A value that doesn't meet it stops the program, and the
  message names what it lacks: `Measured: s must be a Shape, found a Circle, which has no Perimeter().`
- A method on an interface, `(s Shape) Describe()`, is a method of every value that meets it, dictionaries too. A field or a method
  of the value itself wins over it. A call looks at the interfaces of its package and of the packages its file uses; when two of
  them give the method to a value that meets both, the call stops and names them.
- A small interface or method is private to its package, as any name, and a public interface needs a comment.
- Not there: an interface made of others, `match` on an interface, types with parameters.

## Packages

A package is a folder, as in Go: there is no import by file, and no `package` line.

```
myproject/
  cesia.toml
  src/
    main.ce
    geometry/
      rect.ce
      circle.ce
      shapes/
        square.ce
  tests/
```

```cesia
(* src/main.ce *)
use geometry
use geometry/shapes

r = geometry.Rect(2, 3)
Print(r.Area(), shapes.Square(2))
```

- The code of a project goes in `src/`. A `use` is absolute: it looks in each source folder of the root of the project, in order,
  then at the root itself, so `use geometry` finds `src/geometry/` from any file, and `use tests/helpers` a folder out of `src/`.
  The first that holds it wins. The root is the folder of the nearest `cesia.toml` above the program or, without one, the folder of
  the file that runs. A `use` takes no `./`, no `../` and no quotes.
- The name in the code is the last part of the path: `use geometry/shapes` gives `shapes.Square`, and `as` renames it. Two uses of
  a file can't give one name.
- A package is all the `.ce` files of its folder, in the order of their names. Its subfolders are other packages, and its `.test.ce`
  files aren't part of it.
- The files of a package need no `use` to see each other, and share their small names, fields and methods. Each file keeps its own
  `use`. Two files of a package can't define one name, but the variable of a loop stays in its file.
- A library is written with `pkg/`: `use pkg/rope` takes `pkg/rope/` of the project when it is there, or else the one Cesia holds,
  and the name in the code is `rope`. `use rope` alone is an error. The modules written in OCaml have no `pkg/`: `use sys`,
  `use json`, `use net`, `use c`, `use regex`, `use columns`, `use debug`, `use lapack`; a folder of the project can't have their names.
- `cesia run file.ce` runs that file alone, and it can `use` packages. `cesia run .` runs all the files of a folder as one program,
  and a task of `cesia.toml` can say `file = "."`.
- `cesia test` sees a folder as a package: the examples of its files run together, and each `.test.ce` sees its private names. In a
  `tests` folder and in `std/` each file stands alone, and so does a file named on the command line, except a `.test.ce`.
- With `--watch`, a change in any file reloads its whole package. A new file needs a restart.
- `cesia doc geometry` and `DocNames("geometry")` see a package as one module.

### Packages of other projects

Any project with a `cesia.toml` gives its packages: there is no app or library, and no registry. A `[deps]` table names the
repository, a tag, and the packages taken:

```toml
[deps.cemacs]
from = "github.com/www-celestial/cemacs"
version = "v0.3.0"
take = ["folders"]
```

```cesia
use deps/www-celestial/cemacs/folders    (* the name in the code: folders *)
```

- The path says where it comes from: the owner and the name of the repository, after its host unless it is `github.com`, as in
  `use deps/gitlab.com/x/y/z`. Inside `deps/www-celestial/cemacs/`, a use of its own code reads its root and its source folders,
  so it runs unchanged; `pkg/` and `deps/` are those of the project that runs.
- Cesia follows the uses of what is taken, to the end: their own code comes with them, never their tests or other folders, and
  a `use deps/...` of theirs brings that project at the version they ask for. One version per repository, the highest asked for.
  Without `take`, every package of its source folders comes.
- `deps/` is read only, as `pkg/`: `cesia.lock` keeps the commit of each tag and the fingerprint of each file, and the loader
  checks each file it reads from them, once. A tag moved since the lock stops `cesia pkg install`. To change someone's package,
  fork it, then `cesia pkg move`.
- git fetches each tag once, into `~/.cache/cesia/`: another install, or another project, needs no network. `cesia run`, `cesia do`
  and `cesia test` never use it.

| Command | What it does |
|---|---|
| `cesia pkg` | each package, its version, and whether it is as installed |
| `cesia pkg add github.com/x/y@v1.2.0 folders` | writes the `[deps.y]` table, then installs |
| `cesia pkg install` | makes `pkg/` and `deps/` what `cesia.toml` and `cesia.lock` say: after a clone, or to undo a change by hand |
| `cesia pkg update [label] [--to v1.3.0]` | to the newest tag, or that one, and `pkg/` to this Cesia |
| `cesia pkg move www-celestial/cemacs someone/cemacs-fork` | takes a fork instead, and rewrites the uses of the project |
| `cesia pkg --check` | the newer tags, through the network |

## Editors

Neovim and Vim: copy `tools/editors/nvim/` into `~/.config/nvim/`.

Emacs: add `(load "/path/to/cesia/tools/editors/cesia-mode.el")` to your `init.el`.

## What's there

In every program, with no `use`:

- Functions: `Map`, `Filter`, `Reduce`, `Scan`, `Group`, `Top`, `Range`, `Count`, `FlatMap`, `Sort`, `SortBy`, `Order`, `Reverse`, `Unique`.
- Lists: `Append`, `Concat`, `Take`, `Skip`, `IndexOf`, `Flatten`, `Zip`, `Len`.
- Dictionaries: `{Name: "Ana"}` is `{"Name": "Ana"}`, `d.Name` is `d["Name"]`, `d.City = "Lyon"`, `Get`, `GetOr`, `Has`, `Put`,
  `Drop`, `Keys`, `Values`, `Pairs`, `MapValues`, `Merge`. Keys keep the order of insertion; `==` ignores it. Keys written in the
  code make a dictionary as fast as a struct; keys from data, a balanced tree that no choice of keys slows down.
- Texts: `Split`, `Join`, `Replace`, `Slice`, `Trim`, `Lower`, `Upper`, `Contains`, `StartsWith`, `EndsWith`, `Find`, `Repeat`, `Chars`, `Lines`, `PadLeft`, `PadRight`, `Number`, `Text`, and for bytes `Bytes`, `FromBytes`, `Byte`, `ByteSlice`, `ByteFind`.
- Numbers: arrays and matrices compute element by element, with `Sum`, `Mean`, `Min`, `Max`, `Matmul`, `Transpose`, `Sqrt`, `Exp`, `Log`, `Sin`, `Cos`, `BitAnd`, `BitOr`, `BitXor`.
- Results: `Ok`, `Err`, `?`, `Unwrap`, `UnwrapOr`, `MapOk`, `AndThen`. Fibers: `Spawn`, `Wait`, and channels between them:
  `Channel`, `Send`, `Receive` with a timeout.

With `use`:

| Module | What it gives |
|---|---|
| `sys` | files, `Stat`, `Rename`, environment, `Run`, processes in a stream with `Start`, clock |
| `net`, `http` | TCP, HTTP server and client |
| `web` | routes, `:params`, middleware, JSON, forms, cookies, static files, templates, WebSocket |
| `tls` | TLS through OpenSSL, server and client, for `http` and `web` |
| `crypto` | SHA-256, SHA-512, BLAKE2b, HMAC, encryption, public keys, signatures, Argon2, through libsodium |
| `encode` | hexadecimal, Base64, URLs, queries |
| `sql` | databases: a pool, rows as maps, typed rows, transactions, streams; SQLite through its library |
| `json`, `csv`, `regex`, `date` | parsing and writing; `regex` stays linear on any pattern |
| `set`, `queue`, `heap`, `algo` | data structures, search, graphs, permutations, Levenshtein |
| `num` | numpy-like: statistics, linear algebra, QR, eigenvalues, FFT, random numbers |
| `frame` | pandas-like: tables, `Where`, `SortBy`, `GroupBy`, `JoinOn`, CSV |
| `rope`, `history` | a large text with fast edits, and undo |
| `c` | C libraries: 60 arguments, structures by value, variadic functions, callbacks |
| `cpp` | C++: classes and functions through a generated layer, exceptions become panics |
| `sdl` | a native window: text, rectangles, keys, mouse, clipboard |

## A web server

```cesia
use pkg/web

defn hello(request)
  web.SendJson({"hello": request.Params["name"]})
end

app = web.Get("/hello/:name", hello, web.App())
Print(web.Serve(app, port = 8080))
```

```bash
cesia run --allow net=:8080 server.ce
```

## Databases

`pkg/sql` talks to SQLite through its library, `libsqlite3`, which Linux and macOS have and a release of Cesia brings.

```cesia
use pkg/sql

struct Todo { Id Int, Title Text, Done Bool, CreatedAt Text }

defn main()
  db = sql.Open("sqlite:data/todo.db")?
  sql.Script("create table if not exists todos (id integer primary key, title text not null, done boolean not null default false, created_at text default current_timestamp)", db)?
  added = sql.Exec("insert into todos (title) values (?)", ["Buy bread"], db)?
  first = sql.One("select * from todos where id = ?", [added.LastId], db)?   (* a map, or missing *)
  Print(first.Title, first.CreatedAt)                                        (* created_at is read CreatedAt *)
  todos = sql.Query("select * from todos where not done", [], db, as = Todo.From)?
  sql.Transaction(tx -> sql.Exec("update todos set done = true where id = ?", [todos[1].Id], tx), db)?
  sql.Each(t -> Print(t.Title), "select title from todos order by id", [], db)?   (* any size, a batch in memory *)
  Ok(missing)
end

Print(main())
```

```toml
[project]
name = "todo"

[tasks.run]
file = "todo.ce"
allow = ["read=data", "write=data"]   # SQLite's -wal and -shm files sit beside the database
```

- `Exec` gives `{Changed, LastId}`; `Query` every row; `One` the first or missing; `Each` streams; `Table` gives columns,
  `{Names, Columns}`, as `pkg/frame` holds them; `Script` runs a schema; `Transaction` commits an Ok, rolls back an Err or a
  panic, and nests as savepoints. `as = User.From` types each row; the first Err says its `Row`.
- Values: missing is NULL, a Bool 1 or 0, Int, Float and Text as they are, a `date.Date` its text, a list or a map its JSON.
  Back: NULL is missing, a BLOB a Text of its bytes, a column declared `boolean` a Bool. Dates stay texts: `date.Parse` reads
  them.
- Values only go through `?`, never into the text: `"... where name = '$name'"` is an injection. One statement per call, so
  `"1; drop table users"` is an Err; a table or column chosen at run time comes from a fixed map in the program:
  `{Newest: "created_at desc", Title: "title"}[choice]`. SQLite opens without URIs, extensions or attached databases, so
  `attach`, `vacuum`, `load_extension` and the pragmas `temp_store_directory` and `data_store_directory` are refused, and
  its files need the `read` and `write` permissions of their folder, never `ffi`.
- Errors are `Err({Kind: "sql", Code, Message})`: SQLSTATE codes where SQL has one (`23505` unique, `23503` foreign key,
  `23502` not null, `23514` check, `22003` an integer past 63 bits, `07001` the count of `?`), else `sqlite-N`, or `url`,
  `library`, `pool`, `closed`, `done`, `statements`, `params`, `names`. A message never holds a parameter.
- A pool of `max = 8` connections; a call waits `wait = 5` seconds for one, and a busy database is waited for in the fiber, so
  the others run. `sqlite::memory:` keeps one connection. Calls into SQLite run on the main thread: right for short queries.
- `pkg/sql` is the one way to SQLite: `c.Open` refuses its library.

## C and C++

```cesia
use c

defn main()
  m = c.Open("m", version = 6)?
  cos = c.Fn("cos", ["f64"], "f64", m)?
  Print(cos(0.0))
  Ok(missing)
end

Print(main())
```

C++ has no stable binary interface, so `cpp.Wrap` generates a small C layer and compiles it once: see `std/cpp.ce`.

Calling C is total trust: it ignores every permission and limit, and a wrong signature can crash the program.

## Windows and interfaces

A window is a value, and a frame an array of commands. `sdl` draws them: rounded surfaces, fine edges, soft shadows, images, icons and
curves. `ui` builds them, with pure functions: dark and light themes, rectangles that follow the window, panels, sliders, lists, code
and graphs of nodes.

```bash
cesia do material    # a material editor: drag a node, turn the light, move the sliders, press t
```

```cesia
use pkg/sdl
use pkg/ui

look = ui.Look(ui.Dark, sdl.Measure(window).Width, sdl.Measure(window).Height)
frame = Flatten([ui.Panel("Details", area, look), ui.Slider(0.5, bar, look)])
```

`Update` gets a `tick` while `moving(state)` is true, and `ui.Ease` moves a value at the same speed at any frame rate. A window with
nothing moving draws nothing. The interface font is Adwaita Sans, titles use Noto Sans Medium, and code JetBrains Mono: all three are in
`examples/fonts/`, under the SIL Open Font License.

## Comments and documentation

`(* ... *)` is a note, on one line or several, and can hold another one. `(** ... *)` documents what it belongs to. `--` is no
comment: written outside a text, it is an error that says how comments are written.

A block, `defn … end` or the block form of `struct` and `interface`, has its documentation first in its body. A one-line
definition has it at the end of its line when one sentence is enough, else just above it. The first `(** *)` of a file, before any
code, says what the module is for. The examples, indented under the text with `-->`, run under `cesia test`.

```cesia
defn Scaled(r Rect, by Number) Rect
  (** A rectangle larger by some factor.

        Scaled(Rect(1, 2), 2) --> Rect(2, 4) *)
  Rect(r.Width * by, r.Height * by)
end

struct Rect
  (** A rectangle, in metres. *)
  Width Number    (** along x *)
  Height Number   (** along y *)
end

Square(x Number) Number = x * x   (** The square of a number. *)

(** The cube of a number.

      Cube(2) --> 8 *)
Cube(x Number) Number = x * x * x
```

A `(** *)` at the end of the line of a field, of a parameter, or of the `)` that closes the parameters, documents that one, and
`cesia doc` lists them after the text, with `result` for the `)`:

```cesia
defn Grown(
  r Number,    (** the number to grow *)
  by Number    (** how many times larger *)
) Number       (** the larger number *)
  (** A number larger by some factor. *)
  r * by
end
```

`cesia doc` lists the modules, `cesia doc pkg/num` the names of a module (from the project's copy when there is one), and
`cesia doc num.Solve` shows one, written as in the code, as `cesia doc date.Date.Year` shows a method. A program, or an editor, asks the same way: `Doc("num.Solve")` or `Doc(Sort)` give the text or
`missing`, and `DocNames("num")` the names. An instance method has no value to pass, so `Doc("Rect.Area")` also finds those of the program.
A function written in OCaml, as `Sort` or `json.Parse`, has its text in the binary, and `cesia doc` ends it with `Built into
Cesia.`: no source of Cesia is needed to read it.

## Large data

`frame` and `num` work on whole columns in OCaml. A column of integers or floats is stored without a box, and `GroupBy`,
`SortBy`, `JoinOn`, `WhereMask` and `FromCsv` are native. As with pandas, the data stays in memory.

Large work uses half of the logical cores, or the number in `CESIA_CORES`. The results are the same to the last bit, whatever
that number.

`num.Solve`, `num.Inverse`, `num.Det`, `num.Qr` and `num.Eigen` go through LAPACK when the machine has it, and `Matmul` through
a fast BLAS such as OpenBLAS. They are found at run time, and without them the same functions work, more slowly. Install
OpenBLAS for speed.
`num.Backend()` names the library in use, and `CESIA_BLAS` chooses one, or `none`.

## Limits

- Arrays have two dimensions at most.
- Linux on x86-64 is the verified platform. `.github/workflows/ci.yml` also runs the tests on macOS, and only builds on Windows.

## License

Cesia is under the MIT License: see `LICENSE`.

The fonts in `examples/fonts/` keep their own license, the SIL Open Font License, with its text next to them: `AdwaitaSans-OFL.txt`,
`NotoSans-OFL.txt`, and `OFL.txt` for JetBrains Mono.
