# cesia.toml

Every table and every key of `cesia.toml`, the file at the root of a project. A key that Cesia doesn't know stops `cesia do`
with its line, so a typo can't go unseen. The keys of `[site]` are the exception: `cesia doc --site` reads them, and it is
the one that checks them.

## `[project]`

```toml
[project]
name = "shop"
cesia = "1.0"
src = ["src"]
native = ["sodium"]
```

| Key | What it says |
|---|---|
| `name` | the name of the project |
| `cesia` | the oldest Cesia it needs: an older one stops at once, and says to run `cesia upgrade` |
| `src` | the folders of its code, `["src"]` when it is left out: what another project takes without `take`, and what `cesia doc` and `--site` read |
| `native` | the C libraries it loads: each task that runs a file gets `ffi=` for each of them |

## `[native]`

The engine of a [native package](native.md): OCaml compiled once, which runs the natives of one of the project's packages.

```toml
[native]
package = "cesia/echo"
natives = ["reverse", "later"]
```

| Key | What it says |
|---|---|
| `package` | the package whose files see the natives, as a path from the root |
| `natives` | their names, each a private name: the engine `native/NAME-TAG.cmxs` must register exactly these |

## `[tasks.NAME]`

A task is a program to run with its permissions, a command, or a group of other tasks. `cesia do NAME` runs it.

```toml
[tasks.serve]
file = "src/server.ce"
allow = ["read=data", "write=data", "net=:8080"]
limit = "memory=1G"
watch = true
needs = ["test"]

[tasks.test]
run = ["tests/run.sh"]

[tasks.all]
needs = ["test", "serve"]
```

| Key | What it says |
|---|---|
| `file` | the Cesia file to run, or `"."` for all the files of the root as one program |
| `allow` | its permissions, as `--allow` takes them, one per text |
| `limit` | its limits, as `--limit` takes them, in one text |
| `watch` | `true` to reload at each save, as `--watch` |
| `run` | a command and its arguments, run as they are, without a shell; a task has `file` or `run`, not both |
| `needs` | the tasks to run first, in order; a task with only `needs` is a group |

## `[deps.LABEL]`

A project whose packages this one takes. `cesia pkg add` writes the table.

```toml
[deps.geometry]
from = "github.com/someone/geometry"
version = "v1.2.0"
take = ["src/shapes"]
```

| Key | What it says |
|---|---|
| `from` | the repository, without `https://` |
| `version` | a tag of it |
| `take` | the packages taken, as paths from its root; without it, every package of its `src` |

## `[site]`

What `cesia doc --site` writes on each page.

```toml
[site]
title = "Shop"
source = "https://github.com/someone/shop/blob/main/"
```

| Key | What it says |
|---|---|
| `title` | the name at the top of each page |
| `source` | the start of a link to the code: a name's page links to its file and line |
