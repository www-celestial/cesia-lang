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
errors and the calls that lead to them name the file and its lines. A cell run again that defines a function with the
same code as before keeps the machine code the JIT made with it: the solve cell of a Lorenz notebook, `lorenz` defined
again and solved again, takes 2.2 ms instead of 22.7, as [How Cesia works](internals.md#calls-through-a-value) says;
a function that changed, that reads a name of a cell run again since, as `rho` once its cell was edited, or that calls
another of its cell, is made again.

A session has only the permissions of its `allow`, as `--allow` takes them: `cells.Session("mean.ce", allow = ["read"])`.
The program that starts it needs the `exec` permission of this `cesia`, [cesia.Binary].

What a value shows:

| Value | Shows |
|---|---|
| a graph of [std/plot] | `{Kind: "graph", Scene, Key}`: its scene, [plot.Scene] at the width Run gives, 640 pixels by default, and 400 high; a graph that std/plot can't draw is the cell's error, with std/plot's message |
| an animation of [plot.Frames] | `{Kind: "graph", Scene, Key, Frames, Fps}`: the scene of its first frame, the number of its frames and their rate |
| a 3D graph of [plot.Surface] or [plot.Line3] | `{Kind: "graph", Scene, Key, View}`: its scene, and `View`, the `[az, el]` of its code |
| a frame of [std/frame] | `{Kind: "table", Columns, Rows, Count}`: its first 20 rows, as texts, and its count |
| an array or a matrix | `{Kind: "array", Shape, Rows}`: its shape and its first 10 × 10 values, as texts |
| a struct of at most 20 fields, as a `stats.Test` | `{Kind: "table", Columns, Rows, Count}`: a row for each public field, its name and its value as a text, `value.Text(v, 80)`, which makes no more of a long list than its 80 characters, so a model of $10^6$ rows shows at once, and a matrix of more than 1000 values as its size; an `Ok` of a struct shows the struct |
| anything else | `{Kind: "text", Text}`: its text, as `io.Print` writes it, cut at 20,000 characters by `value.Text` |

Before each cell runs, [std/random] starts again from the seed of the session and the title of the cell, as `cesia
test` starts each test: a cell run again draws the same numbers, whatever ran before it, a change in one cell changes
no other's draws, and [cells.Html] gives the numbers Cemacs showed for the same seed. A cell renamed draws other
numbers; `cesia run` on the file, one stream from the top, draws other numbers than its cells.

Values stay in the session: [cells.Variables] gives each name's Name, Type, Size and Preview, a few texts, and never
copies a large array: each text is made by `value.Text(v, 80)`, which stops at 80 characters, so a session that holds a
model of $10^6$ rows answers in a tenth of a millisecond. The session keeps the graphs of its last 64 runs, and [cells.Scene] draws one again at another
width, by its Key, for a pane that changed its width, another frame of an animation, `frame = k`, or a 3D graph turned
to another view, `view = [az, el]`: an editor asks for each frame as it shows it, so that an animation never crosses the
pipe whole, and a frame of the Lorenz curve, 5,000 points, comes back in about 10 ms; it asks for each view as a 3D graph
turns, and a surface of 100 by 100 quads comes back in about 14 ms, the places of its points on the screen, its quads in
the order to draw them. The session reads its answers by chunks and joins each line once, so a long answer costs its
length, not its square. [cells.Rows] gives the rows from one to another of a frame, a matrix or a list, as texts, so that a
viewer reads a large value one screen at a time.

[cells.Stop] stops the cell that runs: its fiber is cancelled at its next wait or checkpoint, its Run gives the error
`Stopped.`, and the session and the names defined before stay. A session that doesn't answer within 2 seconds, as a cell
inside one long native call, is ended and a new one starts: the session that Stop gives then has Restarted true, and the
cells run again from the top.

## Sliders

A *slider* is a bar with a knob that you drag to change a number. In a cell of its own, each line
`name = cells.Slider(value, min, max)` gives a name a number that an editor moves: Cemacs draws the slider under the line,
and a move writes the new number in the file, then runs again only the cells that read that name.

```cesia norun
use std/cells
use std/ode
use std/result

(* %% Parameters *)
rho = cells.Slider(28.0, 0.0, 50.0, step = 0.5)
n = cells.Slider(3, 1, 10)

(* %% Lorenz *)
lorenz(t, y) = [10.0 * (y[2] - y[1]), y[1] * (rho - y[3]) - y[2], y[1] * y[2] - 8.0 / 3.0 * y[3]]
s = result.Unwrap(ode.Solve(lorenz, [0.0, 50.0], [1.0, 1.0, 1.0]))
```

The file is the truth: after a move, `cesia run`, the window and the page of [cells.Html] read the same number. A slider is
a plain function call, and under `cesia run` [cells.Slider] checks its numbers and gives the value:

```cesia
use std/cells
cells.Slider(28.0, 0.0, 50.0, step = 0.5) -->
cells.Slider(3, 1, 10) -->
```

Two rules, besides the three of the cells, make a slider something an editor can move without guessing:

4. A cell with a slider holds only sliders, one a line, and comments. A slider that sat beside other code would make its
   cell run again at each move, and what that code computes would go stale.
5. A slider takes numbers written in the file, possibly negative, as `28.0`, `-1.5` or `1e-3`: an editor rewrites the
   value's number, and draws the slider before anything runs. `cells.Slider(1.0, 0.0, top)` is the error
   `cells.Slider takes numbers written in the file, not expressions.`

[cells.Analyse] finds the sliders through the name that the first cell's `use std/cells` gives, `cells` or the name
after `as`, and gives each cell its Sliders: each with its Name, its Line, the Column and the End of the value's number
on that line, counted from 1, its Value, its Min, its Max and its Step: Ints for a slider of Ints, else Floats, as
`cesia run` reads them.

```cesia
use std/cells
a = cells.Analyse(cells.Parse("use std/cells\n(* %% P *)\nrho = cells.Slider(28.0, 0.0, 50.0, step = 0.5)"))
a[2].Sliders[1] -->
cells.Analyse(cells.Parse("use std/cells\n(* %% P *)\nrho = cells.Slider(60.0, 0.0, 50.0)"))[2].Errors[1].Message -->
```

The numbers are checked in both places, with the same text: [cells.Slider] panics and [cells.Analyse] gives the error
when a number isn't finite, when the min is not below the max, when the value is outside them, when the min, the max or
the step has more than 18 decimals (the text of a position has theirs), when max - min is too wide for a number (an Int
holds 63 bits), when the step is not above 0 or is wider than max - min, and past $10^6$ steps. The step defaults to (max - min) / 100, with two more decimals than
min and max have, so that 0.0 to 0.7 steps by 0.007; or to 1 when value, min and max are Ints, and such a slider gives
Ints. A value written off the steps stays as it is until it moves.

A slider's positions are min + k × step, for k a whole number, computed and never added up, and the last one is the
largest at most max, as an HTML range input has it. [cells.Snap] gives the position nearest a number, and steps more
when asked: its Text is what the file writes, with the decimals of min and step, so that steps of 0.1 write `0.3` and not
`0.30000000000000004`, and its Value is the number `cesia run` reads back from that text.

```cesia
use std/cells
s = {Value: 0.0, Min: 0.0, Max: 1.0, Step: 0.1}
cells.Snap(s, 0.31) -->
cells.Snap(s, 0.31, steps = 1).Text -->
```

[cells.Set] gives a slider its new value in a session: snapped as Snap does, checked against the slider's min and max,
and given to the name **in place**. A cell run again first forgets the names it defines, so that a function of another
cell that reads one of them would find it without a value until its own cell ran again; Set changes the number the name
holds, and the function reads the new one at once. The machine code of a loop that reads it reads each new number from a
slot, so it keeps its code: a step of the slider of `rho` in the Lorenz notebook, Set then the solve cell run again,
takes 2.6 ms instead of 24, as [How Cesia works](internals.md#calls-through-a-value) says. Set gives the value and ToRun, the cells to run again: those that
read the name, directly or through other cells, in file order. The slider's own cell is never among them, since it holds
nothing else.

```cesia norun
use std/cells
use std/io
use std/result
use std/sys

defn Main()
  cs = cells.Parse(sys.Read("lorenz.ce")?)
  a = cells.Analyse(cs)
  s = cells.Session("lorenz.ce")?
  for c in cs
    cells.Run(s, c)?
  end
  moved = cells.Set(s, a, "rho", 31.5)?
  for i in moved.ToRun
    cells.Run(s, cs[i])?
  end
  result.Ok(missing)
end
```

Set is an Err for a name that is no slider of the analysis, a value that is no finite number or is outside the slider's
min and max, and a session that has no value for the name yet: the slider's cell runs first, as [cells.ToRun] gives it.

The page of [cells.Html] shows each slider under its cell, with its value as the file writes it, on a range that doesn't
move: the page has no script, and nothing there could run again what reads it.

What a slider trusts is little. [cells.Analyse] reads the file's text without ever panicking: numbers that a slider
couldn't count or write are errors of the file, as above. The session takes a set only for a name that holds a number
already, and gives it only a finite number: never a function, whose calls may have been compiled with it, nor a text. [cells.Set] checks the name,
the number and the range before it asks. What an editor writes in the file is the editor's to check: see
[Cemacs](https://www-celestial.github.io/cemacs/cells.html).

## A page to share

[cells.Html] runs every cell of a file in a new session, from the top, and gives one HTML page: each cell's title, its
code colored as the docs color it, what it printed, its value as a graph in SVG, a table or a text, or its error. The page needs no other
file and no script, and shows what `cesia run` computes, not the state of an editor. An animation starts paused on its
first frame, under a box *Play* that plays it and pauses it, by CSS alone, as [Graphs](graphs.md#in-a-web-page-frames-of-css)
tells: the box is a check box, which Tab reaches and Space checks. A 3D graph shows at the view of its code, and its
SVG has a `<title>`, as `Surface, 61 × 61 points, z from −0.301 to 0.584`, which a screen reader says.

```cesia norun
use std/cells
use std/result
use std/sys
sys.Write("mean.html", result.Unwrap(cells.Html("mean.ce")))
```
