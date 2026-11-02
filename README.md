# Kepler

A small interpreted language, written in OCaml. Fast, safe by default, with fibers, files, processes, HTTP and C calls.

## Install

```bash
dune build --profile release
ln -s "$PWD/_build/default/bin/main.exe" ~/.local/bin/kepler
```

## Write and run a program

```bash
kepler new hello       # creates hello/, with kepler.toml and main.kp
cd hello
kepler do run

kepler run main.kp           # or run any file directly
kepler run --watch main.kp   # reloads the code at each save
```

`examples/tour.kp` shows the language in one file. `examples/notes.kp` is a web app in 23 lines. `examples/stats.kp` works on a table.

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
kepler run --allow read=./data,net=:8080 server.kp
kepler run --limit memory=512M,steps=1000000 program.kp
```

## A project

A `kepler.toml` next to the code declares what can be run, and which C libraries are used:

```toml
[project]
name = "notes"

[tasks.serve]
file = "notes.kp"
allow = ["read=notes.txt", "write=notes.txt", "net=:8080"]
```

```bash
kepler do          # lists the tasks
kepler do serve    # runs one, and shows the exact command
```

## Editors

Neovim and Vim: copy `tools/editors/nvim/` into `~/.config/nvim/`.

Emacs: add `(load "/path/to/kepler/tools/editors/kepler-mode.el")` to your `init.el`.

## What's there

In every program, with no `use`:

- Functions: `map`, `filter`, `reduce`, `scan`, `group`, `top`, `range`, `count`, `flat_map`, `sort`, `sort_by`, `order`, `reverse`, `unique`.
- Lists: `push`, `concat`, `take`, `skip`, `index_of`, `flatten`, `zip`, `length`.
- Dictionaries: `{"a": 1}`, `d["a"]`, `d["a"] = 2`, `get`, `get_or`, `has`, `put`, `drop`, `keys`, `values`, `pairs`, `map_values`.
- Texts: `split`, `join`, `replace`, `slice`, `trim`, `lower`, `upper`, `contains`, `starts_with`, `ends_with`, `find`, `repeat`, `chars`, `lines`, `pad_left`, `pad_right`, `number`, `text`, and for bytes `bytes`, `from_bytes`, `byte`, `byte_slice`, `byte_find`.
- Numbers: arrays and matrices compute element by element, with `sum`, `mean`, `min`, `max`, `matmul`, `transpose`, `sqrt`, `exp`, `log`, `sin`, `cos`, `bit_and`, `bit_or`, `bit_xor`.
- Results: `Ok`, `Err`, `?`, `unwrap`, `unwrap_or`, `map_ok`, `and_then`. Fibers: `spawn`, `wait`.

With `use`:

| Module | What it gives |
|---|---|
| `sys` | files, `stat`, `rename`, environment, `run`, processes in a stream with `start`, clock |
| `net`, `http` | TCP, HTTP server and client |
| `web` | routes, `:params`, middleware, JSON, forms, cookies, static files, templates, WebSocket |
| `tls` | TLS through OpenSSL, server and client, for `http` and `web` |
| `crypto` | SHA-256, SHA-512, BLAKE2b, HMAC, encryption, public keys, signatures, Argon2, through libsodium |
| `encode` | hexadecimal, Base64, URLs, queries |
| `json`, `csv`, `regex`, `date` | parsing and writing; `regex` stays linear on any pattern |
| `set`, `queue`, `heap`, `algo` | data structures, search, graphs, permutations, Levenshtein |
| `num` | numpy-like: statistics, linear algebra, QR, eigenvalues, FFT, random numbers |
| `frame` | pandas-like: tables, `where`, `sort_by`, `group_by`, `join_on`, CSV |
| `rope`, `history` | a large text with fast edits, and undo |
| `c` | C libraries: 60 arguments, structures by value, variadic functions, callbacks |
| `cpp` | C++: classes and functions through a generated layer, exceptions become panics |
| `sdl` | a native window: text, rectangles, keys, mouse, clipboard |

## A web server

```kepler
use web

defn hello(request)
  web.send_json({"hello": request.params["name"]})
end

app = web.get("/hello/:name", hello, web.app())
print(web.serve(app, port = 8080))
```

```bash
kepler run --allow net=:8080 server.kp
```

## C and C++

```kepler
use c

defn main()
  m = c.open("m", version = 6)?
  cos = c.fn("cos", ["f64"], "f64", m)?
  print(cos(0.0))
  Ok(missing)
end

print(main())
```

C++ has no stable binary interface, so `cpp.wrap` generates a small C layer and compiles it once: see `std/cpp.kp`.

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

look = ui.look(ui.dark, sdl.measure(window).width, sdl.measure(window).height)
frame = flatten([ui.panel("Details", area, look), ui.slider(0.5, bar, look)])
```

`update` gets a `tick` while `moving(state)` is true, and `ui.ease` moves a value at the same speed at any frame rate. A window with
nothing moving draws nothing. The interface font is Adwaita Sans, titles use Noto Sans Medium, and code JetBrains Mono: all three are in
`examples/fonts/`, under the SIL Open Font License.

## Documentation

Comments are `--` for a line and `(* ... *)` for several, which can hold one another. A `(** ... *)` above a definition documents it,
like `--` lines:

```kepler
(** The next number.
      inc(1) --> 2 *)
inc(x) = x + 1
```

The documentation comes from the language. A comment just above a definition documents it, and the examples in it run under
`kepler test`.

```kepler
-- The square of a number.
--
--   square(3) --> 9
square(x) = x * x
```

`kepler doc` lists the modules, `kepler doc num` the names of a module, and `kepler doc num.solve` shows one. A program, or an
editor, asks the same way: `doc("num.solve")` or `doc(sort)` give the text or `missing`, and `doc_names("num")` the names.

## Large data

`frame` and `num` work on whole columns in OCaml. A column of integers or floats is stored without a box, and `group_by`,
`sort_by`, `join_on`, `where_mask` and `from_csv` are native. As with pandas, the data stays in memory.

Large work uses half of the logical cores, or the number in `KEPLER_CORES`. The results are the same to the last bit, whatever
that number.

`num.solve`, `num.inverse`, `num.det`, `num.qr` and `num.eigen` go through LAPACK when the machine has it, and `matmul` through
a fast BLAS such as OpenBLAS. They are found at run time, and without them the same functions work, more slowly. Install
OpenBLAS for speed.
`num.backend()` names the library in use, and `KEPLER_BLAS` chooses one, or `none`.

## Limits

- Arrays have two dimensions at most.
- Linux on x86-64 is the verified platform. `.github/workflows/ci.yml` also runs the tests on macOS, and only builds on Windows.

## License

Kepler is under the MIT License: see `LICENSE`.

The fonts in `examples/fonts/` keep their own license, the SIL Open Font License, with its text next to them: `AdwaitaSans-OFL.txt`,
`NotoSans-OFL.txt`, and `OFL.txt` for JetBrains Mono.
