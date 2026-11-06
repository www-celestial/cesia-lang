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

The script downloads the release for your system and checks its fingerprint. It puts the release in `~/.cesia` and two names
for the same program in `~/.local/bin`: `cesia` and the short `ce`. If that folder isn't on your `PATH` yet, the script says so.

A release holds every C library that Cesia's libraries need: nothing else is installed by hand. Check that it works:

```sh
cesia version
```

It prints the version, such as `cesia 1.0.0`. Later, `cesia upgrade` shows the notes of the newest release and asks before it
installs it.

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
[hot reload](glossary.md#hot-reload):

```sh
cesia run --watch hello.ce
```

A program that has ended starts again when the file changes. One that is still running, such as a server or a window, keeps its
state and takes the new code at once. Press `Ctrl-C` to stop.

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
  fingerprint of each of their files;
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
its result at once. An editor can also show the errors of a file in its lines, before it runs, with
[cesia check](commands.md#cesia-check).

## Next

You can run a program. The next chapter, [Values and names](values.md), shows what a program works with: numbers, texts, true
and false, and the names that hold them.
