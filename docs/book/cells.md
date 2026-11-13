# Cells

A *notebook* is code cut into *cells*, pieces that run one at a time, each with its result under it: Jupyter and Pluto.jl
are notebooks. In Cesia a notebook is a normal `.ce` file, cut by comments, and [std/cells] runs it: cells that depend on a
cell run again when it does, as in a *reactive* notebook. The file stays a program: `cesia run` runs it from the top, and
gives what the cells give. Cemacs draws the results under the cells; this page is the engine under it, for any tool.

## A file of cells

A line that holds only a comment starting with `%%` starts a cell, and the rest of the comment is its title. The lines
before the first one are the first cell, usually the uses:

```cesia norun
use std/io
use std/list

(* %% Data *)
n = 1000
xs = [i * i for i in 1..n]

(* %% Mean *)
mean = list.Mean(xs)
io.Print("mean of $n squares")
mean
```

For `cesia run`, `cesia check` and `cesia fmt` a marker is a comment like any other: `cesia fmt` leaves it on its line.

[cells.Parse] gives the cells of a source, each with its Title, its first and last lines, From and To, counted from 1,
and its Source, the marker with it, so that line k of a cell is line `From + k - 1` of the file. When a marker opens the
file, the first cell is empty, with To = From - 1, so that the cell of the uses is always the first one:

```cesia
use std/cells
source = "use std/io\n(* %% Data *)\nn = 3\n(* %% Twice *)\nio.Print(n * 2)"
[[c.Title, c.From, c.To] for c in cells.Parse(source)] -->
```

## What a cell reads and defines

A cell *defines* what its top-level statements give a name: `x = ...`, `[q, r] = ...`, its functions, structs and
interfaces, and the names of its uses. It *reads* the names that its code and the bodies of its functions use without
defining them; a parameter or a local variable of a function is no read. [cesia.Reads] finds them, with the compiler's own
resolver, the code that decides what a name means when a program runs: it is exact by construction, and its tests compare
it with what `cesia check` says of every test program of Cesia, whole and cut in two.

```cesia
use std/cesia
[r.Name for r in cesia.Reads("defn f(a)\n  a * rate\nend\ntotal = f(k)").Value] -->
```

[cells.Analyse] gives, for each cell, its Defines, its Reads and its Errors, each error with its Line and Column in the
file. Three rules make a file mean the same thing as cells and as a program:

1. A name is defined by one cell only. Two cells that define `x` are both in error, each naming the other.
2. A cell reads only names that the cells above it define. A cell that reads a name defined below says which cell to
   move up. So there is no cycle: the order of the file is an order to run them in.
3. A name that no cell defines is the error `Name "k" doesn't exist.` where it is read, and a package of `std/` named
   without its use says which use to write in the first cell.

Two more follow from them. A method goes in the cell of its struct, as it goes in the package of its struct. And a loop
or a block of a cell that gives a value to a name another cell defines is an error: under `cesia run` the whole file is
one scope, and the loop would change that name for the cells below. The variable of a `for` loop, and a name that a cell
gives a value only inside a block, stay in their cell: a cell below that reads one is told to give it its value at the
top of its cell.

```cesia
use std/cells
a = cells.Analyse(cells.Parse("(* %% A *)\nx = y + 1\n(* %% B *)\ny = 1"))
a[2].Errors[1].Message -->
```

## What runs again

After cell c runs, or is edited and run, [cells.ToRun] gives the cells to run, in file order: c, then each cell that
reads, directly or through other cells, a name c defines. The others keep their results. The first cell, the uses,
runs them all again.

```cesia
use std/cells
a = cells.Analyse(cells.Parse("(* %% A *)\nx = 1\n(* %% B *)\ny = 2\n(* %% C *)\nz = x + y"))
cells.ToRun(a, 2) -->
cells.ToRun(a, 3) -->
```

This is the model of Pluto.jl, whose README says: "When you change a variable, Pluto automatically re-runs the cells
that refer to it", and "deleted code leaves no trace". A deleted cell's names are forgotten with [cells.Forget], and the
cells that read them show the third rule's error. One difference: Pluto lets cells sit in any order, and Cesia doesn't,
by the second rule, so that `cesia run` computes what the cells show.

A cell run again repeats what it does besides its value: it prints again, writes its files again. Nothing hides that: a
cell that must write once is better run once, on purpose.

## The session

[cells.Session] starts a session on a file: one Cesia process, `cesia run --cells file.ce`, that runs none of the file and
waits for cells. [cells.Run] gives it one cell and waits for it: an Ok with Output, the lines it printed, Value, what its
last expression shows, Error, or missing, with the Line of the file and the Text of the error as `cesia run` shows it,
and Seconds, the time it ran. Before a cell runs, the names it defines are forgotten, so that a cell that fails leaves no
old value behind. A cell whose From is 0 is code typed at a prompt beside the cells, which no line of the file holds:
its errors name `<prompt>`.

```cesia norun
use std/cells
use std/io
use std/result
use std/sys

defn Main()
  cs = cells.Parse(sys.Read("mean.ce")?)
  s = cells.Session("mean.ce")?
  for c in cs
    r = cells.Run(s, c)?
    io.Print(r.Output, " ", r.Value)
  end
  io.Print(cells.Variables(s)?)
  result.Ok(missing)
end
```

The cells run at the file level, as the prompt of `cesia run --repl` runs code: each sees the names the cells before it
defined, and the uses written above it. They run as the program would, not under the hook of the debugger, which costs
about ten times: fib(35) in a cell takes 56.8 ms, the same file under `cesia run` 56.8 ms too (medians of 21 runs). Their
errors and the calls that lead to them name the file and its lines.

A session has only the permissions of its `allow`, as `--allow` takes them: `cells.Session("mean.ce", allow = ["read"])`.
The program that starts it needs the `exec` permission of this `cesia`, [cesia.Binary].

What a value shows:

| Value | Shows |
|---|---|
| a graph of [std/plot] | `{Kind: "graph", Scene, Key}`: its scene, [plot.Scene] at the width Run gives, 640 pixels by default, and 400 high; a graph that std/plot can't draw is the cell's error, with std/plot's message |
| a frame of [std/frame] | `{Kind: "table", Columns, Rows, Count}`: its first 20 rows, as texts, and its count |
| an array or a matrix | `{Kind: "array", Shape, Rows}`: its shape and its first 10 × 10 values, as texts |
| a struct of at most 20 fields, as a `stats.Test` | `{Kind: "table", Columns, Rows, Count}`: a row for each public field, its name and its value as a text, cut at 80 characters and made from no more of a long list than that shows, so a model of $10^6$ rows shows at once; an `Ok` of a struct shows the struct |
| anything else | `{Kind: "text", Text}`: its text, as `io.Print` writes it |

Before each cell runs, [std/random] starts again from the seed of the session and the title of the cell, as `cesia
test` starts each test: a cell run again draws the same numbers, whatever ran before it, a change in one cell changes
no other's draws, and [cells.Html] gives the numbers Cemacs showed for the same seed. A cell renamed draws other
numbers; `cesia run` on the file, one stream from the top, draws other numbers than its cells.

Values stay in the session: [cells.Variables] gives each name's Name, Type, Size and Preview, a few texts, and never
copies a large array. The session keeps the graphs of its last 64 runs, and [cells.Scene] draws one again at another
width, by its Key, for a pane that changed its width. [cells.Rows] gives the rows from one to another of a frame, a matrix or a list, as texts, so that a
viewer reads a large value one screen at a time.

[cells.Stop] stops the cell that runs: its fiber is cancelled at its next wait or checkpoint, its Run gives the error
`Stopped.`, and the session and the names defined before stay. A session that doesn't answer within 2 seconds, as a cell
inside one long native call, is ended and a new one starts: the session that Stop gives then has Restarted true, and the
cells run again from the top.

## A page to share

[cells.Html] runs every cell of a file in a new session, from the top, and gives one HTML page: each cell's title, its
code colored as the docs color it, what it printed, its value as a graph in SVG, a table or a text, or its error. The page needs no other
file and no script, and shows what `cesia run` computes, not the state of an editor.

```cesia norun
use std/cells
use std/result
use std/sys
sys.Write("mean.html", result.Unwrap(cells.Html("mean.ce")))
```
