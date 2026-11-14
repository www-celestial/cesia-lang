# Changelog

## 1.2.0

Everything here is added, but for two exit codes of `cesia do` (Changed, just below): a program written for 1.1 runs
as it did.

### Changed

- On Linux and macOS, the last task of `cesia do` takes its place, in the same process (`exec`): systemd sees the
  program itself, stops it with one TERM, and gets its own exit code, as from `cesia run`. Two exit codes change: a last
  task killed by a signal gives the shell's 128 and its number, 143 for TERM, instead of 1; a last task that a TERM
  stops cleanly, as a server does, gives its own code, 0, instead of 1. Windows keeps the last task as a child.

### Language

- A do block after the `)` of a call, `list.Reduce(0, xs) do total, x` up to `end`: the function `defn (total, x) ... end`,
  the same tree, in the place of the argument that is `_` alone, or else first, as in Julia. `do` stays a plain name
  elsewhere, and the function written inside the parentheses stays valid. `cesia fmt` and the modes for Emacs and Neovim
  know it.
- `text.Fold(s)`, Unicode 18.0's simple case folding, to search and compare what people write:
  `text.Fold("ÉLODIE") == text.Fold("Élodie")`. `text.Lower` and `text.Upper` stay ASCII, for the texts of protocols.
- `value.Text(x, most)`: the text of a value, cut at `most` characters, its first `most - 1` and an ellipsis; only that
  start is made, so a preview of a list of 10^6 numbers or of a long text costs what its `most` characters cost.
- `path.Abs(p)`, the absolute path of a path from the current folder, its `.` and `..` taken away as text; it needs the
  read permission on the path.
- `sys.Mkdir` and `sys.Write` take `private = true`: a folder 0700 and a file 0600, their owner's alone from their
  creation on, or made so if they were there; a private `sys.Write` writes a new file and renames it over the path, so
  that a reader of the old file never gets the text, and a link there is replaced, its target untouched.

### Servers

- `std/websocket` is a client too: `websocket.Dial(url)` gives a connection whose messages come on the channel
  `c.Messages`, with `websocket.Send`, `websocket.Close` and `websocket.DefaultMaxMessage`; tested against
  Autobahn|Testsuite in the CI. `websocket.Dial(url, headers = ...)` sends a cookie or an Origin, and refuses before any
  connection a name that isn't a token or that the handshake writes itself, and a line end or a zero byte in a value.
- `std/live`, live screens: `live.Route(path, screen, actions = {...})` serves pages whose shows change by themselves,
  pushed over a WebSocket, and their actions, drawn at once by `live.js` and confirmed or undone by the app's reply;
  `live.Show(name, changes)`.
- `http.Stream(produce)`, a response whose body goes out in chunks as it is made, each piece within the timeout or the
  connection ends; a panic or an `Err` cuts it short, and HEAD runs nothing.
- `http.SameOrigin`, a middleware against cross-site request forgery, by `Sec-Fetch-Site` then `Origin` and `Host`, as
  Go's CrossOriginProtection; std/live uses it for its screens.
- `net.Peer` gives the address of the other end of a connection, and std/http puts it in each request as `Peer`, to
  limit a client by; a handler gets the request as a middleware left it, with the keys it put there, as the person
  signed in.

### Tools

- `std/cells`: a notebook in a `.ce` file, cut by `(* %% Title *)` comments. `cells.Parse`, `cells.Analyse` (what each
  cell defines and reads, a name in one cell only, read only below its cell) and `cells.ToRun` (the cells that depend on a
  run); `cells.Session`, `cells.Run`, `cells.Forget`, `cells.Variables`, `cells.Rows`, `cells.Scene` and `cells.Stop` run them in a process of their
  own, `cesia run --cells`, as fast as `cesia run`, a graph of `std/plot` as its scene; `cells.Html` gives the page of a
  file, its graphs in SVG. Each cell starts std/random again from the session's seed and its title, so a cell run again
  draws the same numbers; a struct of at most 20 fields shows as a table of its fields, an `Ok` of a struct as the
  struct.
- `std/plot`, graphs as values: `plot.Line`, `Points`, `Bars`, `Histogram`, `Heatmap`, `Density` and `Area`, on shared
  axes with `plot.Of` and side by side with `plot.Grid`, drawn to SVG by `plot.Svg` and `plot.Save`, and to a scene of
  shapes in pixels by `plot.Scene`; the ticks by the extended Wilkinson algorithm, long lines by M4, the colors of Okabe
  and Ito and viridis. A line of 10^6 points in 37 ms.
- `c.Write(type, offset, values, block)` writes a whole array of numbers into a block in one call, each converted as
  `c.Set` converts one: the vertices of a shape or the pixels of an image.
- `c.Fn(..., slow = true)` runs each call on a domain of its own, the runtime released while its fiber waits, at most
  one per core at once; `crypto.HashPassword` and `crypto.CheckPassword` use it, so a sign-in no longer stops every
  fiber for 70 ms.
- `cesia.Reads(source)`: the names a source reads and doesn't define, with the compiler's own resolver.
  `cesia.Definitions` gives the names of `[q, r] = ...` too.
- `cesia do TASK ARGS...` passes the words after the task to its own program, as its `sys.Args`, never through a shell;
  a task with no program of its own refuses them.
- `[test] skip` in `cesia.toml` names the folders and files that `cesia test` leaves out unless its path is in one of
  them, as end-to-end tests that need a server started first.
- A `[deps]` version may be the whole hash of a commit, for a project that has no tag yet: `cesia pkg` fetches that
  commit alone and checks it.
- `cesia test` stops the programs a test started with `sys.Start` or `sys.Run` when the test ends, even past its time.
- `cesia test` of a folder starts its largest files first, so that a long one doesn't start last and keep the others
  waiting; the reports still come in the order of the files. Cesia's tests/lang, 89 files on 8 threads: 2.44 -> 1.85 s.
- `cesia doc --site` writes formulas in MathML, GitHub's alerts and heading ids, the colors of `[site] color` at AA
  contrast and the README as a page, checks the `norun` blocks that follow one another as one program, and builds the
  French site of `docs/fr/`, whose pages must keep the headings, code and links of the English ones; Cesia's book is in
  French too. `std/markdown` writes GitHub's alerts, and the formulas of `$...$` and `$$...$$`.
- Tabs in the docs: a `python`, `r` or `matlab` block right after a `cesia` block shows as a tab beside it,
  Cesia | Python | R | MATLAB, with no script; `tools/tabs.ce` runs each tab of Cesia's book, capped and with no
  network, and checks that it prints what its cesia block shows.
- For those who work on Cesia: `tools/test.sh` runs the typed path and the OCaml tests only, the change loop, 11 ->
  4.4 s; `tools/test.sh --no-spec` runs the same tests on the other path, and `tools/test.sh --slow` the tests slow by
  nature, on both paths; `tools/check.sh` runs those two after the loop, and the CI the first two.
- The nightly pre-release is made again from main each time the CI passes there, from the commit it tested, so that
  projects that build against main test with it.

### Numerical methods

- `std/optimize`: `optimize.Root`, the zero of a function by Brent's method, from a bracket or one start, to the last
  float by default, tested on the 154 problems of Alefeld, Potra and Shi; `optimize.Minimize`, by L-BFGS with the line
  search of Moré and Thuente, and `optimize.Simplex`, by Nelder and Mead with the coefficients of Gao and Han, both
  tested on the 35 problems of Moré, Garbow and Hillstrom. An `Err` with the best point where there is no zero or no minimum.
- `std/ode`: `ode.Solve`, the method of Dormand and Prince with its dense output, a PI control of the step, events
  located by `optimize.Root`, and an alarm when the problem is stiff; `stiff = true` runs Rodas5P, a Rosenbrock method
  of order 5, with the Jacobian given by `jacobian =` or by differences. An `Err` with the solution so far at a blow-up,
  a NaN or past its steps. Lorenz on [0, 100] at `rtol = 1e-8` in 127 ms, against 681 for scipy and 8,827 for Octave.
- `std/quad`: `quad.Integral(f, a, b)`, QUADPACK's QAGS, QAGP at the `points` given and QAGI for an infinite bound,
  with Wynn's epsilon algorithm, in a native engine that calls `f` back: the same value and error estimate as scipy's
  `quad`, to the last bit, on 42 integrals, in 46.7 us against scipy's 82.3. `math.Inf`, the infinity.
- `std/sparse`: matrices in compressed columns, `sparse.Of` from triplets with every index checked, `Eye`, `Diags`,
  `Kron`, `Add`, `Scale`, `Transpose`, `Dense`, `Get` and `Mul`; `sparse.Solve`, as MATLAB's backslash, orders by
  approximate minimum degree, then factors by supernodes, multifrontal, Cholesky or LU on dense fronts through BLAS,
  with one step of refinement; `sparse.Read` reads Matrix Market files, every line checked. Poisson on 300 x 300 points
  in 315 ms (scipy 805, Octave 330), on 1000 x 1000 in 3.85 s (scipy 33.7, Octave 8.1).
- `num.Lu` factors a square matrix once, for many solves with its `Solve`; `num.Solve`, `Inverse` and `Det` go through
  the same native elimination, with the same bits as before: an `Lu` of order 100 in 0.65 ms instead of 3.6.

### Statistics

- `std/stats`: the laws Normal, StudentT, ChiSquared, FisherF, Uniform, Exponential, Gamma, Beta, Binomial and Poisson
  as values, each with `Pdf`, `Cdf`, `Quantile` (both with `upper = true` for the upper tail, computed directly) and
  `Sample`; `stats.Lm`, the linear model of R's `lm` without a formula, with `summary(lm)`'s table, `Predict`, `Band` and
  `Confint`; the tests `TTest`, `TTest2`, `WilcoxonTest`, `WilcoxonTest2`, `KsTest`, `ChiSquaredTest` and `CorTest`, each
  giving a `stats.Test`. Checked against values of 70 digits, NIST's datasets and R.
- `stats.MonteCarlo(f, n = ...)` or `(f, tol = ...)`: the mean of random draws, single or in batches, with its
  standard error and Student's interval, as a `stats.Estimate`; with `tol`, it draws until the interval is narrow
  enough, by the rule of Chow and Robbins. Its coverage is checked on 1,000 runs of each law.
- `std/special`: `Gamma`, `LogGamma`, `Beta`, `LogBeta`, `Erf`, `Erfc`, `Erfcx`, `ErfInv`, `ErfcInv`, `GammaInc` and
  `BetaInc`, from the papers of Cody, Wichura, DiDonato and Morris, and Temme.
- `num.Variance`, `num.Std` and `num.Covariance` take `sample = true`, which divides by n - 1 as R's `var`, `sd` and
  `cov`; the default stays numpy's n.

### Speed

Measured on the same machine as the others, in the book's chapters on speed and numerical methods:

- The cache of loaded packages: a package unchanged since the last run is neither lexed, parsed nor resolved again,
  its entry written once the run has ended, checked by its BLAKE2b digest, in a folder of the person's alone:
  `use std/plot` starts in 5.69 ms instead of 9.66, Cemacs reaches its first frame in 36.97 ms instead of 52.16. A
  function's body is read from the cache at its first call: 4.03 and 50.62 ms. An entry places a used package's modules
  from its end, so two programs run in turn no longer resolve a package again: 0.4 to 1.2 ms a run.
- Loading makes half the garbage it made: Cemacs's 44 modules load in 24.4 ms instead of 38.2.
- The resolver's definite assignment costs the same per statement whatever the number of variables: a function of
  4,000 variables resolves in 6 to 7 ms instead of 120 to 190.
- The start stays where it was before std/sparse and std/quad: the sources of std/ are strings that only code names,
  and a program's stacks start small: `io.Print(1)` in 2.70 ms, 2.82 before, in the release build.
- `encode.Unbase64` of 1.4 MB, a page's screenshot, 572 -> 5.7 ms.
- The JIT makes a unit's machine code at MIR's level 1 first, in 30 to 60 % less time, and its level 2 in another
  domain once the unit is hot: Lorenz on [0, 100] 83 -> 66 ms, `structs` 51 -> 40, long runs at level 2's speed.
- The JIT reads and writes lists of integers by index, and checks the indexes that move with a loop's counter once,
  before the loop: a sparse product 3.75 -> 2.79 ns a non-zero.
- The JIT keeps small arrays of floats in slots and inlines the functions that give them, goes back to the interpreter
  inside an if, and leaves it the statements it can't make, so the loop of `ode.Solve` is machine code; a loop whose
  statement left to the interpreter runs at nearly every turn stays in the interpreter: 1,011 -> 75 ms for 10^6 turns.
- `f()`, a call with no argument of a function held in a value, and `random.Float()` are machine code: `f()` 37 -> 2.2
  ns, 10^6 single draws of `stats.MonteCarlo` 539 -> 8.9 ms. `^`, `math.Exp` and the other functions of one float on an
  array of floats run unboxed, and `num.Uniform` draws in one native loop, the same numbers for a seed.
- `-x`, `math.Abs`, `list.Max` and `list.Min` on an array of floats in one native pass, and `num.Dot` without the array
  of products: 2 to 10 times faster at 1,000 floats, the same bits.
- A native that wakes many fibers from another domain writes the wake pipe once: when one native wakes 10,000 fibers,
  the last is awake in 9.5 ms instead of 11.6; `json.Text` of a small map in 314 ns instead of 390.
- `json.Text` and `json.Parse` take a text eight bytes at a time, and so does the length of a text: 1.6 MB 3.6 ->
  0.6 ms. `csv.Text` writes a list of lists natively, 5 times as fast.
- `cells.Variables` of a session that holds 10^6 numbers and a model fitted on 10^6 rows answers in 0.09 ms instead of
  4.1 s; `"$xs"` of 10^6 integers 131 -> 55 ms, of 10^6 floats 1080 -> 936 ms; the text of `[1, 2, 3]` 145 -> 120 ns.
- The text of a float, for `io.Print`, `"$x"`, `value.Text` and `json.Text`, by Ryu's tables (Adams, PLDI 2018)
  instead of up to three `printf` and two `strtod`, in the same bytes: `json.Text` of 32,000 floats 97 -> 3.9 ms, the
  scene of a Lorenz curve 30 -> 1.4 ms, `"$x"` of a float of 17 digits 2.9 us -> 0.19 us.

### Fixes

- On a phone no page of the site scrolls sideways: the header takes a second line, long links and code wrap, and a
  formula wider than its line scrolls in its own box.
- `http.Fetch` names the port in `Host` when it isn't the scheme's own, so that a server that compares a page's
  `Origin` with its `Host` finds the same text.
- `cesia lsp` finds a name of a package of the project, as `shop.Total`, in its open buffers before the disk, with its
  doc text for hover.
- The full list is in the commits since v1.1.0.

## 1.1.0

Everything here is added: a program written for 1.0 runs as it did.

### Language

- `a if c else b`, the value first as in Python: the same tree as `if c a else b end`, so it costs nothing when it runs.
- `return x if c` and `break if c`, when the condition ends the line, as in Ruby: the same tree as `if c return x end`.
- `fiber.Channel(size = n)` holds n values at most; `fiber.Close`, `fiber.Select` with a timeout, `fiber.Cancel`, and
  `fiber.Wait(task, timeout =)`.
- `sys.Write(path, text, sync = true)` answers once the file and its folder are on the disk; `text.ByteFind(..., fold = true)`
  ignores the case of ASCII letters; `text.IsUtf8` and `text.Count`; `sys.ReadInput(count)`; `sys.Start(..., dir =)`.

### Servers

- `cesia run --workers N` serves one listener from N processes; HUP replaces them without a failed request; TERM and INT
  stop a server cleanly; `sys.Stops` tells every fiber of a stop.
- `std/log` writes a JSON line per event and `std/metrics` counts for Prometheus; `http.Serve` holds under abuse.

### Tools

- `cesia lsp`, a language server: the marks of `cesia check` as you type, the docs under the cursor, definitions, completion.
- `cesia fmt` writes files in the style of Cesia's code and checks that each keeps its tree.
- Native packages: a package's engine in OCaml, compiled once against `Cesia_v1`, runs its natives under `native=LABEL`.

### Speed

Measured on the same machine as the others, in the book's chapter on speed:

- `fib` 74 -> 58 ms, ahead of Java's 71; maps 253 ms, ahead of Go's 272;
- a fiber 3.4 us and 2.1 KB, less memory than a goroutine;
- a start in 2.62 ms;
- HTTP: a tiny route 67k requests a second, beside Go's 67k, and JSON 48k, ahead of Node's 41k.

### Fixes

- An example's check that waits no longer overwrites the variables before it.
- The tests run on macOS's own tools; on a phone, the site's contents come first, above the text.
- The full list is in the commits since v1.0.0.

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
