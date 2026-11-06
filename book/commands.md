# Commands

Every command of `cesia`, and every option. `cesia` alone prints the short form of this page.

## cesia run

```bash
cesia run [--allow LIST] [--limit LIST] [--watch] [--debugger FILE] [--no-spec] [--no-jit] file.ce [args...]
```

Runs a program. The words after the file are its arguments, in [Args].

| Option | What it does |
|---|---|
| `--allow LIST` | the permissions, separated by commas: `read`, `write`, `net`, `exec`, `env`, `ffi`, `debug`, `all`, each with `=` and a scope if needed. See [Permissions](permissions.md). |
| `--limit LIST` | the limits: `memory=512M`, `steps=N`, `depth=N`, `nesting=N`. See [Permissions](permissions.md). |
| `--watch` | reloads the code at each save of one of its files, without stopping the program |
| `--debugger FILE` | runs a debugger written in Cesia beside the program: it needs `--allow debug` |
| `--no-spec` | runs without the versions of each function that Cesia makes for the types it sees: the results must be the same |
| `--no-jit` | runs without native code, in the interpreter only |

`cesia run .` runs all the files of the current folder as one program.

## cesia test

```bash
cesia test [path] [--no-spec]
```

Runs the examples of the documentation and the test functions of the project, or of a folder or a file. Ends with the code 1
when a test fails. See [Tests](tests.md).

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
the browser. Outside a project, it builds this book and the reference of this Cesia, in the cache. See [Tests](tests.md).

## cesia version

```bash
cesia version
```

Prints the version of Cesia.
