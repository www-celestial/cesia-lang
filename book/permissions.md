# Permissions

In this chapter you decide what a program may touch: files, the network, other programs. A Cesia program can touch nothing
outside itself until its command line allows it. You also set limits on how long it runs and how much memory it takes, so that
a program you don't trust, or a bug, can't harm the machine.

## Nothing by default

Without a permission, a program computes and prints, and that is all. A function that needs more stops the program, and the
message says what to add:

```cesia fails
use std/sys
sys.Read("notes.txt")
```

A denied permission is a bug, not an `Err`: the program asked for something it was not given, and the fix is on the command
line.

## --allow

`--allow` takes a list of permissions, separated by commas:

```bash
cesia run --allow read program.ce
cesia run --allow read=./data,write=./out program.ce
cesia run --allow net=:8080,env=HOME server.ce
```

| Permission | Allows |
|---|---|
| `read`, `read=./data` | reading files, all of them or those under a folder |
| `write`, `write=./out` | writing, renaming and removing files, all of them or under a folder |
| `net`, `net=:8080` | the network, or listening on one port |
| `exec`, `exec=git` | running other programs, all of them or one |
| `env`, `env=HOME` | reading environment variables, all of them or one |
| `ffi=sqlite3` | loading a C library, by its name |
| `debug` | the breakpoints of a debugger, for `cesia run --debugger` |
| `all` | everything |

A permission after `=` is as narrow as you can make it. Give that one: a program that reads its data from `./data` needs
`read=./data`, not `read`. Reading outside the folder is denied as if nothing had been given.

## ffi is total trust

A C library runs outside Cesia's checks: it can read any file, open any connection, and break the memory of the program.
`ffi=NAME` gives a program everything for that library, so give it only to libraries you trust, as the ones Cesia's own
modules use.

## A task keeps its permissions

Typing permissions each time is slow and error-prone. A task of `cesia.toml` writes them once, next to the file it runs:

```toml
[tasks.serve]
file = "src/server.ce"
allow = ["read=data", "write=data/uploads", "net=:8080"]
limit = "memory=1G"
```

`cesia do serve` runs it, and prints the exact `cesia run` command first. A reader of the project sees in one place what each
program may do.

## --limit

`--limit` stops a program that goes too far, with `Limit "memory" reached.` and the line where it was:

```bash
cesia run --limit memory=512M,steps=10000000 program.ce
```

| Limit | Stops the program when |
|---|---|
| `memory=512M` | it holds more memory than that: `K`, `M` and `G` are its units |
| `steps=1000000` | it has run that many steps, as a loop that never ends |
| `depth=10000` | calls inside calls go deeper than that: the default is 10,000 |
| `nesting=600` | code, JSON or values are nested deeper than that: the default is 600 |

Without `--limit memory`, a program may take at most 80% of the machine's memory, so that one large array can't freeze it.
A function that calls itself forever stops at the depth limit, with the line of the call:

```cesia fails
forever(n) = forever(n + 1) + 1
forever(1)
```

## Running someone else's code

Permissions and limits together make it safe to run a program you just downloaded:

- run it first with no `--allow`: each message says what it wants, one at a time;
- give the narrowest permission for each, a folder or a port;
- add a `--limit memory` and `steps` while you look at what it does.

## Next

Your programs touch only what you allow. The next chapter, Files, reads and writes files, lists folders, runs other
programs, and reads the clock.
