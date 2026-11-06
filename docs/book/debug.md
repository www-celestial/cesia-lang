# The prompt and the debugger

Two ways to look inside a program while it runs, built on one engine: run this code here, where here is the running
program, or the place where it stopped.

## The prompt

`cesia run --repl` runs a program and opens a prompt beside it, inside the package of its main file. Take this `shop.ce`:

```cesia norun
use std/io

defn Price(n)
  n * 2
end

stock = 3
io.Print("start $(Price(stock))")
```

```bash
cesia run --repl shop.ce
```

```text
start 6
> Price(4)
8
> stock + 1
4
```

An expression shows its value. The prompt sees what the main file sees: its functions, its variables, its structs and the
packages it uses, here `io`. What you define at the prompt stays for the next lines:

```text
> rate = 1.5
> Price(rate)
3.0
```

A definition of a function of the program replaces it in the running program, which goes on with the new one, as a
[reload](commands.md#cesia-run) does:

```text
> defn Price(n)
.   n * 10
. end
> Price(4)
40
```

An error doesn't close the prompt. A bug in what you type shows its message, and its line when you typed several; a bug in a
function of the program shows where, as the program would, and the prompt waits for the next line. A bug in the main file
itself shows too, and the prompt opens on what ran before it, with the exit code 1 at the end:

```text
> Bad(9)
error: shop.ce:3:5: Index 9 is outside this array of 2 elements.
  3 |   xs[n]
    |     ^
  in Bad (shop.ce:3)
> 2 + 2
4
```

A block reads lines until its `end`, and a list or an expression cut in the middle reads the next line too: the prompt
shows `.` while it waits for the rest. A `use` at the prompt works for the lines after it.

The program runs while the prompt waits: a server goes on serving, a loop goes on looping, and a function you define again
takes effect at its next call. When the main file is done, the prompt stays until you leave it with Ctrl-D, at an empty
line. `cesia run --repl` alone, with no file, is a prompt on an empty program.

On a terminal, the keys edit the line: the arrows, Home and End, Ctrl-A and Ctrl-E for the start and the end, Ctrl-K and
Ctrl-U to cut to the end or the start, Ctrl-W for the word before; up and down walk the lines typed before. Ctrl-C clears
the line, and at an empty line stops the program, as anywhere.

The code typed at the prompt runs with the permissions of the program, no more: `--allow` gives them, as for the program
itself. `--repl` only adds the `debug` permission, for the prompt.

## The debugger

`cesia run --debugger debugger app.ce` runs the program under the debugger that comes with Cesia. It stops before the
first line, and at each stop it says where the program is and reads commands:

```cesia norun
use std/io

defn Total(n)
  sum = 0
  for i in 1..n
    sum = sum + Half(i)
  end
  sum
end

defn Half(i)
  i / 2
end

io.Print(Total(4))
```

```bash
cesia run --debugger debugger total.ce
```

```text
stopped at total.ce:15 (start)
(debug) break total.ce 12 if i > 2
breakpoint total.ce:12 if i > 2
(debug) continue
stopped at total.ce:12 (break)
(debug) print i * 10
i * 10 = 30
(debug) up
  Half (total.ce:12)
> Total (total.ce:6)
  <file> (total.ce:15)
(debug) print sum
sum = 1.5
```

| Command | What it does |
|---|---|
| `break FILE LINE` | stops at that line each time the program reaches it |
| `break FILE LINE if CONDITION` | stops there only when the condition is true: an expression of the variables there |
| `clear FILE LINE` | removes the breakpoint of that line |
| `breaks` | lists the breakpoints |
| `print EXPRESSION` | the value of any expression, in the current frame: its variables, its package, its uses |
| `vars` | every variable of the current frame that has a value |
| `watch EXPRESSION` | shows that expression at each stop; `unwatch EXPRESSION` stops it |
| `where` | the frames, from the innermost, the current one marked with `>` |
| `up`, `down` | moves to the frame of the caller, or back |
| `continue` | runs until the next stop |
| `step` | runs one statement, entering a call |
| `next` | runs one statement, a call as a whole |
| `out` | runs until the current function returns |

The current frame is the innermost at each stop. An expression only reads: what `print` computes never changes the
program.

### Stops on errors

A [bug](errors.md) stops the program where it happens, with every variable still there, before the error is shown:

```text
stopped at app.ce:7 (error)
  Index 3 is outside this array of 2 elements.
(debug) print xs
xs = [1, 2]
```

After `continue`, the error goes on as it would without the debugger. A bug in a [fiber](fibers.md) stops too, and the
stop says which fiber: `stopped at app.ce:4 (error) in fiber 1`. The others wait while the program is stopped.

### Fix and continue

While the program is stopped, change the code in its file and save it. When the program resumes, by `continue`, `step`,
`next` or `out`, the debugger reloads the files that changed and says so:

```text
(debug) continue
reloaded total.ce
```

The function that is running goes on with the code it started with; its next call runs the new code. A file with an error
doesn't reload: the debugger shows the error and stays stopped, so that you can fix it and type `continue` again.

## Your own debugger

The debugger is a file written in Cesia, `src/tools/debugger.ce`, and `--debugger` takes another one as well, a file of
your project: `cesia run --debugger mydebug.ce app.ce`. It has a function `OnStop(stop)`, which runs at each stop and gives
what to do next: `"continue"`, `"step"`, `"next"` or `"out"`.

```cesia norun
use std/debug
use std/io

defn OnStop(stop)
  io.Print("$(stop.File):$(stop.Line) $(stop.Reason)")
  if stop.Reason == "start"
    debug.SetBreak("app.ce", 12, "n > 100")
  else
    io.Print(debug.Eval("n * 2", stop.Frames[1]))
  end
  "continue"
end
```

A stop holds:

| Field | What it is |
|---|---|
| `File`, `Line` | where the program stopped |
| `Reason` | `"start"`, `"break"`, `"step"` or `"error"` |
| `Frames` | the frames, from the innermost: each has `Function`, `File`, `Line` and `Vars`, each variable a `Name` and a `Value` |
| `Fiber` | 0 for the main program, else the number of the fiber that stopped |
| `Error` | the message of the error for a stop on an error, else missing |

The functions of [std/debug] do the rest: [debug.SetBreak], [debug.ClearBreak] and [debug.Breaks] for breakpoints,
[debug.Watch], [debug.Unwatch] and [debug.Watches] for the watches, which live with the program from one stop to the next;
[debug.Eval] runs code in a frame or at the file level of the main package, the engine of the prompt too; [debug.Reload]
reloads what changed; [debug.ReadLine] reads a line, edited on a terminal, and [debug.Complete] says whether code is whole.
They need the `debug` permission, which `--debugger` and `--repl` give by themselves.

The debugger runs inside the program, before it, and its own code never stops. A debugger is no library: it loads only
with `--debugger`, and a program run without it pays nothing for it.

## Speed

A program under a debugger runs as fast as without one while nothing is asked of it: only a line with a breakpoint, and
every line while you step, goes to the debugger. Hot code still becomes native code, calls included; a function whose code
holds a breakpoint stays in the interpreter, and at each stop native code goes back to the interpreter and becomes native
again once hot, so the results are the same as without the debugger. A stop on an error inside native code shows the
variables of the frame that runs it, but not those of the calls native code made inside it.

You can look inside a running program. The next chapter, [C and C++](c.md), calls the libraries of the system from Cesia.
