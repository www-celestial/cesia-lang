# Permissions

In this chapter you decide what a program may touch: files, the network, other programs. A Cesia program can touch nothing
outside itself until its command line allows it: it runs in a [sandbox](glossary.md#sandbox). You also set limits on how long it runs and how much memory it takes, so that
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
| `net`, `net=:8080` | the network, or listening on one port of this machine only: the address, or the one a name resolves to, is 127.0.0.1 or ::1 |
| `net=0.0.0.0:8080`, `net=[::]:8080` | listening on one port for other machines too, on every address or on one |
| `net=example.com`, `net=example.com:443` | connecting to one host, on any port or on one |
| `net=own` | listening on this machine, and connecting only to the program's own listeners while they are open, by address or `localhost`, with no name looked up: what a test gets |
| `exec`, `exec=git` | running other programs, all of them or one |
| `env`, `env=HOME` | reading environment variables, all of them or one |
| `ffi=m`, `ffi=build/libdemo.so` | loading a C library, by its name or by the exact path of its file |
| `debug` | the breakpoints and the code run by [std/debug]; `cesia run --debugger` and `cesia run --repl` give it by themselves, with no `--allow` |
| `all` | everything |

### This machine or the network

A server listens on 127.0.0.1 by default, which only programs of the same machine reach, and `net=:8080` allows that alone.
To take connections from other machines, as from a phone on the same wifi, the server listens on `0.0.0.0` (every address
of the machine), and the permission names that address too:

```bash
cesia run --allow net=0.0.0.0:8080 server.ce
```

where `server.ce` calls `http.Serve(app, host = "0.0.0.0")`. Under `net=:8080`, that listen is denied, and the message says
which permission to write.

### As narrow as you can

A permission after `=` is as narrow as you can make it. Give that one, by the
[principle of least privilege](glossary.md#principle-of-least-privilege): a program that reads its data from `./data` needs
`read=./data`, not `read`. Reading outside the folder is denied as if nothing had been given. A folder holds a path by where
it leads, its links followed: a link in `./data` that points outside it is denied too, as is writing a new file through one.

## ffi is total trust

A C library, called through the [foreign function interface](glossary.md#foreign-function-interface), runs outside
Cesia's checks: it can read any file, open any connection, and break the memory of the program.
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

### The defaults

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

Your programs touch only what you allow. The next chapter, [Files](files.md), reads and writes files, lists folders, runs other
programs, and reads the clock.
