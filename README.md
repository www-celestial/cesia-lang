# Cesia

A small language for solving real problems directly: a script that cleans a CSV, a web server on a database, a program that
drives other programs. It starts at once, it is safe by default, and when something goes wrong it says what to write.

```cesia
use std/web

app = web.App() then web.Get("/hello/:name", r -> web.Plain("Hello, $(r.Params.name)!"), it)
web.Serve(app, port = 8080)
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/www-celestial/cesia-lang/main/install.sh | sh    # Linux and macOS
irm https://raw.githubusercontent.com/www-celestial/cesia-lang/main/install.ps1 | iex         # Windows, in PowerShell
cesia upgrade              # later: the newest release, after its notes and a question
cesia upgrade --nightly    # a build of main between releases, made by hand
```

A release holds the binary and every C library its libraries use, in `~/.cesia/lib/`: OpenBLAS for BLAS and LAPACK (macOS has
its own), libsodium, SQLite, and OpenSSL on macOS and Windows (Linux keeps the system's, for its security fixes).
Nothing else is installed by hand. In `0.x` the middle number of a version rises when a change can break a program, the last one
for a fix, and the notes of a release come from the messages of its commits.

From the sources, with OCaml 5.5 and dune:

```bash
dune build --profile release
ln -s "$PWD/_build/default/src/bin/main.exe" ~/.local/bin/cesia
ln -s "$PWD/_build/default/src/bin/main.exe" ~/.local/bin/ce      # optional: the short name of the same binary
```

Such a binary says `cesia 0.3.0+dev`: `git pull` and `dune build` update it, not `cesia upgrade`. `ce` and `cesia` are one
program, as `vi` and `vim`: `ce run file.ce` is `cesia run file.ce`.

## Read the book

The book teaches Cesia from the start, in 22 short chapters, and the reference has a page for every name, each with examples
that ran when the site was built: **https://www-celestial.github.io/cesia-lang/**. It follows `main`, and each push publishes
it again.

The chapters are plain Markdown, in [`docs/book/`](docs/book/index.md). From a clone, `cesia doc --site --open` builds the same site in
`site/` and opens it, and `cesia doc list.Sort` or `cesia doc num.Solve` prints one page in the terminal.

## Editors

Neovim and Vim: copy `tools/editors/nvim/` into `~/.config/nvim/`.

Emacs: add `(load "/path/to/cesia/tools/editors/cesia-mode.el")` to your `init.el`.

## Limits

- Arrays have two dimensions at most.
- Linux on x86-64 is the verified platform. `.github/workflows/ci.yml` also runs the tests on macOS, and only builds on Windows.

## License

Cesia is under the MIT License: see `LICENSE`.
