# Changelog

## 1.0.0

Cesia is a small language for solving real problems directly: a script that cleans a CSV, a web server on a database, a
program that drives other programs. It starts at once, it runs a program safely by default, and when something goes wrong
it says what to write. One binary holds the language, its tools and its libraries, on Linux, macOS and Windows.

From 1.0 on, the first number of a version rises when a change can break a program, the middle one when something is
added, and the last one for a fix. A program written for 1.0 runs on every 1.x.

### What is in it

- The language: numbers, texts, lists and matrices that compute as a whole, dictionaries, structs with methods, interfaces,
  `match` on shapes, functions as values, `it` and `then` for short steps, comprehensions, and optional types that check
  what comes in. Errors are values, `result.Ok` and `result.Err`, passed on with `?`; bugs stop the program with their
  line and what to write instead. Every short form has its plain function beside it: `a..b` is `list.Range(a, b)`.
- Safety: a program touches nothing outside itself until its command line allows it, with `--allow` for files, the
  network, other programs, the environment and C libraries, each as narrow as a folder or a port; `--limit` caps its
  memory, its steps and its depth.
- Speed: an interpreter that specializes functions by the types it sees, and a JIT that turns hot code into native code.
  The JIT, SQLite, the debugger and the test engine are plugins loaded at their first use, so a program starts in about
  2.5 ms.
- The tools: `cesia run` (with `--watch` to reload at each save, `--repl`, `--debugger`, `--seed`), `cesia test`,
  `cesia check`, `cesia do` for the tasks of `cesia.toml`, `cesia new`, `cesia pkg` for dependencies from git with a lock
  file, `cesia doc` and `cesia doc --site`, `cesia upgrade`.
- The libraries, in `std/`: lists, texts, dictionaries, math, matrices and numerical work, tables of columns, JSON, CSV,
  regular expressions, dates, paths, flags, random numbers, files and processes, fibers and channels, HTTP and web
  applications, WebSocket, TLS, cryptography, SQLite, Markdown, and C and C++ libraries through `std/c` and `std/cpp`.
- The book, which teaches Cesia from the start to a real program, and the reference of every name, both on one site whose
  examples run at each build.

### New since 0.2

- `cesia run --repl`: a prompt beside the running program, in its main file's package; a function defined again replaces
  the program's own. A debugger in Cesia: conditional breakpoints, a stop on each error with every variable, any
  expression in a frame, frames up and down, watches, and fix and continue. Both work with the JIT.
- `cesia check` reads a project without running it: names, arguments, types, and results whose `Err` would go unseen.
  `Int!` says that a function gives an `Int` or an `Err`, and `_ =` drops a result on purpose.
- Tests: a failure shows the value of each part it compared; `math.Near`; properties with `test.ForAll` and the
  generators of `std/gen`, which shrink a failure to the smallest case; `test.Snapshot`; `test.Temp`; tests in parallel
  workers, each with a deadline and its own listeners.
- `std/random` with `--seed`, `std/path`, `std/flags`, `sys.Walk`, `date.Local` and offsets, `text.Decimals`,
  `io.PrintError`, `sys.ReadInput` and `sys.Exit`.
- The JIT: hot functions and loops become machine code, numbers, arrays, maps and structs included, with the same
  results as the interpreter. It runs on x86-64; on arm64 it is off for now, and programs run interpreted.
- Arrays of three dimensions and more: `matrix.Zeros(2, 3, 4)`, `a[i, j, k]`, `value.Size`, `matrix.Reshape([2, 3, 4], xs)`,
  sums and means along a dimension with `list.Sum(a, dim = 3)`, and arithmetic element by element, natively in the JIT.
- `std/sql` on SQLite, with a pool, typed rows and transactions; channels between fibers; one storage for every map;
  `From` and `Fields` between structs and dictionaries.
- Every error shows in one form, its place and then its message, at the prompt and in the debugger too.
- Releases with their C libraries beside the binary, `install.sh`, `install.ps1` and `cesia upgrade`.

### Breaking changes since 0.2, and what to write

- No name is global. Each file uses the packages of `std/` it needs: `use std/io`, then `io.Print(x)`; `list.Map`,
  `text.Split`, `result.Ok`, also in patterns: `result.Ok(v) -> v`. A name written alone says which use it needs.
- A variable, parameter, function or pattern named as a package the file uses is refused: with `use std/text`, name a
  text `s` or `line`, not `text`.
- A range is written `a..b`, short for `list.Range(a, b)`; `a:b` stops with a message that says so.
- A use says where its code comes from: `use std/csv` for what comes with Cesia, `use src/shapes` for a folder of the
  project, from its root, and `use deps/OWNER/REPO/...` for a dependency. The folder `pkg/` is now `std/`: run
  `cesia pkg install`.
- `--allow net=:8080` listens on this machine only, 127.0.0.1 and ::1. To take connections from other machines, write
  the address too: `net=0.0.0.0:8080`. A test gets `net=own`: its own listeners only.
- `std/sdl`, `std/ui`, `std/rope` and `std/history` left Cesia, for the editor that uses them, and releases no longer
  hold SDL3: a program that opens it gets it from the system.
- A quote inside a text is written `\"` only: two quotes in a row are an error that says what to write.
- The inner parts of `std/http` and `std/websocket` are private. `net.Size`, `net.Find` and `net.SplitAt` are gone:
  `text.ByteLength`, `text.ByteFind` and `text.ByteSlice` do the same. The names renamed or removed before 1.0 are listed
  below.
- `sql.Open` on a file needs read and write for the files SQLite keeps beside it, `-wal`, `-shm` and `-journal`, as for
  the database itself: grant its folder, as `--allow read=data,write=data`.
- A struct of one field shows its value alone, as the code builds it: `Ok(42)`, `Err("no")`, no longer
  `Ok(Value = 42)`. A struct of more fields still shows their names. At the `--repl` prompt, a text shows with its quotes,
  `"HELLO"`, as `-->` writes it.

### Renamed and removed before 1.0, old -> new

One way for each thing: none of the old names stays beside the new one, and a program that uses one stops at its load
with the usual message.

- std/web is merged into std/http; http.Get, http.Post and http.Request become http.Fetch:
  - `use std/web` -> `use std/http`, and `web.X` -> `http.X` for `App`, `Route`, `Get`, `Post`, `Delete`, `AnyMethod`,
    `Wrap`, `Plain`, `Html`, `Redirect`, `NotFound`, `WithHeader`, `SetCookie`, `Form`, `BodyJson`, `Handler`,
    `Websocket`, `Logger`, `Cors`, `FileResponse`, `Static`, `Escape`, `Template`
  - `web.PutRoute` -> `http.Put`; `web.SendJson` -> `http.Json`; `web.Serve(app)` -> `http.Serve(app)`
  - `http.Get(url)` -> `http.Fetch(url)`; `http.Post(url, body)` -> `http.Fetch(url, method = "POST", body = body)`;
    `http.Request(method, url)` -> `http.Fetch(url, method = method)`
  - `http.Serve(handler)` -> `http.Serve(app)`: a bare handler becomes `http.App() then http.AnyMethod("*", handler)`
  - `web.GetHeader` -> `http.HeaderValue`
  - `websocket.Accept(headers, onMessage)` -> `websocket.Accept(key, onMessage)`, the key of the request;
    `http.Websocket` checks the request and calls it
- Private now, with no public name: `http.Blank`, `http.Crlf`, `http.MaxHead`, `http.Render`, `http.ReadResponse`,
  `http.ParseResponse`, `http.WaitForConnections`, `http.Plain` (the wrap without TLS: `wrap` left out of `http.Serve`
  means plain TCP); `net.Arm`, `net.Reap`, `net.OpenCount`, `net.IsHeader` (inside std/http); `debug.Words` (inside
  the debugger); `date.DaysFromCivil`; `text.XorBytes` (inside std/websocket). The connection a `wrap` gives has
  `Read`, `Write` and `Close`: std/http sets the deadlines itself.
- Arguments, the function or the sizes first and the data last:
  - `matrix.Reshape(xs, rows, cols)` -> `matrix.Reshape([rows, cols], xs)`, the shape as a list of sizes
  - `algo.Bfs(start, neighbors)` -> `algo.Bfs(neighbors, start)`; `algo.Dfs` the same
  - `algo.Dijkstra(start, edges)` -> `algo.Dijkstra(edges, start)`
  - `algo.TopologicalSort(nodes, needs)` -> `algo.TopologicalSort(needs, nodes)`
- A question starts with Is or Has: `set.Member` -> `set.Has`; `set.Subset` -> `set.IsSubset`; `cesia.Dev` ->
  `cesia.IsDev`; `debug.Complete` -> `debug.IsComplete`; `crypto.Same` -> `crypto.IsSame`
- Removed, with what does the same:
  - `list.Every(f, xs)` -> `list.All([f(x) for x in xs])`; `list.Some(f, xs)` -> `list.Any([f(x) for x in xs])`
  - `list.Butlast(xs)` -> `list.DropLast(1, xs)`; `list.Rest(xs)` -> `list.Skip(1, xs)`
  - `fn.Pipe(x, f, g)` -> `x then f() then g()`; `fn.Partial(f, a)` -> `x -> f(a, x)`, or `f(a, it)` in an
    argument, as `list.Map(math.Add(2, it), xs)`
  - `set.Count(s)` and `queue.Count(q)` -> `value.Len(s)` and `value.Len(q)`
  - `num.SumCols(m)` -> `list.Sum(m, dim = 1)`; `num.SumRows(m)` -> `list.Sum(m, dim = 2)`: the same lists
  - `num.Seeded(seed)` -> `cesia run --seed N`: `num.Uniform(n)` and `num.Normal(n)` take no generator and give a
    list, drawn by std/random as `random.Float` is
- Renamed: `csv.Write` -> `csv.Text`; `frame.Rows` -> `frame.RowCount`; `fn.Comp` -> `fn.Compose`; `syntax.String` ->
  `syntax.Text`
