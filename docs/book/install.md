# Install and first run

In this chapter you install Cesia, run a first program, and make a project with its own tasks.

## Install

On Linux and macOS, in a terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/www-celestial/cesia-lang/main/install.sh | sh
```

On Windows, in PowerShell:

```powershell
irm https://raw.githubusercontent.com/www-celestial/cesia-lang/main/install.ps1 | iex
```

The script downloads the release for your system, Linux or macOS on x86-64 or arm64, Windows on x86-64, and checks its
fingerprint: a *fingerprint*, or checksum, is a short number computed from every byte of a file, here its SHA-256, that
changes if a single byte does. The release publishes the fingerprint of each archive, and a download that doesn't match it
is refused, so a file cut or damaged on the way is never installed. The script puts the release in `~/.cesia` and two names
for the same program in `~/.local/bin`: `cesia` and the short `ce`. Your `PATH` is the list of folders where the shell looks
for a command; if `~/.local/bin` isn't in it yet, the script says so. `CESIA_HOME` and `CESIA_BIN` change the two folders,
and `CESIA_RELEASES` the place of the releases, as [Environment variables](env.md) says.

A release holds every C library that Cesia's libraries need: nothing else is installed by hand. Check that it works:

```sh
cesia version
```

It prints the version, such as `cesia 1.0.0`. Later, `cesia upgrade` shows the notes of the newest release and asks before it
installs it; it checks the BLAKE2b fingerprint of what it downloads the same way.

## A first program

A program is a text file whose name ends in `.ce`. Make a file `hello.ce` with one line:

```cesia
use std/io
io.Print("Hello, world!")
```

Run it:

```sh
cesia run hello.ce
```

[io.Print] writes its arguments on one line, with a space between them, and a line end after the last one. It takes any value,
not only texts:

```cesia
io.Print("Two and two make", 2 + 2)
io.Print([1, 2, 3])
```

A program runs from its first line to its last. There is no `main` to write: the lines at the top of the file are the
program.

## Run it again at each save

`--watch` keeps the program running and loads your changes each time you save the file, a
[hot reload](glossary.md#hot-reload): the new code replaces the old in the running program, which keeps its values. A change
is running within 100 ms of the save:

```sh
cesia run --watch hello.ce
```

A program that has ended starts again when the file changes. One that is still running, such as a server or a window, keeps its
state and takes the new code at once. Press `Ctrl-C` to stop.

### Trying a line

`cesia run --repl` opens a prompt, a [REPL](glossary.md#repl) for *read, eval, print loop*: type an expression, and it shows
its value. It suits trying a function before you write it in a file. Ctrl-D leaves it.

```text
$ cesia run --repl
> use std/text
> text.Upper("hello")
HELLO
```

The chapter [The prompt and the debugger](debug.md) shows more of it.

## When something is wrong

An error names the file, the line and the column, and shows the line. Cesia checks every name of a program before it runs its
first line, so a typo stops it before anything happens: the first line here never prints.

```cesia fails
io.Print("This line never runs")
Pritn("Hello")
```

### Mistakes that show when their line runs

Other mistakes show only when their line runs. Here a text and a number are added, and the message says what to write instead:

```cesia fails
io.Print("Total: " + 3)
```

## A project

One file is enough for a script. For more, make a project:

```sh
cesia new hello
cd hello
cesia do run
```

`cesia new` makes a folder with:

- `cesia.toml`, which names the project and its tasks;
- `src/main.ce`, the program, which prints `Hello from hello`;
- `std/`, a copy of the libraries of Cesia, and `cesia.lock`, a [lock file](glossary.md#lock-file) that keeps the
  fingerprint of each of their files, its BLAKE2b-256, so that a file changed by hand, or a different copy on another
  machine, shows;
- `.gitignore`, which leaves `std/` and `deps/` out of git: `cesia pkg install` makes them again after a clone.

### Its cesia.toml

The `cesia.toml` of a new project:

```toml
[project]
name = "hello"
cesia = "1.0"

[tasks.run]
file = "src/main.ce"
```

`cesia = "1.0"` is the oldest Cesia the project needs. An older one stops at once, and says to run `cesia upgrade`.

## Tasks

A task names a program to run and what it may touch. `cesia do` lists the tasks, and `cesia do run` runs the task `run`. It
first shows the exact command:

```sh
$ cesia do run
> cesia run src/main.ce
Hello from hello
```

So you never have to remember a long command: write it once in `cesia.toml`, and `cesia do` runs it. Packages and tasks have a
chapter of their own later.

## Editors

Any editor works, since a program is a text file. The sources of Cesia hold a mode for Emacs and one for Neovim and Vim, in
`tools/editors/`, which colour the code. Keep a terminal beside your editor with `cesia run --watch`, and each save shows
its result at once. An editor that speaks the Language Server Protocol also shows the errors of a file in its lines as you
type, and the documentation of a name under the cursor, with [cesia lsp](commands.md#cesia-lsp): [Editors](editors.md) gives
the few lines each one needs.

## Next

You can run a program. The next chapter, [Values and names](values.md), shows what a program works with: numbers, texts, true
and false, and the names that hold them.
