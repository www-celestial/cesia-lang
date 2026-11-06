# Packages

In this chapter you split a program into folders, use the libraries that come with Cesia, and take code from other projects.
You also meet `cesia.toml`, the file that describes a project: its name, its tasks, and what it uses.

## use

[use] brings a [package](glossary.md#package), a module of code, into a file. The name in the code is the last part of its path, followed by a dot:

```cesia
use std/encode
encode.Hex("hi") -->
encode.Base64("hi") -->
```

### as

`as` gives the package another name, which helps when two would have the same one, or when a name is long:

```cesia
use std/set as sets
s = sets.Of([3, 1, 3, 2])
sets.Items(s) -->
sets.Member(2, s) -->
```

### Where the code comes from

The first part of the path says where the code comes from:

| A use | Takes |
|---|---|
| `use std/rope` | what comes with Cesia: its libraries and the modules of the binary |
| `use src/geometry` | a folder of your project, from its root |
| `use deps/someone/project/src/x` | a folder of another project, from that project's root |

A use takes no `./`, no `../` and no quotes. The reference lists everything under `std/`: [std/sys], [std/json],
[std/web], [std/sql] and the others.

## A package is a folder

A package is all the `.ce` files of one folder, as in Go. There is no `package` line, and no import of one file. Here is a
project with two packages of its own:

```text
shop/
  cesia.toml
  src/
    main.ce
    prices/
      tax.ce
      round.ce
```

The two files of `src/prices/` are one package. Here they are, one after the other: `tax.ce` calls `cents`, a small name
of `round.ce`, without a `use`.

```cesia
(* src/prices/tax.ce *)
WithTax(price) = cents(price * 1.2)

(* src/prices/round.ce *)
cents(x) = Round(x * 100) / 100

WithTax(10.25) -->
```

`src/main.ce` writes `use src/prices`, and calls `prices.WithTax(10.25)`.

- A name with a capital, `WithTax`, is public: other packages reach it as `prices.WithTax`. A name with a small letter,
  `cents`, stays inside its folder.
- A subfolder is another package: `src/prices/old/` is used as `use src/prices/old`, and named `old` in the code.

### Names every file sees

A name that every file sees without a `use`, as [Count] or [Get], belongs to the [prelude](glossary.md#prelude). It means
that one in every file: a package can't define it, and the message says so. Give your function a name of its own, as
`set.With` adds to a set where [Put] adds to a dictionary.

```cesia fails
Count(basket) = 3
```

### Private names

A private name is no name of the package from outside, and the message says so:

```cesia fails
use std/encode
encode.hexDigit
```

## cesia.toml

`cesia new shop` makes a project: a `cesia.toml`, `src/main.ce`, a `.gitignore`, `std/`, a copy of Cesia's libraries for
this project, and `cesia.lock`, which keeps their fingerprints. `cesia.toml` says what the project is:

```toml
[project]
name = "shop"
cesia = "0.2"     # the oldest Cesia it needs
src = ["src"]     # the folders of its code: the default

[tasks.run]
file = "src/main.ce"

[tasks.serve]
file = "src/server.ce"
allow = ["read=data", "net=:8080"]
```

### Tasks

A task is a program with its permissions, which the chapter [Permissions](permissions.md) explains. `cesia do` lists the tasks,
and `cesia do serve` runs one and shows the exact command, so you can type it yourself:

```bash
cesia do
cesia do serve
```

The root of a project is the folder of the nearest `cesia.toml` above the program. Without one, it is the folder of the file
that runs.

## Code from other projects

Any project with a `cesia.toml` can give its packages to others, as a [dependency](glossary.md#dependency) of theirs:
there is no registry. A `[deps]` table names the repository,
a tag, and the packages you take:

```toml
[deps.cemacs]
from = "github.com/www-celestial/cemacs"
version = "v0.3.0"
take = ["src/folders"]
```

Its code then writes `use deps/www-celestial/cemacs/src/folders`, and names it `folders`.

### cesia pkg

`cesia pkg add` writes that table for you, and fetches the code. `cesia pkg install` makes `std/` and `deps/` what
`cesia.toml` and `cesia.lock` say, for instance after a clone:

```bash
cesia pkg add github.com/www-celestial/cemacs@v0.3.0 src/folders
cesia pkg install
cesia pkg
```

- git fetches each tag once, into a cache: another project that takes it needs no network.
- `cesia.lock`, the [lock file](glossary.md#lock-file), keeps the commit of each tag and a fingerprint of each file. The code in `std/` and `deps/` is read only: Cesia
  checks each file the first time it reads it, so a change by hand stops the program.
- To change someone's package, fork it, then let `cesia pkg move` point the project at your fork.
- `cesia run`, `cesia do` and `cesia test` never use the network.

## Next

Your programs have parts, and can use the parts of others. The next chapter, [Permissions](permissions.md), says what a program
may touch outside itself, and how much it may use.
