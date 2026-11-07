# Commands

Every command of `cesia`, and every option. `cesia` alone prints the short form of this page.

## cesia run

```bash
cesia run [--allow LIST] [--limit LIST] [--watch] [--workers N] [--debugger FILE] [--repl] [--no-spec] [--no-jit] [--seed N] file.ce [args...]
```

Runs a program. The words after the file are its arguments, in [sys.Args].

| Option | What it does |
|---|---|
| `--allow LIST` | the permissions, separated by commas: `read`, `write`, `net`, `exec`, `env`, `ffi`, `debug`, `all`, each with `=` and a scope if needed. See [Permissions](permissions.md). |
| `--limit LIST` | the limits: `memory=512M`, `steps=N`, `depth=N`, `nesting=N`. See [Permissions](permissions.md). |
| `--watch` | reloads the code at each save of one of its files, without stopping the program |
| `--workers N` | serves on N processes, or one per core with `cores`, under a supervisor that starts again a worker that ends and replaces them all on HUP. See [Every core](http.md#every-core). Not with `--watch`, and not on Windows. |
| `--debugger FILE` | runs a debugger written in Cesia beside the program, and gives it the `debug` permission by itself: no `--allow debug`. `--debugger debugger` is the one that comes with Cesia. See [The prompt and the debugger](debug.md). |
| `--repl` | opens a prompt beside the program, in the package of its main file: an expression shows its value, a function defined again replaces the program's own. Without a file, a prompt on an empty program. See [The prompt and the debugger](debug.md). |
| `--no-spec` | runs without the versions of each function that Cesia makes for the types it sees: the results must be the same |
| `--no-jit` | runs without native code, in the [interpreter](glossary.md#interpreter-and-jit) only |
| `--seed N` | gives [std/random] the seed N, a whole number, in place of one from the system: the same seed gives the same numbers. [random.Seed] tells the seed of a run. |

`cesia run .` runs all the files of the current folder as one program.

## cesia test

```bash
cesia test [path | file.ce:isName] [--seed N] [--cases N] [--update] [--allow LIST] [--no-spec]
```

Runs the examples of the documentation and the test functions of the project, or of a folder or a file, or one test function
of a file. Ends with the code 1 when a test fails. See [Tests](tests.md).

| Option | What it does |
|---|---|
| `--seed N` | the cases of [test.ForAll] of an earlier run again: the summary of a run that tried properties gives its seed |
| `--cases N` | how many cases each [test.ForAll] tries, 100 by default |
| `--update` | accepts the new and the changed [test.Snapshot]s of the tests that run |
| `--allow LIST` | more permissions for the tests, as for `cesia run`, beyond those a test has by default |
| `--no-spec` | runs without the versions of each function by type, as `cesia run --no-spec` |

## cesia check

```bash
cesia check [--json] [--stdin file.ce] [path...]
```

Reads the code and says what is wrong, without running any of it: syntax, names, the arguments of a known function, struct or
native, values that surely don't fit a type, and [results](types.md#checking-without-running-cesia-check) left unhandled. A path is a file, or a
folder with its subfolders; with none, the source folders of `cesia.toml`. A file of a source folder is read with the other
files of its package, as `use` reads them, and a test with its package; any other file stands alone, as a program. It needs
the read permission only, so checking a project from elsewhere is safe. Ends with the code 1 when there is an error; warnings
alone give 0.

| Option | What it does |
|---|---|
| `--json` | one JSON object per line, and nothing else: `file`, `line`, `column`, `end` (the column after the span), `severity` (`"error"` or `"warning"`), `message`, `hint` |
| `--stdin file.ce` | the text of that file comes from the input instead of the disk, as an editor sends a buffer not yet saved |

## cesia fmt

```bash
cesia fmt [--check] [path...]
```

Writes files in the style that the code of Cesia shares, and names each one it changes. A line that starts a statement is
indented two spaces for each block it is in, `defn`, `if`, `for`, `while`, `match` or `struct`, and a line that goes on with
a statement, inside brackets or after a comma, moves with the line it continues; no line ends with spaces; no two blank
lines follow each other, and none starts or ends the file. Nothing else changes: not a word, not a comment, not a text, not
a `\r\n`. Before it writes a file, it checks that the code reads as the same program; a file that doesn't read stays as it
is, and is named with its error. A path is a file, or a folder with its subfolders; with none, the project here, without
its `std/` and `deps/`. It needs the read and write permissions. Ends with the code 1 when a file stays as it is.

| Option | What it does |
|---|---|
| `--check` | writes nothing: names each file out of the style, and ends with the code 1 if there is one |

## cesia lsp

```bash
cesia lsp
```

A language server, for the editors that speak the Language Server Protocol: it reads their messages on its input and answers
on its output. It shows what `cesia check` finds in an open file as it is typed, the documentation of the name under the
cursor, where a name is defined, and the names of a package after its dot. The editor starts it in the folder of the
project, as [Editors](editors.md) shows for each one. It needs the read permission only.

## cesia do

```bash
cesia do [task]
```

Without a task, lists the tasks of `cesia.toml`. With one, runs the tasks it needs, then it, and prints each command first.
See [cesia.toml](toml.md).

## cesia new

```bash
cesia new name
```

Makes a project in a new folder: `cesia.toml`, `src/main.ce`, `.gitignore`, `std/` and `cesia.lock`.

## cesia pkg

```bash
cesia pkg [install | update [label] [--to tag] | add url@tag [package...] | move old new | --check]
```

| Command | What it does |
|---|---|
| `cesia pkg` | each package, its version, and whether it is as installed |
| `cesia pkg install` | makes `std/` and `deps/` what `cesia.toml` and `cesia.lock` say |
| `cesia pkg update [label] [--to tag]` | a dependency to its newest tag, or to that one, and `std/` to this Cesia |
| `cesia pkg add url@tag [package...]` | writes a `[deps]` table and installs it |
| `cesia pkg move old new` | takes a fork instead of a repository, and rewrites the uses of the project |
| `cesia pkg --check` | the newer tags, through the network |

See [Packages](packages.md).

## cesia upgrade

```bash
cesia upgrade [--nightly]
```

Shows the notes of the newest release of Cesia, and asks before it installs it. `--nightly` takes the build of the day.

## cesia doc

```bash
cesia doc [name]
cesia doc --site [folder] [--open]
```

`cesia doc` lists the modules; with a module, such as `std/num`, its names; with a name, such as `num.Solve` or `Sort`, its
text and its examples. `--site` builds the site of the project in `site/`, or in the folder given, and `--open` opens it in
the browser. See [Tests](tests.md).

## cesia version

```bash
cesia version
```

Prints the version of Cesia.
