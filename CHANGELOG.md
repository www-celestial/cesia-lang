# Changelog

## 1.3.0

### Language

- An `if` with nothing before its `else` is an error when the file loads, which says to write the value in parentheses or
  on a line of its own: a value that starts with a minus sign right after the condition was read as part of it, so that
  `if x < 0 -1 else 0 end` meant `if x < 0 - 1 (nothing) else 0 end`, and gave `missing` where -1 was meant, with no
  error. Cesia's own code held three such mistakes, fixed below; an `if` left empty on purpose is written with `not`.
- `x!` unwraps a result: the value of an Ok, and an Err is a bug that stops the fiber at the `!`, with the text of its
  error, as `result.Unwrap(x)` does, which stays its plain form. It never leaves the function, so it goes at the top of
  a file too, where `?` can't: `db = sql.Open("sqlite::memory:")!`. It follows its value with no space, as `?` does, and
  chains: `f(x)!.Name`, `xs[1]!`, `g()!(2)`; `a!=b` is still not-equal, `a! == b` unwraps then compares. A value that
  is no result is the type error of `?`. It makes no call, and machine code reads the Ok as a field: a loop of 10
  million unwraps and adds takes 223 ms in the interpreter and 32 ms as machine code, against 746 ms with
  `result.Unwrap`, which stays interpreted; with arithmetic around it, 787 and 234 ms against 1432 ms (medians of 21
  runs). `cesia check` gives `f(x)!` and `f(x)?` the type before the `!` of f's result, `Int` for `Int!`, and says when
  it doesn't fit. `cesia build --target wasm` compiles it, with the same output and the same errors as `cesia run`. The
  book and the examples of std/ write `x!` where they wrote `result.Unwrap(x)`, 198 places, and the chapter Errors tells
  it beside `?` and `match`, in English and in French.
- `x then f(a)?` is `f(a, x)?`, and `x then f(a)!` is `f(a, x)!`: a `?` or a `!` that ends the right side of `then`
  comes after the pipe, with `it` too, `x then f(it, a)?`. It called `f(a)` without the piped value, and failed with
  « f needs the argument b »; and `x then f(a, it)?` made the function `it -> f(a, it)?`, whose `?` left that hidden
  function and not the one that held it, so that its Err went on as a value.

### Shapes

- `std/check`: shapes of what comes from outside, `check.Text(1, 200)`, `Int`, `Float`, `Money(2)`, `Bool`, `Date`, `Time`, `Email`,
  `Id`, `Url`, `OneOf`, `List`, `Record`, `Secret`, with `optional` and `default`. `check.Read` gives the value made clean or
  a map of each wrong field to its message; `check.Out` keeps the declared fields only; `check.Masked` hides secrets for a
  log; `check.Schema` gives the JSON Schema. Pure Cesia, so a page and its server share one shape.

### Servers

- `http.Route` takes `stream`, the most bytes the body of its requests may hold: a body too large for one read, or than
  `maxBody`, comes to its handler in pieces as it reads them, `r.Read()` giving each and `r.Size` the length, so that an
  upload of a file is never whole in memory; a body larger than `stream` is a `413` before the handler, a client that
  sent `Expect: 100-continue` is told to go on at the first read only, and the connection closes after the response.
  Each piece has the request's timeout, and the whole a second more for each 64 KiB. A route without it, and every
  program that served before, reads as before (`tests/net/http-pieces.ce`).
- `http.Fetch` takes `peer`, a function of the address the connection reached, run before any byte goes, TLS's too: an
  `Err` it gives closes the connection and is Fetch's. A program that asks an address it was given checks the very
  address a name was found at, with no second lookup (against server-side request forgery and DNS rebinding).
- `tls.Client` takes `ca`, the path of a PEM file of the authorities to trust instead of the system's, as a company's own.

### Files

- `sys.Copy` copies a file with its mode and its times, as `cp -p`, refusing a folder or the same file under another
  name before a byte is written; `sys.Chmod` and the new Mode of `sys.Stat` give and read the permission bits;
  `sys.SetModified` sets the time of a change, as `touch`; `sys.Symlink`, `sys.Link` and `sys.ReadLink` make and read
  links. Everything a file manager needs, as the folders of Cemacs.
- `sys.RemoveTree(path)` deletes a folder and all it holds, as `rm -r`, never following a link: one inside goes
  itself, and a path that is one goes alone. It walks by descriptors, each folder opened from the one above it and
  checked to be the folder seen there, so that a folder swapped for a link while it runs is never entered, as Cemacs's
  folders need to delete for good; its first failure is an Err that names the file, and a tree of any depth keeps at
  most 32 folders open. On Windows it walks by paths and never enters a link or a junction. `cesia pkg`, `cesia
  upgrade` and the Temp folder of `cesia test` use it, the last saying what it couldn't remove where it said nothing.
- `sys.CopyTree(from, to)` copies a folder and all it holds, as `cp -rp`: files with their modes and times, links made
  again, never followed, the modes and times of the folders set last, the deepest first. A folder at `to` takes it in,
  each file or link replaced whole through a name of its own. It walks by descriptors on both sides, as
  `sys.RemoveTree`, each folder of the copy the person's alone while it fills, so that a folder swapped for a link while
  it runs, in the source or in the copy, leads no read and no write out of them: the race that let a copy of Cemacs's
  folders overwrite 2886 files of 3000 of another folder. A pipe, a device or a socket, a link where a folder is asked,
  and a copy into its own source are each an Err. It needs read on `from` and write on `to`.
- `sys.Copy(from, to, new = true)` makes the copy only new, as `O_CREAT | O_EXCL | O_NOFOLLOW`: a file or a link at `to`,
  even one that leads nowhere, is an Err and stays as it was, so no one can put a link there for the copy to write
  through. Without it, a file at `to` is replaced, as before.
- `sys.Write(path, text, new = true)` makes the file only new, as `sys.Copy` with `new = true`: a file or a link at
  `path`, even one that leads nowhere, is an Err and stays as it was, so the new file of a save can't be a link someone
  put at its name first; the write permission is then on `path` itself. It goes with `sync`, `mode`, `group` and
  `private`. Without it, a file at `path` is replaced, as before.
- `sys.Write(path, text, mode = M, group = G)` gives the file the mode M, exactly, the umask aside, and the group G, as
  `chgrp`, on its descriptor once it is open, before its old text is cut and the new one is in: an editor's save, a new
  file renamed over the old one, keeps the old one's rights with no moment under others and no act by its path. A group
  the person is not in is an Err, and a file that was there keeps its text. A file it makes so is its owner's alone,
  0600, until it has them, so no one of the person's own group can open it on the way and read the text through it. `sys.Stat` gives `Owner` and `Group`, the
  numbers of the file's user and group; 0 on Windows, as in Python and Node. A write with none of `mode`, `group`,
  `new` and `private`, under no folder of `write=`, costs what it did before them, within 1 %: 1.86 µs a call to
  `/dev/null`, 1.84 before them (medians of 21 runs, alternated).

### Texts

- `text.ByteFindAny(bytes, from, s, not = false)` gives the byte position of the first byte of `s` from byte `from` on
  that is one of the bytes of `bytes`, or with `not = true` the first that is none of them, or missing, as Go's
  `strings.IndexAny` and C's `strcspn` and `strspn`: a lexer skips a word, a run of spaces or the inside of a text at
  once. It reads eight bytes at a time through a table of the 256 bytes, made once for each of the last eight sets: a
  run of 1 MB in 0.86 ms, where a loop of `text.Byte` takes 45 ms, and a call on a word of 5 bytes with a set of 63 in
  69 ns, where `text.ByteFind` of one byte as near takes 125 (medians of 21 runs). It counts against `--limit steps` the
  bytes of its set and those it read. In a call, `not =` names an argument, where it was an error.

### Science

- `std/math` has the rest of the functions of one number of numpy, R and MATLAB: `Log10`, `Log2`, `Log1p`, `Expm1`,
  `Cbrt`, `Sinh`, `Cosh`, `Tanh`, `Asinh`, `Acosh`, `Atanh`, `Hypot`, `SinDegrees`, `CosDegrees`, `TanDegrees`,
  `Radians`, `Degrees`, `IsNan`, `IsInf`, `IsFinite`, `Clamp`, `Step`, `LogSumExp`, `Epsilon` and `NextAfter`, and
  the constants `E`, `MaxFloat`, `MinFloat`, `MaxInt` and `MinInt`; `num.ReplaceNan` fills the NaN and missing values
  of an array. Each works on a number and on an array, element by element, and gives the bits of numpy where numpy
  calls the C library too. `math.Cbrt` is correctly rounded, where the C library's cube root is up to 3 ulps away
  (`np.cbrt(27.0)` is `3.0000000000000004`, `math.Cbrt(27)` is `3.0`), and as fast; the degrees are reduced exactly,
  so that `math.SinDegrees(180)` is `0.0`. Machine code calls the C library for `Log10` to `Atanh` and `Hypot` itself.
  The book's chapter Numbers cleans a weather station's log with them, beside Python, R and MATLAB, and gives the
  precision of each against mpmath, numpy, R and Octave.
- `std/constants` holds the 355 physical constants of CODATA 2022 by their names in NIST's table: `constants.Value`,
  `Unit`, `Uncertainty` and `Find`, the bits of `scipy.constants`.
- Graphs are black on white, their texts in JetBrains Mono, the font of the code in Cemacs, which draws them as
  `plot.Save` writes them: the layers without a color are black, lines told apart by their dash, solid, dashed, dotted
  and dash-dot in turn, points by their shape, circle, square, triangle and cross, bars by their grey, the ink at 100,
  60, 40 and 30 %; the grid `#d0d0d0` and the lines 1 pixel wide by default, `width = 1.5` still taken. `color =` gives
  any layer a color of its own, as before; heatmaps and surfaces keep viridis and RdBu. The font being monospaced, a
  text is 0.6 em a column, none for a combining mark, two for a wide character of East Asia: the table of the widths of
  Noto Sans and `tools/plot-font.ce` are gone. A graph that drew draws the same data; its look alone changed.
- `plot.Text(x, y, texts, color, size, anchor, dx, dy)` writes texts on a graph, each beside its point of the data, as
  the hour beside each point of a curve: a layer that follows the axes, cut to the plot, at most 100,000 texts. The SVG
  writes `"` as `&quot;` too, with `&`, `<` and `>`, in every text of the program.
- `plot.Of(..., note = "lat: 40.76\nlon: -73.98", noteAt = "top left")` puts a box of text at a corner of the plot, a
  line for each line of the note, on the paper, a new color of scenes that a back-end paints as its ground; the SVG
  keeps the spaces of its texts, `xml:space="preserve"`, as std/plot measures them.
- `plot.Of(..., legend = "ends")` names each line at its end, its label right of its last point in the plot, in its
  color, the labels moved apart a line when two would overlap, the margin grown to hold them; the box stays the default.
- `plot.Of(..., xticks = list.Range(0, 360, step = 90), xlabels = ["N", "E", "S", "W", "N"])`, and `yticks`, `ylabels`:
  the ticks of an axis chosen, in place of those of Talbot, Lin and Hanrahan, and their labels, as many as the ticks, or
  the numbers written as the computed ones are; a log axis takes ticks above 0. Without them, nothing changes.
- `plot.Of(..., polar = true)` draws a graph in a circle, as a compass: x an angle in degrees, 0 at the top, clockwise,
  and y the distance from the center, `ylim = [90, 0]` putting 90 at the center and 0 on the rim; rings at the ticks of
  y, rays every 30 degrees or at `xticks`, their labels outside the rim; lines, points, texts and rules, cut at the rim.
  A polar graph is square, 500 by 500 by default; with a 3D graph, log axes or `xlim`, it is an Err.
- A graph under a cell keeps the shape of its own size: `cells.Run` and `cells.Scene` draw it at the width asked, or its
  own when it is less, and as high as its shape asks, 400 for 640 by default and square for a polar graph, where every
  graph was 400 pixels high; `plot.Scene(g, width, missing)` gives that size to any back-end.
- `plot.Rule(x = 180, label = "S")` and `plot.Rule(y = 0, dash = "dashed")`: a line of reference across the plot,
  upright or across, grey unless a color is given, its label at its end; the range of its axis grows to hold it.
- `cells.Show(x)` shows a value under the cell that runs, at its place among what the cell prints, as `display` does in
  Jupyter: two graphs, or a table then a graph, in one cell. `cells.Run` gives them in its new Shown, each with its place
  among the lines of Output; each graph has its own Key for `cells.Scene`; the page of `cells.Html` shows them in order.
  Out of a session, as under `cesia run`, Show only gives its value.
- The inputs of a form in a cell, written as a slider is: `cells.Choice(value, options)`, a value among options, texts
  or finite numbers, at most 1,000; `cells.Check(value, label = missing)`, `true` or `false`; `cells.Field(value)`, a
  text or a number as written; `cells.Date("2026-11-23")`, the date of std/date of a day written `YYYY-MM-DD`. Each gives
  its value under `cesia run` and panics on one it doesn't take, and `cells.Analyse` says the same of the file in the same
  words, with the errors of the cell: a value written as an expression, `$name` or `$(...)` in a text, two inputs of
  one name, code beside them. Analyse gives each cell its new Inputs, the sliders among them, each with its Name, Kind,
  Line, the Column and End of its value, Value, and Min, Max and Step, Options or Label; Sliders stays as it was.
- `cells.Snap` gives the value of any input as the file writes it, a text in quotes with `\`, `"`, ends of line, tabs
  and carriage returns escaped and `$` written `$$`, so that it reads back as the same text and never as code; for a
  choice the option `steps` further, for a date the day `steps` days further. `cells.Set` gives any input its new value
  in the session in place, checked as Analyse checks it, and gives Text, that value as the file writes it, besides Value
  and ToRun, for a slider too; its Err for a name that is no input says `is no input of the cells`. The session reads the
  value of a set from its text, never runs it, and gives it only to a name that holds a value of the same kind.
- The page of `cells.Html` shows each input as the file writes it, in a box that doesn't change: a list of its one value,
  a check box, a text box or a date box, its texts escaped.
- `cells.Rows(session, name, first, last, sort = missing, filter = missing, find = missing)` sorts a table by a column,
  `{Column, Descending}`, numbers as numbers, NaN and missing last both ways, equal rows in their order, and keeps the
  rows that hold each word of a filter in any of their cells, ASCII letters in either case, never read as a pattern; both
  in the session, which keeps the order for the next screen. Rows gives Total and Positions, the place of each row in the
  value, and with `find` the place of a position in the order. An ask gives at most 1,000 rows, 20,000 cells and 256
  columns. A sort of a million rows by a column of floats takes 0.24 s, 100 of them anywhere 0.48 ms.
- A table that a run shows, a frame, a struct or a matrix, has a Key, as a graph has, and the session keeps it with the
  last 64 graphs: `cells.Rows` reads it again by that key, so a value that only a cell's last expression holds scrolls
  too. A list of maps or structs shows as a table, its columns the keys of the first, where it showed as a row of texts.
- `cells.Totals(session, name, filter = missing)` totals each column of a table of the session over every row its filter
  keeps, not only those a screen shows: the values that aren't missing, the missing ones, NaN among them, and for a
  column of numbers their sum, mean, least and greatest, computed in the session on whole columns. The totals of a
  million rows of 3 columns take 65 ms there.
- `cells.Tables(cells, i)` reads the tables that a cell writes as values, a list of maps or `frame.Of` of lists, each
  value a number, a text, true, false or missing written there, with where the file writes each, and runs none of it;
  `cells.Edit(table, row, column, words)` makes words typed the new value of one, checked for the kind of its column, a
  number written as a Float in a column of Floats, a text in quotes, with the place its text takes in the file: an
  editor edits a table as it edits an input, and the file stays the truth.
- `plot.Scene(..., mark = [i, n])` and `cells.Scene(..., mark = [i, n])` ring point i of each line, points or texts of n
  points at its exact place, even one that M4 left out, write its values in a box beside it, and give Points, the places
  on the screen of those layers' points with their positions: the row of a table of n rows and its point on the graph of
  the same cell, which Cemacs links.
- `plot.Scene(..., xlim, ylim, points = false)` and `cells.Scene` with the same draw a graph zoomed or moved without
  changing it, and with `points = true` give the points of every line, points and texts, their values, `Values`, and
  `Axes`, how the data meet the pixels, so that an editor shows the values under the mouse and zooms about it, as
  Cemacs does; each entry of `Points` gives its `Count` and its `Values`, with a mark too. `cells.Svg(session, key)`
  gives the SVG of a graph that the session keeps, as `plot.Save` writes it. A first graph is drawn as fast: 7.01 ms
  for a scene of a line of 1,000 points, the whole run, against 7.00 (medians of 21 runs, alternated).
- The page of `cells.Html` draws a table as Cemacs does: a thin frame and the rule under its header in ink, lighter
  lines between its rows and columns, its header bold, a number on the right with its decimal point under those of its
  column, a text on the left, every text escaped.
- `cells.Html(path, allow = [], code = true)`: with `code = false`, the page leaves out the code of every cell, and the
  cells that show nothing, as Cemacs shows a file of cells as an app after `C-c e t`; without it, the page is the same as
  before, to the byte.
- `std/mesh` makes solid parts of triangles: `mesh.Box`, `mesh.Cylinder`, `mesh.Cone` and `mesh.Sphere`, closed, their
  corners counterclockwise from outside, 48 segments around by default; `mesh.Move`, `mesh.Turn` (degrees around an axis,
  the right hand's rule, Rodrigues' formula), `mesh.Scale` (a mirror turns the corners back) and `mesh.Merge`;
  `mesh.Normals` and `mesh.Bounds`; `mesh.Of` for your own matrices of points and triangles, checked. `mesh.ReadStl`
  reads binary and text STL, each corner at one place made one point; a file from anyone is checked before any memory is
  taken: a binary file must be 84 + 50 n bytes for the n its header counts, a text must follow the grammar of facets, a
  NaN, an infinity or more than 2,000,000 triangles is an Err, and under `--limit memory=` the reading stops in its
  fiber. `mesh.WriteStl` writes binary, or text with `ascii = true`; read back, a mesh of floats of 32 bits is the same.
  `text.Numbers(kind, bytes)` and `text.FromNumbers(kind, numbers)` read and write the numbers that the bytes of a binary
  file hold, little-endian, `u8` to `f64`. 99,224 triangles read in 186 ms from binary, 1.55 s from text.
- `plot.Mesh(m, color, edges, label)` draws a mesh in a 3D graph, lit and shaded flat: ambient 0.3, Lambert's diffuse
  0.7 and Blinn's highlight 0.2, from `light`, or from the eye turned 30 degrees up when the graph gives none; the faces
  turned away from the eye left out, the parts ordered whole by planes between them, and of two convex parts that cross,
  as a shaft through a wheel, one cut by the planes of the other, once, when `plot.Of` makes the graph. `edges = true`
  draws the edges of a drawing: those where faces meet at more than 30 degrees, the outline and the border, each hidden
  where a nearer face covers it. A test checks against a ray cast from the eye that the part seen at points of the
  screen is the nearest, at random views of random parts that cross. At most 200,000 triangles a graph, about 70 bytes
  of SVG each triangle drawn.
- `plot.Of(..., light = [x, y, z], perspective = true, aspect = "equal", axes = false)`: a light fixed along the axes;
  a pinhole camera, the eye 4 radii of the box away; a unit as long on each axis, the default with a mesh, or the box of
  1 by 1 by 0.75; no box, grid or ticks. A surface given `light` or `perspective` is shaded and seen through the camera,
  its quads in the order of McMillan for a projection from a point; without them it is the same bytes as before.
- The book has a chapter, 3D objects, in English and in French: a box lit, the light, edges, perspective, moving and
  turning, a small machine, an STL part, a lit surface, how each step works with its papers, its limits, its speed, and
  matplotlib, MATLAB, plotly and PyVista beside it. `std/plot` loads in 4.89 ms where it took 4.36 ms, and a first graph
  takes 8.1 ms, against 7.7 (medians of 21 runs, alternated): the code of meshes is in the package.

### Tools

- `cesia build --target wasm file.ce` compiles a program ahead of time to WebAssembly: `file.wasm` and its loader
  `file.js`, which `node file.js` runs and a page runs as a module script, with the output, the errors, their places and
  the limits of `cesia run`, byte for byte. A first slice: integers of 63 bits checked, floats, texts, lists, maps,
  functions and closures, `if`, `match` and loops, results and `?`; what it doesn't compile yet is an error at the
  build, at its place. Values are objects of WasmGC, the browser's own collector; the compiler is a plugin,
  `cesia_wasm.cmxs`, that only `cesia build` loads. The book's chapter Compiling to WebAssembly shows a program in a
  page.
- Fibers in WebAssembly: `fiber.Spawn`, `Wait`, `Cancel`, `Channel` with its size, `Send`, `Receive` and `Select` with
  their timeouts, `Close`, `sys.Sleep` and `sys.Now`, in the order of `cesia run`, each wait parking the fiber's whole
  stack by JavaScript Promise Integration (Chrome 137, Firefox 153, Safari 27, Node 26). A long run gives the page its
  event loop back every 8 ms: a loop of 2 seconds leaves Chrome at 60 frames a second, for 2% of its time, and Firefox
  at 57, for 8%.
- `std/js`: `js.Call(module, name, args)` calls a function of a JavaScript module beside the program, the one way out
  of a page; a channel given to it is the one way in, filled by JavaScript. In a page, `std/websocket` is the browser's
  WebSocket, and `regex.Test` its `RegExp`.
- The standard library of a page: dictionaries of keys of numbers and texts, most of `std/text`, `json.Parse` and
  `json.Text`, `list.Sort`, `Max`, `Min` and the others, `std/columns` and `std/matrix` as `std/plot` uses them,
  slices, masks and indexes of two dimensions, `in`: Ceres's pages, `std/plot` in them, run in Chrome and Firefox.
  The places of errors go in `file.sites`, which the loader reads at the first error only.
- In a page, `std/check` reads a shape as on the server, the same values and the same messages: the forms of a page and
  the body of its request are checked by one definition. `http.Fetch` is the page's `fetch`, a path of its origin
  allowed, its cookies sent, `peer` refused (the browser doesn't tell the address); `date.Local` is on the clock of the
  page; `encode.Hex` and so `std/encode`, `text.Bytes`, `FromBytes`, `PadLeft`, `PadRight`, `IsUtf8` and
  `ByteFindAny` compile.
- `cesia doc --site` colors the blocks of `python`, `r`, `matlab`, `ocaml`, `js`, `lua`, `bash`, `sh`, `powershell`,
  `toml`, `ini` and `css`, the tabs too, with the colors of Cesia's code: keywords, called names, texts, numbers and
  comments, the variables of a shell, the keys and sections of `toml` and `ini`, the properties of `css`. It colors them
  as it builds, with no script, in the time the site took before.
- `std/markdown` writes images, `![what it shows](url "title")`, as CommonMark and GitHub do, the text between the
  brackets as the image's `alt`; an image leads only to http, https or a file of the site, never `javascript:` or
  `data:`. A hook `Image(url, alt, line)` gives its address; without it, an image takes the one `Url` gives.
- `cesia doc --site` shows the images of a book: the files of `docs/BOOK/images/`, PNG, JPEG, GIF, WebP or SVG, written
  from the page's own folder as GitHub shows them, a French page leading to the English ones. An image that isn't there,
  from elsewhere, outside `images/` or with no text for those who can't see it stops the build, as an SVG that holds
  more than a drawing or a link among the files. The images the blocks draw go to `drawn/` of the site.
- `cesia doc --site` shows under a block the image it draws: each `.svg` file that the block names between quotes, as
  `plot.Save(g, "waves.svg")`, and that its run wrote, at its size and with the title of the graph for those who can't
  see it. Only a drawing is shown, the elements of `plot.Svg`: an image with a script, a link or a file it would load
  stops the build. Cesia's book shows its graphs so: bars, heatmaps, bands, texts, rules, notes, ticks of your own, polar
  graphs, surfaces and lines in 3D, an animation, the sun path, and the graphs of the chapters on numerical methods and
  statistics, where it showed only their code.
- The book shows pictures in nearly every chapter. Diagrams, SVG drawings of `docs/book/images/`: a value and its two
  names, the store of a list, a slice, an array of three dimensions in memory, the three forms of a dictionary and a
  `dict.Put` on its trie, a struct copied, closures, `?`, two fibers on a timeline, a middleware, the folders of a
  project and its uses, what `--allow` opens, the path of a program through the engine, two transactions, `cesia test`
  and a first run. Charts that its blocks draw from the numbers of its tables: speed beside Python, Node, Go, Java and
  the others, C, native packages, duplicates, servers, JSON, graphs, numbers, numerical methods, statistics and data.
  And Cemacs at work, in pictures it takes of itself: cells, a table and its graph, sliders, inputs, the debugger and
  the documentation from `cesia lsp`. The French pages show the same ones, the diagrams and pictures with their words
  in French. An image of a page is never wider than the page, on a phone too.
- For those who work on Cesia: the tests added since 1.2.0 had made the change loop 4.8 s again; it takes 4.0 s, 4.4 s
  with two cores busy. Tests slow by nature run with `tools/test.sh --slow`, which `tools/check.sh` runs after the loop:
  nine of the JIT, whose loops are as long as the units and level 2 they check need, those of `install.sh` and `cesia
  upgrade`, the tight stiff problems of `ode.Solve`, math on an array past its split among the cores and the random
  lines of sliders. Tests slow by accident start fewer processes, stop a cell 50 ms after it starts instead of 200, or
  run under a limit of 4 MB instead of 16.
- For those who work on Cesia: `cesia doc --site` runs the blocks of a page again when `CESIA_STD` names other sources
  of `std/`, or when one of them changes, where it showed what the blocks printed with the std/ of the binary, its
  images too.
- For those who work on Cesia: the CI runs the slow tests too, on Linux, as `tools/check.sh` does before each commit,
  where no CI ran them; and a branch `try/NAME` is built and tested as main is, on the three systems, publishing nothing,
  so that a change of the release itself is seen working before it reaches main.

### Speed

- `encode.Base64` makes its digits as numbers and the text by one call of `text.FromBytes`, instead of a text of four
  pieces for each three bytes: 125 bytes in 24 µs instead of 56, as the cursor of a page of Centauri, which writes one
  for each page; its output is the same, as RFC 4648's vectors and a property test against the version before check.
- `cesia build --target wasm` makes faster modules. Each `for` and `while` runs in a function of its own, 16,384 turns a
  call, so that V8 and SpiderMonkey run it in their optimized code from its next call, where a long call stayed in its
  first code; a map literal whose keys and kinds the compiler knows is a struct of WasmGC with typed fields, and a
  statement that reads such a map or a float from a variable has a fast version after one test, the general one when the
  test fails; a map past 8 keys finds them by a table of hashes with a seed drawn at random for each table, and takes a
  new key in its own room; arithmetic and comparisons of values go inline for floats and small integers. In Node,
  against the first slice: `matmul` 171 ms instead of 904, `structs` 151 instead of 923, `dyn` 310 instead of 1,103,
  `points` 53 instead of 148, `mandel` 58 instead of 91, and `bench/maps.ce`, 500,000 keys, 413 where it hadn't ended
  after 100 s (`cesia run` 342); JavaScript in the same Node takes 61, 142, 137, 34, 57 and 583. Chrome 158 and Firefox
  160 are measured too, in the book's chapter Compiling to WebAssembly.
- Modules compiled to WebAssembly are smaller: only the types their code uses, the texts of messages a byte each from a
  data segment, and messages that name a value without the printer of arrays: hello world takes 322 bytes instead of
  431, `matmul` 10,879 instead of 11,194; the loader 3,149 bytes instead of 3,820, 1,313 with Brotli.
- `http.Handler` puts the routes in a tree of the parts of their paths, once, where each request tried them one by one:
  the route of a request costs the same among 500 routes as among 5, 2.9 µs for the last of 500 instead of 235, 2.8
  for the last of 100 instead of 44.8, the last item of an API of 200 routes in 3.5 instead of 159, and a path that none
  of 500 takes gets its 404 in 0.84 µs instead of 243 (the handler called without the network, medians of 5 runs,
  alternated; Go's `ServeMux` takes 0.28 to 0.36 µs, its 404 1.48). The first route added that takes the path, then
  the method, answers, as before, which a test checks on random sets of routes against the walk of the list; building
  the tree takes 91 µs for 200 routes, when `http.Handler` is called.
- `crypto.Blake2b` is the BLAKE2b of OCaml's runtime, the reference code of RFC 7693, where it called libsodium's through
  `std/c`: the same bytes, at every size, in 0.47 µs instead of 3.56; `crypto.IsSame` compares in OCaml, every byte
  read, as `sodium_memcmp` did, in 0.16 µs instead of 3.38; and `encode.Hex` writes its text in one pass, so that a hash
  of 32 bytes and its hex take 0.87 µs instead of 19.2. The check of a session, the hash of its secret in hex compared
  with the one kept, takes 1.18 µs instead of 23.5, beside Python's 0.84 (medians of 5 runs, alternated). The other
  calls of `std/crypto` stay in libsodium.
- The cache of loaded packages reads the code of a function only when that function first runs: an entry is a head,
  which the load reads and checks, then a record for each function, its body with the names of its variables, which the
  run maps from the file and checks at that function's first call alone. `use std/plot` reads 25 KB of its entry of
  236 KB, none of its 260 records, and takes 3.85 ms instead of 4.22, the 0.33 ms that the 3D graphs had added; every
  package of Cemacs loads in 11.33 ms instead of 11.80; a first `plot.Svg`, which reads 105 records, takes the same time
  (medians of 101 runs, alternated).
  An entry's name holds the build of Cesia too: two versions used in turn, as an old binary kept beside a new one, keep
  each their own entries, where each run wrote over the other's and read its packages from their sources: `use
  std/plot` in 3.75 ms instead of 33.76, the two versions taking turns (medians of 21 runs). The entries
  of earlier versions are no longer read, and go once the folder passes 256 MB, as the least used.
- A native called with three or four arguments, as `text.ByteFind`, `text.ByteSlice` or `text.PadLeft`, gets them in
  an array made in place, as one with one or two always did, where a map made a closure and called into C at each call:
  20 ns less a call, `text.ByteFind` of a byte near in 125 ns instead of 145, `text.ByteSlice` of 5 bytes in 90 instead
  of 109 (medians of 21 runs, alternated).
- A file of more than 256 statements or functions loads from the cache of loaded packages with no young collection:
  each of its arrays that long was made of a young value, which OCaml moves out first by a collection that promoted all
  that was read, three of them at each load and then a major cycle. Cemacs, whose cells passed 256 functions, reaches
  its first frame in 30.84 ms instead of 32.96, as fast as before them (30.86), medians of 21 runs, alternated.
- A search for a part of 32 bytes or more is 3.5 to 9 times faster, by Two-Way and a skip to the part's rarest byte, eight
  bytes at a time: a part of 1,000 bytes at the end of 100 MB of text is found in 105 ms instead of 650, a miss in 1 MB
  of `a` by `aa...ab` takes 0.44 ms instead of 10; `text.Count` and `text.Split` work on such a part once, not at each
  place found, and count a part of 32 bytes in 1 MB of it in 3.1 ms instead of 9.1 (medians of 21 runs, alternated).
- A loop at the top of a file that assigns a variable a function reads, or a name that code typed at a prompt before
  gave a value, the variable of its `for` included, is machine code, the variable kept in a register and written back
  to its module at the end of the loop, at each checkpoint, where another fiber or a stop sees it, at a statement left to
  the interpreter and at an error: `n = n + 1` over 10^6 turns, `n` read by a function, in 8.4 ms instead of 21.7, over
  10^7 in 17.3 instead of 161.9, and the same loop typed a second time at a prompt in 2.96 ms instead of 26.8 (medians of
  21 runs, alternated). A loop that only reads such a variable of the file is machine code too.
- Machine code calls a function that has defaults directly, an argument left out, given, or named in any order, bound
  as the interpreter binds it and made in the order of the parameters, the default made in the callee's frame after its
  step, where the loop around such a call stayed interpreted: 10^7 calls of `f(i)` with `step = 1` in 27.0 ms instead
  of 321.6, of `f(i, 2)` in 27.3 instead of 284.4, of `f(i, step = 2)` in 27.1 instead of 283.0. A self tail call into
  another version, as `count(n - 1, acc + 1)` from `count(50)` with `acc = 0`, is a call, as the interpreter's, and no
  more keeps the whole function interpreted: 20,000 calls of `count(50)` in 10.5 ms instead of 16.4 (medians of 21 runs,
  alternated).
- A native costs less to call: only an owned list, struct or map is looked for among its arguments to be shared, where
  every result was, a sixth of a call of `math.Abs`, and one with no argument makes no array through a map: 10^7 calls of
  `text.ByteLength` in 269.8 ms instead of 322.7, of `sys.Now` in 422.9 instead of 517.6; and machine code makes
  `math.Abs` of an integer itself, 10^7 calls in 20.2 ms instead of 302.1 (medians of 21 runs, alternated).

### Fixes

- A server no longer slows down as it serves. Once the large allocations reserved since the last full checkpoint passed
  a quarter of the memory limit (with the default limit, a few minutes of a busy server), every reservation after it
  asked OCaml for the size of its heap, `Gc.quick_stat`, which took a third to a half of a request's time, and only a
  full checkpoint, which a request's fiber never reaches, started the count again: a plaintext route of `std/http` fell
  from 29,300 to 14,900 requests a second and stayed there, 30 to 64 µs of CPU a request, with no database at all, and
  a TechEmpower app on Cepheus the same. The heap is now looked at once each time a quarter is crossed, as was meant:
  30,100, then 35,500 a second over the same 19 minutes (12 rounds alternated with the binary before and a Go server
  as the control, load 3.7 to 11.8).
- Each response of `http.Serve` has a `Date` header, as RFC 9110 asks of a server with a clock (section 6.6.1), in its
  form of section 5.6.7, `date: Wed, 25 Nov 2026 13:40:00 GMT`: caches and clients read the age of a response from it.
  The line is made again when the second changes, not for each response, and a handler that sets its own `Date` keeps
  it.

- An error of the system that a native lets out instead of an Err, a `Sys_error` or an error of Unix, is a panic of the
  kind io at the native's call, which stops its fiber alone, where it ended the program with a line naming no place, or
  with an internal error. No native of `std/` is known to let one out: it is a safety net, and it costs nothing, caught
  where panics are, where a handler at each call cost 0.5 to 1.4 ns.
- Under `--limit steps`, the limit is reached at the step that goes past it in whatever fiber, in the interpreter and in
  machine code alike: a fiber started with a whole quantum of 10,000 steps, whatever was left, and a main program that
  waited kept its last steps uncounted while the fibers ran, so the limit came later, where the checkpoints fell, which
  machine code put elsewhere than the interpreter: a program that ran a fiber after a loop of machine code needed 37,999
  steps interpreted and 41,016 in machine code; both need 41,016. A loop of short fibers now stops inside the fiber that
  goes past the limit, where it stopped at the spawn of one after it ended.
- Under `CESIA_JIT=always`, a loop at the top of a file, of a cell or of code typed at a prompt gives its variables
  their last values: the top was machine code as a whole from its first run, which kept them in registers and wrote them
  to the frame only at a checkpoint, so a variable read after it, by another file, a function defined later or the
  variables of a session, held its number of the last checkpoint, `9999801` for `10000000`, or `0` after a loop shorter
  than a quantum. The default JIT never made a file's top machine code as a whole, which it does only after 1,000 calls.
- Code typed at a prompt, that of `cesia run --repl`, `debug.Eval` at the file level, as a debugger runs it while the
  program runs, and a session of std/cells at line 0, as Cemacs's `C-c e r` and `*repl*` send it, gives a name that code
  typed there before gave a value its new one in place: `x = x + 1` reads the x before, and so do `xs[2] = 7` and `p.X =
  3`, where each stopped with `"x" has no value yet.` and left the name with no value; a line that fails leaves the name
  with the value it had when the error came; the functions defined at the prompt before read the new value, where those
  of `cesia run --repl` read the old one; and the value before goes, where it stayed in memory behind the new one. A cell
  keeps its rule: it forgets the names it defines before it runs. A name given a value twice in one cell or one line
  shows once among the variables of the session, where it showed twice.
- A function whose record in the cache of loaded packages doesn't read when it first runs, as when another process
  changed the file in place, is taken from its file parsed and resolved again from the source the load read, and the
  run goes on with the same output, where it stopped with "The cache of loaded packages kept this function damaged".
- `stats.MonteCarlo` gives its estimate when its draws add up below 0, where it stopped at its first block with "A
  condition must be true or false, not missing": the rounding step of its sums wrote |x| as `if x < 0.0 -x else x end`.
- `ode.Solve` with `stiff = true` solves back in time with steps longer than 1, where it stopped with "f gave [missing] at
  t = missing", and takes the derivative in t on the side the solution goes, where shorter steps took it on the other:
  the sign of the step was `if s < 0.0 -1.0 else 1.0 end`.
- For those who work on Cesia: `tools/tabs.ce` reads a negative power of ten, as `1.25e-07`, as negative, where it read
  it as positive on both sides of a comparison, so that a tab that printed 1.25e7 for 1.25e-7 agreed.
- `frame.SortBy` keeps equal values in their order when it sorts decreasing too, as its documentation said, where it
  reversed them, and puts the NaNs last both ways, as pandas, R, numpy and the tables of Cemacs do, where they came
  first in an increasing sort. A program that read a NaN at the top of an increasing sort finds it at the bottom.
- `list.Reverse`, `list.Take` and `list.Skip` keep a list of floats or of integers typed, copied in parallel, where
  each value was boxed and the list looked over again: 3 to 10 times faster on a million numbers (85 ms to 10 to 30 ms,
  medians of 21 runs on a machine in use).
- `plot.Svg` and `plot.Save` write the title of a graph of two dimensions as the `<title>` of its SVG, which a screen
  reader reads, as they wrote the words of a 3D graph, and for a grid the titles of its graphs: the image that a block of
  the book draws had, for those who can't see it, only its file name where the title of the graph was meant.
- A program whose current folder another process removed goes on: `path.Abs` of a relative path is a bug of the new kind
  `io`, which stops its fiber alone, as any bug, where an error of OCaml ended the program with exit 1, every fiber with
  it, saying only `cesia: No such file or directory`. An absolute path needs no folder and is given as before; a grant of
  a relative folder, as `--allow read=.`, holds nothing then and the act is denied; `sys.Run("./x")` gives an Err.
- On a Windows with neither Git nor MSYS2, the libraries of a release load: `crypto.Open` and `tls.Open` failed there,
  as the libsodium of `lib/` needed a DLL of its compiler, `libgcc_s_seh-1.dll`, that no release holds, and `libssl`
  looked for `libcrypto` beside `cesia.exe` and on the `PATH`, not beside itself in `lib/`. A library opened by its full
  path loads those it needs from its own folder first, as on Linux and macOS. The release builds libsodium and OpenSSL
  from their sources, as on macOS, with nothing of the compiler outside them; it checks that each DLL of `lib/` needs only
  the others and those of Windows, and runs its check of SQLite, libsodium and OpenSSL with only the folders of Windows on
  the `PATH`, where those of Git hid both faults. OpenSSL is 3.5.9 on macOS and Windows, the version of 3.5 its project
  follows until 2030, where Windows had 3.6.4, no longer followed since November 1, 2026, and macOS 3.5.4.
- A search for a part of 32 bytes or more, by `text.Find`, `Contains`, `Count`, `Split`, `Replace` or `ByteFind`,
  allocates nothing of the part's length and does nothing when the part can't fit in what is left of the text: the
  method of Knuth, Morris and Pratt built a table of 8 bytes a byte of the part outside `--limit memory`, and its work
  outside `--limit steps`, where Two-Way, of Crochemore and Perrin, needs no table. A part of 10 MB searched in 100 bytes
  under `--limit memory=16M` took 94 MB, now 18 MB, the two texts; 2,000 searches of a part of 1 MB in `"x"` under
  `--limit steps=100000` took 15.5 s, now 0.00 s. With `fold`, the part is no longer copied in lower case.
- The cache of loaded packages keeps the count of its bytes in its file `total`, which each write adds to under a lock,
  and is looked over only when the count would pass 256 MB, by one run while the others wait: the first write of each
  run read all its entries, 40,000 files on a machine in use, so hundreds of runs that ended at once, as a suite of
  tests, stalled the disk. 60 runs of new files ended at once on a copy of such a cache, 154 MB: the copies that save
  their entries all end within 0.16 to 0.27 s, where they took 2.1 to 2.5 s (3 turns each, alternated), the same entries
  saved. A folder just under the limit whose entries are written again at the same size goes down to half once, where
  it would be looked over at each write.
- `sys.Mkdir` gives an Err where a name is there that is no folder it can reach, a link that leads nowhere or a folder
  another process took away between its two steps, as `mkdir -p` says, where the program ended at once with exit 1,
  whatever handled its errors: the check after the system's "file exists" raised an error of OCaml that no native turned
  into an Err. The same on Windows for `sys.RemoveTree` and `sys.CopyTree` of a folder that goes away while they list
  it. `tests/sys/remove-race`, which makes and removes folders while another process swaps them, ended so once in 24
  runs under load, never in 120 now.
- A function that calls itself in tail position runs as a loop when the call names its arguments or leaves a default
  out, as the book says, where only a call that gave every argument in order did: `byStep(n, step = 1) = if n <= 0
  "done" else byStep(n - step) end` stopped at the depth limit from 10,000 on, on both paths, and now runs 100,000 turns
  in one frame, its defaults made again at each turn. 2,000 runs of 5,000 turns take 277 ms where 2,000 runs of 5,000
  calls took 311 (medians of 7, release builds); calls that gave every argument run as before.
- `cesia test` saves the failing case of a `ForAll` when another run makes `.cesia/failures` at the same time, as the
  golden tests of a fresh clone do, where the save went silently and the next run drew its cases again: 8 runs at
  once lost one in 25 tries, none in 60 now. The CI on macOS failed so on `tests/testing/forall`.
- `cells.Analyse` gives the error of rule 5 for a slider written with no argument, `x = cells.Slider()`, where it
  panicked, so an editor that analysed such a file stopped.
- `cpp.Wrap` makes its library again when a header of the project that the layer includes by `"name"` changes, or the
  compiler, its version or its flags, where it reused a library whose `.cpp` text matched: an edited header went
  unseen, and a library that someone else put in the build folder beside that `.cpp` was loaded. The fingerprint of each
  library it makes is kept in Cesia's cache, the person's alone, and a library without it is made again; it compiles
  under a name of its own, then renames.
- `http.Fetch` takes `timeout`, the seconds a server may stay silent between two reads, 300 unless it says otherwise,
  and `maxBody`, the most bytes of a body, none unless it says so: a silent server held it for ever. It refuses a head
  past 16 KiB, and searches each read alone for the end of the head, where a head that never ended filled the memory
  and was searched whole again at each read.
- WebSocket: the client counts each fragment of a message 64 bytes more than its payload against `maxMessage`, where a
  server that sent empty fragments filled the memory with 2 bytes of traffic each; the server reads a frame that comes
  in pieces into one buffer, joined once, where it copied all it had at each piece (a megabyte in pieces of 64 bytes
  took 2.4 s of its processor); it closes with 1007 a text or the reason of a close that isn't UTF-8, and with 1002 a
  close of one byte or of a code that RFC 6455 refuses, where it took the text and sent the close back.
- `cesia upgrade` fetches over `https://` alone, and refuses a redirect to another address, where it followed a
  `Location` of plain `http://`; `install.sh` and the line that runs it ask `curl` for `https://` alone and TLS 1.2 at
  least, redirects too, and `install.ps1` for TLS 1.2 and an `https://` address at the end of its redirects.
- `cesia upgrade` puts the new `lib/` in place, then the binary, and undoes each step when a later one fails, so that a
  failure leaves the old Cesia whole: it left the new binary with the old `lib/`, or none, when its `lib/` couldn't be
  moved, as for an archive that held an `old-lib/` folder of its own.
- What a cell prints is never taken for a message of its session: a line of data that held the byte 1 and JSON, as a
  row of a CSV, was read as one, so that it could end the run with a value of its own, put the next runs out of step,
  and give `cells.Html` a graph whose SVG held a script. Each message now holds a token that the session draws at
  random as it starts, and `cells.Html` puts in its page only an SVG as `std/plot` writes it. A session of an older
  `std/cells`, as a project's own copy, still runs.
- `cesia pkg` refuses a fetched project that holds a link, its `cesia.toml` too, before a byte of it is copied: a
  link, as `cesia.toml -> ~/.cargo/credentials.toml` or `src/p/x.ce -> ...`, copied the file of the person it led to
  into `deps/`, where the project read it, and the code of a dependency as its own. The cache of git knows a
  repository by its whole address, so another one that ends in the same folders is never served for it: a dependency
  that asked for `file:///tmp/x/someone/geometry` at a tag filled the cache for `github.com/someone/geometry` at that
  tag, for every project. A source fetched without encryption, `http://` or `git://`, is refused: anyone on the way
  could change its code.
- `cesia doc --site` stops at a link in the `files/` of a book, which it copied as the file it led to, so that a block
  allowed to read its own folder read any file of the person who built the site; at a `source` of `[site]` that is no
  `https://` or `http://` address, as `javascript:`, put in the link of each page; and at a link under `docs/`, `std/`
  or the sources that leads nowhere, with its name, where it stopped with an internal error.
- The chapter on permissions says plainly that `exec=PROGRAM` gives that program all its own powers, with any arguments,
  as `ffi=` does: a browser, a shell or `cesia` itself is total trust.
- `sys.Link` needs the write permission on its target, as well as the read one: a hard link is the same file under a
  second name, and a program allowed to read `readable/` only, with `write=out`, could link a file of `readable/` into
  `out/` and write, change the mode or the time of the original through it; in `cesia test`, a test could rewrite the
  project's sources whenever its Temp folder was on the same disk. `sys.ReadLink`, `sys.Remove` and `sys.Rename` check
  the link itself, not where it points: a link out of the folder could be made but never read, moved or removed.
  `read=` and `write=` written from the root hold the same files as written from the current folder, and the reverse:
  a task with absolute folders was denied its own files. On Linux, a file or a folder is checked again where the system
  opened it, and the act done through it, so another process that swaps a folder of the path for a link between the
  check and the act can't lead a read, a write, a change of mode or a new link out of the folder; a link that another
  process removed while a path was checked ended the program with an internal error. `sys.Copy` of a file dated the
  first second of 1970 gave the copy the time of now.
- On Linux 5.6 and later, an act under a folder of `read=` or `write=` opens its file or its folder from the folder of
  the grant with `openat2`, `RESOLVE_BENEATH`, so the kernel refuses a walk out of it in the same call: the second
  check of each act where the system holds its file, which made `sys.Read` of a small file 1.3 times slower and
  `sys.Write` 1.5 times, is gone, and so is, for a path written below its folder, the walk of each folder of where it
  leads to check it first. With `read=data,write=data`, a small file reads in 5.0 µs instead of 16.5, 12.7 before that
  second check, and is written in 19.8 µs instead of 29.4 and 22.6 (medians of 21 runs, alternated). An older
  Linux, or a filter of system calls that refuses `openat2`, keeps the second check.
- `sys.Read` of a small file, or of one the system calls empty as those of `/proc`, no longer takes two buffers of 64
  KB: it reads a file into one of its own size and a byte, and an empty-said one into a page. A read of 12 bytes takes
  3.0 µs instead of 7.7.
- On Linux, `sys.Copy` and `sys.CopyTree` copy the bytes of a file in the kernel, as `cp` does, with `copy_file_range`:
  a clone on btrfs or XFS, which shares the file's blocks until one of the two changes. A file the kernel can't copy
  so, as one of `/proc` or a copy to another file system, is read and written as before, as on macOS and Windows. In a
  folder that it makes, the person's alone while it fills, `sys.CopyTree` makes each file and link at its own name at
  once, only new, where it made each under a name of its own and then renamed it, as it still does in a folder that
  was there. A tree of 2000 files of 1 KB and 20 links copies in 52 ms instead of 114, where `cp -a` takes 60 and
  Python's `shutil.copytree` 172; into a copy of it that is there, each file replaced whole, in 119 ms instead of 166,
  where `cp -a`, which writes over each file in place, takes 52. One file of 1 KB copies in 19 µs instead of 40, and
  one of 100 MB in 0.1 ms instead of 350 (medians of 21 runs, alternated, on btrfs).
- `sys.Copy` sees that the copy is no other name of the source on the file it opened, where it looked at the path
  first, and gives the copy its times to the nanosecond, where a float of seconds could round them. It opens its
  source without waiting, then refuses a pipe or a socket with an Err at once: a pipe at its source, even one put there
  by another program after a check, held the program until someone wrote into it. A device is copied as before, as `dd`
  does, and a link is still copied as the file it leads to.
- `Limit "steps" reached.` names the step that went past the limit: the turn of a loop, as `for j in 1..100` in
  `spin`, or the call that made a frame, as `deep(n - 1)` in `deep`. It named the last place that had written its
  site, as `io.Print(spin(1000))` while `spin(100000000)` of the next line ran, and machine code, which writes none,
  named another place than the interpreter: now both name the same. A program run with `--limit steps=N` makes its N
  steps, and the next one stops it; at the step of a full checkpoint, it stopped one step early.
- The test of a `while` runs once at each turn under the JIT, as in the interpreter. A test false at its first turn ran
  twice once the loop was warm, in a function that stays interpreted: under `CESIA_JIT=always` at the loop's first run,
  in the default mode at each run from its 6,250th. What the calls of the test printed came twice, their work was done
  twice, and their steps counted twice, so that `--limit steps` named a later step than the interpreter.
- A valid program no longer ends with `Internal error: Not_found` under the JIT: a list of integers that took a float
  from an inlined call, in an `if` that also held an empty `if`. A statement that doesn't become machine code now drops
  the blocks made for it with the rest of its code; and any bug of the JIT met while it makes code leaves that loop or
  function interpreted, so that it can never end a program again.
- A nested expression loads in a time that grows with its size: each operand is compiled once. Horner's rule over a
  struct's fields, `c.C0 + x * (c.C1 + x * (...))`, and a chain of indexes, `xs[1][1]...`, compiled an operand twice
  at each level, so that a degree of 20 took 16 s to load and one of 25 never ended.
- `--limit memory` holds while values are written as a text: `value.Text`, an interpolation, `io.Print`, `json.Text`,
  `json.Pretty` and `csv.Text` reserve the bytes of their text each time it grows by a megabyte. A list of 100,000
  times one text of 10 KB, which costs little memory, made a text of 1 GB past any limit.
- An integer and a float compare by their exact values, in `==`, `<`, `>`, maps, `list.Unique`, `list.Sort`, `in` and the
  machine code of the JIT: `9007199254740993 > 9007199254740992.0` is `true`, and the two are two keys of a map. The
  integer was rounded to a float first, which past 2^53 made it equal to its neighbours: a map merged them or lost one,
  and `list.Unique` kept two or one of the same three numbers by their order. An integer and a float it is exactly, as
  `9007199254740992` and `9007199254740992.0`, are one key as before.
- A text in the code of a text, nested past the limit of nesting, is refused as the lexer reads it, as the parser
  refused it after: a file of 5 MB of `"$("$(...)")"` took 735 MB before the message, and one of 15 MB was killed first.
- Under `CESIA_JIT=always`, a typed parameter is checked as the interpreter checks it: a version whose parameters' or
  result's types would be checked as it runs stays interpreted, so `f0(p Int)` called with `2.5` stops at the call, where
  it gave `1.0`.
- A deep recursion, let deep by `--limit depth`, stops near `--limit memory`: OCaml's stack, which the heap doesn't
  count, takes a quarter of the limit at most, or 8 MB, and running out of it is reaching the limit of memory. A
  recursion under a limit of 300 MB took 734 MB before it stopped, now 341 MB.
- A text that isn't UTF-8 follows one rule everywhere: a character starts at each byte that doesn't continue one,
  10xxxxxx, and holds those that do after it; bytes that begin the text and continue nothing are one character.
  `value.Len`, `text.Slice`, `text.Find` and `text.PadLeft` counted so, but `text.Chars`, `text.Code` and regular
  expressions cut each bad byte alone, and `text.Slice` dropped the bytes at the start of a text.
- `math.BitShift` shifts right with the sign, as Python and Go: `math.BitShift(-8, -1)` is `-4`, not
  `4611686018427387900`. A left shift works on the 63 bits of an integer, as its doc now says.
- Two messages say what is wrong: `json.Text` of a value nested past 1,000 levels says so, not that JSON can't hold an
  array, and an index outside a text names a text of so many characters, or bytes, not an array of elements.
- A C function that calls back into Cesia from a call bound without `callsBack = true`, or from a thread of its own,
  stops the program with a message that says so: the callback ran inside a call that holds no frame of OCaml's and
  corrupted the memory, a segmentation fault at best. The version of `c.Open` is digits and dots, as `6` or `"1.2.3"`:
  one with a `/` made the name a path from the current folder, which opened a library that `--allow ffi=NAME` doesn't
  grant. `c.Callback` of a function already made a callback with the same types gives the first one back, `c.Fn` and
  `c.Callback` share one signature for the same types, and each new callback counts against `--limit memory`: 300,000
  callbacks under a limit of 30 MB took 292 MB of C memory.
- Under the JIT, an index error of a small list of floats read at a constant index names that index, not its double:
  `Index 6 is outside this array of 2 elements`, where it said `Index 12`.
- `csv.Parse` reads a quote inside a field that doesn't start with one as a quote, as Python's csv does: `12" pipe,3` is
  the fields `12" pipe` and `3`, where it opened a quoted field that swallowed the rest of the text. A quoted field that
  never closes is an Err of the kind `"csv"`, from `csv.Parse`, `csv.Records`, `columns.ReadCsv` and `frame.FromCsv`. A
  separator is one byte, in Parse and Text, or a type error: `"::"` was ignored by Parse, and `""` made Text write a field
  that read back as another.
- `encode.Unbase64` takes the padding only at the end, one or two `=` of a text of a multiple of four: `aGk=aGk=`, two
  texts put end to end, and `aGk=junk` decoded to wrong bytes without an error.
- `json.Parse` refuses a text that isn't UTF-8, as RFC 8259 asks, and `json.Text` a text of such bytes, which made JSON
  that wasn't. An integer past 63 bits is kept as the text of its digits: `12345678901234567890` became the float
  `1.2345678901234567e19`, which lost the digits of an ID or a hash. An error would have refused a whole document for a
  number nobody reads, and no number of Cesia holds it, so its text, exact, breaks no correct use.
- `date.Format` writes a year before 1 with its sign, `-0005-01-01`, and an offset with seconds with them, `+00:09:21`,
  the time of Paris before 1911, and `date.Parse` reads both: Format gave `00-2-12-17T...`, which Parse refused, and
  rounded an offset of 90 s to `+00:01`.
- A line at the top of a file that starts as the head of a method, with a word glued after its parentheses and nothing
  past it, as `a.v()m`, no longer stops `cesia.Definitions`, `cesia doc` and `cesia test` with an internal error, nor
  `cells.Analyse` and `cesia lsp`, which read cells and files with it: the head was measured by its signature, which
  puts one space before a return type, where the line may have none. It is measured in the line, so that a head with
  two spaces before its return type, as `Rect.Unit()  Rect = ...`, or none around its `=`, as `Rect.Unit()Rect=...`,
  keeps its documentation, which was lost.
- A `defn` whose head, which doesn't read, goes on past its line with a space before a `)`, as `defn )((`, makes
  `cesia test` say that its file can't load, and `cesia doc` leave it out, where both stopped with an internal error: the
  lines of the head were joined with their `defn`, whose space was dropped as one before the `)`.
- A value at the top of a file written `X=1` or `X  = 1`, with any spaces around its `=` or none, keeps its documentation
  in `cesia doc`, `cesia.Doc` and `cesia.Definitions`, as `X = 1` does: only one space on each side was read as a value.
- `cesia test` of a file that doesn't parse, or of a folder that holds one, prints its error as `cesia run` does and ends
  with the code 1, even when the file has nothing to run, which it only reads: it said `0 passed, 0 failed` with the code 0.
- A limit of steps or of depth reached at a call's own step names the function called, at the line that defines it, then
  the call that made its frame, as Python names the frame being entered, in the interpreter and in machine code alike:
  for `f(x) = x + 1` on line 1 of `a.ce` and `run() = f(2)` on line 2, the trace says `in f (a.ce:1)` then `called from
  run (a.ce:2)`, where it said `in run (a.ce:2)` then `called from run (a.ce:2)`, the caller twice.
- A parameter left to its default holds its default in machine code too: a function called with it left out, made
  machine code as a whole, read whatever an earlier frame had left where the value goes, in the default mode once it was
  hot as under `CESIA_JIT=always`: 5,000 calls `sum(20)` of `defn sum(n, step = 1)`, a loop, among calls of another
  function, summed 239,999,960 where they sum 100,000. A self tail call that gives that argument is a call to the version for every argument, in a frame of its own, in
  machine code as in the interpreter: `count(5)` of `defn count(n, acc = 0)` gave 11 under `CESIA_JIT=always`, and a
  limit of depth counts that frame in every mode.
- A loop whose machine code was dropped, at the 17th guess of it that failed, while the interpreter made the rest of
  that turn, goes on with the code the JIT made again for it when a loop inside got hot there: the program ended with
  `Internal error: Cesia.Tier.Handoff`, as two calls of `ode.Solve` under `--limit depth=4` in the default mode, where
  a checkpoint comes at nearly every step; in any long run, the checkpoint of every million steps could fall there.

## 1.2.0

Everything here is added, but for two exit codes of `cesia do` (Changed, just below): a program written for 1.1 runs
as it did, and so does a project whose `std/` 1.1.0 installed, without `cesia pkg install`.

### Changed

- On Linux and macOS, the last task of `cesia do` takes its place, in the same process (`exec`): systemd sees the
  program itself, stops it with one TERM, and gets its own exit code, as from `cesia run`. Two exit codes change: a last
  task killed by a signal gives the shell's 128 and its number, 143 for TERM, instead of 1; a last task that a TERM
  stops cleanly, as a server does, gives its own code, 0, instead of 1. Windows keeps the last task as a child.

### Language

- A do block after the `)` of a call, `list.Reduce(0, xs) do total, x` up to `end`: the function `defn (total, x) ... end`,
  the same tree, in the place of the argument that is `_` alone, or else first, as in Julia. `do` stays a plain name
  elsewhere, and the function written inside the parentheses stays valid. `cesia fmt` and the modes for Emacs and
  Neovim know it, and `cesia.Keywords()` lists `do` with the others, 27 words.
- `text.Fold(s)`, Unicode 18.0's simple case folding, to search and compare what people write:
  `text.Fold("ÉLODIE") == text.Fold("Élodie")`. `text.Lower` and `text.Upper` stay ASCII, for the texts of protocols.
- `value.Text(x, most)`: the text of a value, cut at `most` characters, its first `most - 1` and an ellipsis; only that
  start is made, so a preview of a list of 10^6 numbers or of a long text costs what its `most` characters cost.
- `path.Abs(p)`, the absolute path of a path from the current folder, its `.` and `..` taken away as text; it needs the
  read permission on the path.
- `sys.Mkdir` and `sys.Write` take `private = true`: a folder 0700 and a file 0600, their owner's alone from their
  creation on, or made so if they were there; a private `sys.Write` writes a new file and renames it over the path, so
  that a reader of the old file never gets the text, and a link there is replaced, its target untouched.

### Servers

- `std/websocket` is a client too: `websocket.Dial(url)` gives a connection whose messages come on the channel
  `c.Messages`, with `websocket.Send`, `websocket.Close` and `websocket.DefaultMaxMessage`; tested against
  Autobahn|Testsuite in the CI. `websocket.Dial(url, headers = ...)` sends a cookie or an Origin, and refuses before any
  connection a name that isn't a token or that the handshake writes itself, and a line end or a zero byte in a value.
- `std/live`, live screens: `live.Route(path, screen, actions = {...})` serves pages whose shows change by themselves,
  pushed over a WebSocket, and their actions, drawn at once by `live.js` and confirmed or undone by the app's reply;
  `live.Show(name, changes)`.
- `http.Stream(produce)`, a response whose body goes out in chunks as it is made, each piece within the timeout or the
  connection ends; a panic or an `Err` cuts it short, and HEAD runs nothing.
- `http.SameOrigin`, a middleware against cross-site request forgery, by `Sec-Fetch-Site` then `Origin` and `Host`, as
  Go's CrossOriginProtection; std/live uses it for its screens.
- `net.Peer` gives the address of the other end of a connection, and std/http puts it in each request as `Peer`, to
  limit a client by; a handler gets the request as a middleware left it, with the keys it put there, as the person
  signed in.

### Tools

- `std/cells`: a notebook in a `.ce` file, cut by `(* %% Title *)` comments. `cells.Parse`, `cells.Analyse` (what each
  cell defines and reads, a name in one cell only, read only below its cell) and `cells.ToRun` (the cells that depend on a
  run); `cells.Session`, `cells.Run`, `cells.Forget`, `cells.Variables`, `cells.Rows`, `cells.Scene` and `cells.Stop` run them in a process of their
  own, `cesia run --cells`, as fast as `cesia run`, a graph of `std/plot` as its scene; `cells.Html` gives the page of a
  file, its graphs in SVG. Each cell starts std/random again from the session's seed and its title, so a cell run again
  draws the same numbers; a struct of at most 20 fields shows as a table of its fields, an `Ok` of a struct as the
  struct.
- Sliders in cells: `rho = cells.Slider(28.0, 0.0, 50.0, step = 0.5)`, in a cell of sliders, is a number that an editor
  moves by writing it in the file. `cells.Analyse` gives each cell its Sliders, and the errors of a cell with a slider
  that holds other code, or of a slider whose numbers aren't written in the file; `cells.Snap` gives a slider's position
  nearest a number and its text, `0.3` and not `0.30000000000000004`; `cells.Set` gives a session the new number in place
  and the cells to run again, only those that read it; `cells.Html` shows each slider on the page.
- Animations: `plot.Frames(graphs, fps = 30)`, 1 to 300 graphs shown one after the other, on the axes that all of them
  cover, each frame changing only its data and its title; `plot.Scene(g, width, height, frame = k)` draws one, with
  `Frames` and `Fps` in its scene, and `cells.Scene(session, key, width, frame = k)` asks a session for it, so that an
  editor fetches one frame at a time. `plot.Svg` and `plot.Save` write the frames as an animation of CSS that loops,
  without a script, paused on frame 1 under `prefers-reduced-motion`, keeping every k-th frame past 8 MB; `cells.Html`
  starts each paused under a box Play.
- 3D graphs: `plot.Surface(z, x, y, colors)`, a height over a grid, and `plot.Line3(x, y, z, ...)`, in a box seen from
  `view = [az, el]` as MATLAB's, with `z` and `zlim`, options of `plot.Of`; the quads of a surface drawn far to near in
  an order that is exact without a sort, past 200 by 200 quads the means of blocks, said under the graph.
  `plot.Scene(g, width, height, frame, view)` turns a 3D graph, its scene a new item `"mesh"` and a field `View`;
  `cells.Scene(session, key, width, frame, view)` asks a session for a view, and a 3D graph's value gains `View`.
- `std/plot`, graphs as values: `plot.Line`, `Points`, `Bars`, `Histogram`, `Heatmap`, `Density` and `Area`, on shared
  axes with `plot.Of` and side by side with `plot.Grid`, drawn to SVG by `plot.Svg` and `plot.Save`, and to a scene of
  shapes in pixels by `plot.Scene`; the ticks by the extended Wilkinson algorithm, long lines by M4, the colors of Okabe
  and Ito and viridis. A line of 10^6 points in 37 ms.
- `c.Write(type, offset, values, block)` writes a whole array of numbers into a block in one call, each converted as
  `c.Set` converts one: the vertices of a shape or the pixels of an image.
- `c.Fn(..., slow = true)` runs each call on a domain of its own, the runtime released while its fiber waits, at most
  one per core at once; `crypto.HashPassword` and `crypto.CheckPassword` use it, so a sign-in no longer stops every
  fiber for 70 ms.
- `cesia.Reads(source)`: the names a source reads and doesn't define, with the compiler's own resolver.
  `cesia.Definitions` gives the names of `[q, r] = ...` too.
- `cesia do TASK ARGS...` passes the words after the task to its own program, as its `sys.Args`, never through a shell;
  a task with no program of its own refuses them.
- `[test] skip` in `cesia.toml` names the folders and files that `cesia test` leaves out unless its path is in one of
  them, as end-to-end tests that need a server started first.
- A `[deps]` version may be the whole hash of a commit, for a project that has no tag yet: `cesia pkg` fetches that
  commit alone and checks it.
- `cesia test` stops the programs a test started with `sys.Start` or `sys.Run` when the test ends, even past its time.
- `cesia test` of a folder starts its largest files first, so that a long one doesn't start last and keep the others
  waiting; the reports still come in the order of the files. Cesia's tests/lang, 89 files on 8 threads: 2.44 -> 1.85 s.
- `cesia doc --site` writes formulas in MathML, GitHub's alerts and heading ids, the colors of `[site] color` at AA
  contrast and the README as a page, checks the `norun` blocks that follow one another as one program, and builds the
  French site of `docs/fr/`, whose pages must keep the headings, code and links of the English ones; Cesia's book is in
  French too. `std/markdown` writes GitHub's alerts, and the formulas of `$...$` and `$$...$$`. A link of the README to
  a file that is no page, as `LICENSE`, is kept as written and its place named on the standard error: the build goes on,
  as it did when the README was no page.
- A book uses the project's own packages as another project writes them, `use deps/someone/shop/src/prices` when
  `[site] source` names `someone/shop`, read from the project itself, with no copy in `deps/`; the reference's page of a
  folder of the project names that path too. `norun` blocks are checked as `cesia check` checks and never run, not even
  the top of a package they use, so they need no engine and no `native` permission; a `toml` block marked `norun` isn't
  checked. Formulas write `\ast`, `\circ`, `\leftarrow` and `\mathrm` too, and the band of another project's site names
  the Cesia of its reference, as `Cesia 1.2.0`.
- Tabs in the docs: a `python`, `r` or `matlab` block right after a `cesia` block shows as a tab beside it,
  Cesia | Python | R | MATLAB, with no script; `tools/tabs.ce` runs each tab of Cesia's book, capped and with no
  network, and checks that it prints what its cesia block shows.
- For those who work on Cesia: `tools/test.sh` runs the typed path and the OCaml tests only, the change loop, 11 ->
  4.4 s; `tools/test.sh --no-spec` runs the same tests on the other path, and `tools/test.sh --slow` the tests slow by
  nature, on both paths; `tools/check.sh` runs those two after the loop, and the CI all three. The tests added since
  had made the loop 5.4 s again: it takes 4.0 s, as eleven tests of the JIT, whose loops are as long as the level 2
  they check needs, run with `--slow`, and the dev build has no `-g`, a start 2.64 ms instead of 2.86.
- The nightly pre-release is made again from main each time the CI passes there, from the commit it tested, so that
  projects that build against main test with it.

### Numerical methods

- `std/optimize`: `optimize.Root`, the zero of a function by Brent's method, from a bracket or one start, to the last
  float by default, tested on the 154 problems of Alefeld, Potra and Shi; `optimize.Minimize`, by L-BFGS with the line
  search of Moré and Thuente, and `optimize.Simplex`, by Nelder and Mead with the coefficients of Gao and Han, both
  tested on the 35 problems of Moré, Garbow and Hillstrom. An `Err` with the best point where there is no zero or no minimum.
- `std/ode`: `ode.Solve`, the method of Dormand and Prince with its dense output, a PI control of the step, events
  located by `optimize.Root`, and an alarm when the problem is stiff; `stiff = true` runs Rodas5P, a Rosenbrock method
  of order 5, with the Jacobian given by `jacobian =` or by differences. An `Err` with the solution so far at a blow-up,
  a NaN or past its steps. Lorenz on [0, 100] at `rtol = 1e-8` in 57 ms, against 605 for scipy and 7,549 for Octave.
  With `stiff = true`, Robertson's problem in 12.2 ms, Van der Pol's at mu = 1000 in 15.2, against 147 and 360 for
  scipy's `Radau` and 929 and 116 for Octave's `ode15s`; scipy's `LSODA`, Fortran, takes 9.1 and 11.3 ms, with errors
  100 times Cesia's on Van der Pol's.
- `std/quad`: `quad.Integral(f, a, b)`, QUADPACK's QAGS, QAGP at the `points` given and QAGI for an infinite bound,
  with Wynn's epsilon algorithm, in a native engine that calls `f` back: the same value and error estimate as scipy's
  `quad`, to the last bit, on 42 integrals, in 44.6 us against scipy's 79.8. `math.Inf`, the infinity.
- `std/sparse`: matrices in compressed columns, `sparse.Of` from triplets with every index checked, `Eye`, `Diags`,
  `Kron`, `Add`, `Scale`, `Transpose`, `Dense`, `Get` and `Mul`; `sparse.Solve`, as MATLAB's backslash, orders by
  approximate minimum degree, then factors by supernodes, multifrontal, Cholesky or LU on dense fronts through BLAS,
  with one step of refinement; `sparse.Read` reads Matrix Market files, every line checked. Poisson on 300 x 300 points
  in 315 ms (scipy 805, Octave 330), on 1000 x 1000 in 3.85 s (scipy 33.7, Octave 8.1).
- `num.Lu` factors a square matrix once, for many solves with its `Solve`; `num.Solve`, `Inverse` and `Det` go through
  the same native elimination, with the same bits as before: an `Lu` of order 100 in 0.65 ms instead of 3.6.

### Statistics

- `std/stats`: the laws Normal, StudentT, ChiSquared, FisherF, Uniform, Exponential, Gamma, Beta, Binomial and Poisson
  as values, each with `Pdf`, `Cdf`, `Quantile` (both with `upper = true` for the upper tail, computed directly) and
  `Sample`; `stats.Lm`, the linear model of R's `lm` without a formula, with `summary(lm)`'s table, `Predict`, `Band` and
  `Confint`; the tests `TTest`, `TTest2`, `WilcoxonTest`, `WilcoxonTest2`, `KsTest`, `ChiSquaredTest` and `CorTest`, each
  giving a `stats.Test`. Checked against values of 70 digits, NIST's datasets and R.
- `stats.MonteCarlo(f, n = ...)` or `(f, tol = ...)`: the mean of random draws, single or in batches, with its
  standard error and Student's interval, as a `stats.Estimate`; with `tol`, it draws until the interval is narrow
  enough, by the rule of Chow and Robbins. Its coverage is checked on 1,000 runs of each law.
- `std/special`: `Gamma`, `LogGamma`, `Beta`, `LogBeta`, `Erf`, `Erfc`, `Erfcx`, `ErfInv`, `ErfcInv`, `GammaInc` and
  `BetaInc`, from the papers of Cody, Wichura, DiDonato and Morris, and Temme.
- `num.Variance`, `num.Std` and `num.Covariance` take `sample = true`, which divides by n - 1 as R's `var`, `sd` and
  `cov`; the default stays numpy's n.

### Speed

Measured on the same machine as the others, in the book's chapters on speed and numerical methods:

- `json.Parse` reads a number without a copy of its text when it is short, and a list of numbers without a box for each:
  the scene of a surface of 100 by 100 quads, 192 KB, in 3.5 ms instead of 8.1, the same values to the bit.
  std/cells reads a long answer of its session once, not once a chunk.
- The cache of loaded packages: a package unchanged since the last run is neither lexed, parsed nor resolved again,
  its entry written once the run has ended, checked by its XXH64 checksum, in a folder of the person's alone:
  `use std/plot` starts in 5.69 ms instead of 9.66, Cemacs reaches its first frame in 36.97 ms instead of 52.16. A
  function's body is read from the cache at its first call: 4.03 and 50.62 ms. An entry places a used package's modules
  from its end, so two programs run in turn no longer resolve a package again: 0.4 to 1.2 ms a run.
- Loading makes half the garbage it made: Cemacs's 44 modules load in 24.4 ms instead of 38.2.
- A first graph costs the code it runs: a function that gives no number is inferred when it runs, not by each caller
  that might call it; a growing array of the core no longer empties the young heap first, as it did four times in a
  first `plot.Svg`; a cache entry is checked by XXH64, 7 times faster than BLAKE2b, and writes the number of a node in a
  byte most often. A first `plot.Svg` of a line in 6.99 ms instead of 10.29, of a surface 9.59 instead of 14.20, a
  session of cells that draws a line 7.74 instead of 11.54, `use std/plot` 4.08 instead of 4.38 (medians of 21 runs).
- The resolver's definite assignment costs the same per statement whatever the number of variables: a function of
  4,000 variables resolves in 6 to 7 ms instead of 120 to 190.
- The start is 1.1.0's again: the sources of std/ are strings that only code names, a program's stacks start small, the
  natives of std/ are joined by package in one pass over a table instead of a search of a list for each, and the tables
  of `text.Fold`, of `json.Parse`'s powers of ten and of the digits of an integer are constants of the binary instead
  of being made at each start: `io.Print(1)` in 2.52 ms, as 1.1.0 built the same way, against 2.63 before (medians of
  101 rounds of 50 runs, alternated, the release builds).
- `encode.Unbase64` of 1.4 MB, a page's screenshot, 572 -> 5.7 ms.
- The JIT makes a unit's machine code at MIR's level 1 first, in 30 to 60 % less time, and its level 2 in another
  domain once the unit is hot: Lorenz on [0, 100] 83 -> 66 ms, `structs` 51 -> 40, long runs at level 2's speed.
- The JIT reads and writes lists of integers by index, and checks the indexes that move with a loop's counter once,
  before the loop, and writes no jump to the block that comes next (24 jumps fewer in its unit): a sparse product 3.75 ->
  2.79 ns a non-zero. A variable that an inner loop assigns before it reads it, as a row read from a list, carries
  nothing from one turn of the outer loop to the next, so the inner loop called again starts as machine code instead of
  going back to the interpreter.
- The JIT keeps small arrays of floats in slots and inlines the functions that give them, goes back to the interpreter
  inside an if, and leaves it the statements it can't make, so the loop of `ode.Solve` is machine code; a loop whose
  statement left to the interpreter runs at nearly every turn stays in the interpreter: 1,011 -> 75 ms for 10^6 turns.
- A call through a value that none of the functions the JIT saw takes goes back to the interpreter with the fuel it
  has, as no callee stepped on the way: its statement no longer copies the fuel at its start at every turn.
  `bench/dyn.ce` in 58.9 ms instead of 64.0; 1.1.0 takes 55.4, 6 % less (medians of 101 runs, alternated): the test of
  the function by the identity of its code, which lets a function that a session defines again with the same code keep
  its machine code, and the start of the loop at MIR's level 1 cost the rest.
- A loop whose runs make fewer than 12 steps on average, as one of 2 or 3 turns in a function called often, stays in
  the interpreter: as machine code, coming in and going back at each run lost to the interpreter, 3 times slower at 2
  turns, and its making cost about 2 ms of the program's own time. Van der Pol's at mu = 1000 solved again after
  Robertson's, when two such loops of `ode.Solve` became hot, 20.6 -> 14.8 ms; a loop of 2 turns in a function called
  2 x 10^6 times 666 -> 319 ms. Once its runs grow, as for a larger problem, the loop gets its machine code.
- A function made machine code as a whole, after 1,000 calls, whose calls from the interpreter make fewer than 12 steps
  on average, as one with a loop of 2 turns called from a loop that the interpreter keeps, gets its interpreted calls
  back, its machine code kept: coming in and going back at each call made it 3 times slower than the interpreter.
  Called 2 x 10^6 times, 439 -> 161 ms at 2 turns, 222 -> 110 at 4, 117 -> 84 at 8, where the JIT off takes 138, 100
  and 81 (medians of 21 runs, alternated); from 12 turns on, as before. Its calls inside its machine code stay there, so
  a recursion called once, as `bench/fib.ce`'s, is untouched, and now and then its next calls go through its machine
  code again, which keeps them once they are long.
- `f()`, a call with no argument of a function held in a value, and `random.Float()` are machine code: `f()` 37 -> 2.2
  ns, 10^6 single draws of `stats.MonteCarlo` 539 -> 8.9 ms. `^`, `math.Exp` and the other functions of one float on an
  array of floats run unboxed, and `num.Uniform` draws in one native loop, the same numbers for a seed.
- `-x`, `math.Abs`, `list.Max` and `list.Min` on an array of floats in one native pass, and `num.Dot` without the array
  of products: 2 to 10 times faster at 1,000 floats, the same bits.
- A native that wakes many fibers from another domain writes the wake pipe once: when one native wakes 10,000 fibers,
  the last is awake in 9.5 ms instead of 11.6; `json.Text` of a small map in 314 ns instead of 390.
- `json.Text` and `json.Parse` take a text eight bytes at a time, and so does the length of a text: 1.6 MB 3.6 ->
  0.6 ms. `csv.Text` writes a list of lists natively, 5 times as fast; `text.Repeat` copies what it made, not a byte at
  a call, and `date.FormatDate` writes its usual years and two digits without padding.
- `cells.Variables` of a session that holds 10^6 numbers and a model fitted on 10^6 rows answers in 0.09 ms instead of
  4.1 s; `"$xs"` of 10^6 integers 131 -> 55 ms, of 10^6 floats 1080 -> 936 ms; the text of `[1, 2, 3]` 145 -> 120 ns.
- The text of a float, for `io.Print`, `"$x"`, `value.Text` and `json.Text`, by Ryu's tables (Adams, PLDI 2018)
  instead of up to three `printf` and two `strtod`, in the same bytes: `json.Text` of 32,000 floats 97 -> 3.9 ms, the
  scene of a Lorenz curve 30 -> 1.4 ms, `"$x"` of a float of 17 digits 2.9 us -> 0.19 us.
- `s.At` of an `ode.Solution` at an array of times walks the steps once, in native code: the 5,000 times of a Lorenz
  curve 86.6 -> 0.53 ms, in a scrambled order 66.7 -> 1.9 ms, a time alone 12.8 -> 2.7 us, the same bits; scipy's
  `sol.sol(t)` takes 48 ms.
- A cell run again, or code at the prompt, that defines a function with the same code keeps the machine code the JIT
  made with the one before: the solve cell of a Lorenz notebook run again 2.2 ms instead of 22.7 (53 to 64 ms while the
  JIT made ode's loop again at each run, then interpreted for good), and solving again with `lorenz` kept 2.2 ms instead
  of 23 once it had been run again (medians of 21 runs). A function defined again, the same or changed, no longer fills
  the four functions a call through a value remembers; a loop whose machine code paid for itself, or took a variable of
  a cell that the session ran again, no longer counts that drop toward giving up for good: the parameter cell of that
  notebook run again with a new number makes ode's loop again, 43 ms, instead of 22.7 ms interpreted for good after a
  few edits.
- A number set in place in a session, as `cells.Set` gives a slider's, no longer makes the machine code of the loops
  that read it again at each step: machine code reads the numbers of the modules a session runs from slots at each run,
  checked of their kind, and so it does for a variable that the top code of a file gives again, once it changed. A
  slider step of the Lorenz notebook, `rho` set and the solve cell run again, takes 2.6 ms instead of 24 (2.9 instead of
  28 on average), and solving again after the steps 2.8 ms instead of 26 (medians of 21 steps, five rounds).

### Fixes

- On a phone no page of the site scrolls sideways: the header takes a second line, long links and code wrap, and a
  formula wider than its line scrolls in its own box.
- `http.Fetch` names the port in `Host` when it isn't the scheme's own, so that a server that compares a page's
  `Origin` with its `Host` finds the same text.
- `cesia lsp` finds a name of a package of the project, as `shop.Total`, in its open buffers before the disk, with its
  doc text for hover.
- Machine code no longer runs on with an old number of a module variable that a function it calls read, as `k` in a
  loop's `g(x)` after `k = 5`: the numbers each function of the code took are checked before each run, not only the
  loop's own.
- A module's variable that the top code gave another number while another fiber's machine code that reads it waited at
  a full checkpoint no longer stops the program with an internal error: the code reads the new number at its next run,
  or a loop gives the rest of its turns to the interpreter at its next step.
- Under `CESIA_JIT=always`, a loop that calls through a value, as `f(x)` in `run(f, n)`, gets machine code again: lowered
  at its start, before that call had met any function, it stayed interpreted for good, so the tests and the fuzzer that
  run in that mode compared such loops with the interpreter itself. A loop refused then is now lowered once more after
  its first steps, as one hot by its runs is; the default mode, which lowers a loop only after steps, is unchanged.
- The full list is in the commits since v1.1.0.

## 1.1.0

Everything here is added: a program written for 1.0 runs as it did.

### Language

- `a if c else b`, the value first as in Python: the same tree as `if c a else b end`, so it costs nothing when it runs.
- `return x if c` and `break if c`, when the condition ends the line, as in Ruby: the same tree as `if c return x end`.
- `fiber.Channel(size = n)` holds n values at most; `fiber.Close`, `fiber.Select` with a timeout, `fiber.Cancel`, and
  `fiber.Wait(task, timeout =)`.
- `sys.Write(path, text, sync = true)` answers once the file and its folder are on the disk; `text.ByteFind(..., fold = true)`
  ignores the case of ASCII letters; `text.IsUtf8` and `text.Count`; `sys.ReadInput(count)`; `sys.Start(..., dir =)`.

### Servers

- `cesia run --workers N` serves one listener from N processes; HUP replaces them without a failed request; TERM and INT
  stop a server cleanly; `sys.Stops` tells every fiber of a stop.
- `std/log` writes a JSON line per event and `std/metrics` counts for Prometheus; `http.Serve` holds under abuse.

### Tools

- `cesia lsp`, a language server: the marks of `cesia check` as you type, the docs under the cursor, definitions, completion.
- `cesia fmt` writes files in the style of Cesia's code and checks that each keeps its tree.
- Native packages: a package's engine in OCaml, compiled once against `Cesia_v1`, runs its natives under `native=LABEL`.

### Speed

Measured on the same machine as the others, in the book's chapter on speed:

- `fib` 74 -> 58 ms, ahead of Java's 71; maps 253 ms, ahead of Go's 272;
- a fiber 3.4 us and 2.1 KB, less memory than a goroutine;
- a start in 2.62 ms;
- HTTP: a tiny route 67k requests a second, beside Go's 67k, and JSON 48k, ahead of Node's 41k.

### Fixes

- An example's check that waits no longer overwrites the variables before it.
- The tests run on macOS's own tools; on a phone, the site's contents come first, above the text.
- The full list is in the commits since v1.0.0.

## 1.0.0

Cesia is a small language for solving real problems directly: a script that cleans a CSV, a web server on a database, a
program that drives other programs. It starts at once, it runs a program safely by default, and when something goes wrong
it says what to write. One binary holds the language, its tools and its libraries, on Linux, macOS and Windows.

From 1.0 on, the first number of a version rises when a change can break a program, the middle one when something is
added, and the last one for a fix. A program written for 1.0 runs on every 1.x.

### What is in it

- The language: numbers, texts, lists and matrices that compute as a whole, dictionaries, structs with methods, interfaces,
  `match` on shapes, functions as values, `it` and `then` for short steps, comprehensions, and optional types that check
  what comes in. Errors are values, `result.Ok` and `result.Err`, passed on with `?`; bugs stop the program with their
  line and what to write instead. Every short form has its plain function beside it: `a..b` is `list.Range(a, b)`.
- Safety: a program touches nothing outside itself until its command line allows it, with `--allow` for files, the
  network, other programs, the environment and C libraries, each as narrow as a folder or a port; `--limit` caps its
  memory, its steps and its depth.
- Speed: an interpreter that specializes functions by the types it sees, and a JIT that turns hot code into native code.
  The JIT, SQLite, the debugger and the test engine are plugins loaded at their first use, so a program starts in about
  2.5 ms.
- The tools: `cesia run` (with `--watch` to reload at each save, `--repl`, `--debugger`, `--seed`), `cesia test`,
  `cesia check`, `cesia do` for the tasks of `cesia.toml`, `cesia new`, `cesia pkg` for dependencies from git with a lock
  file, `cesia doc` and `cesia doc --site`, `cesia upgrade`.
- The libraries, in `std/`: lists, texts, dictionaries, math, matrices and numerical work, tables of columns, JSON, CSV,
  regular expressions, dates, paths, flags, random numbers, files and processes, fibers and channels, HTTP and web
  applications, WebSocket, TLS, cryptography, SQLite, Markdown, and C and C++ libraries through `std/c` and `std/cpp`.
- The book, which teaches Cesia from the start to a real program, and the reference of every name, both on one site whose
  examples run at each build.

### New since 0.2

- `cesia run --repl`: a prompt beside the running program, in its main file's package; a function defined again replaces
  the program's own. A debugger in Cesia: conditional breakpoints, a stop on each error with every variable, any
  expression in a frame, frames up and down, watches, and fix and continue. Both work with the JIT.
- `cesia check` reads a project without running it: names, arguments, types, and results whose `Err` would go unseen.
  `Int!` says that a function gives an `Int` or an `Err`, and `_ =` drops a result on purpose.
- Tests: a failure shows the value of each part it compared; `math.Near`; properties with `test.ForAll` and the
  generators of `std/gen`, which shrink a failure to the smallest case; `test.Snapshot`; `test.Temp`; tests in parallel
  workers, each with a deadline and its own listeners.
- `std/random` with `--seed`, `std/path`, `std/flags`, `sys.Walk`, `date.Local` and offsets, `text.Decimals`,
  `io.PrintError`, `sys.ReadInput` and `sys.Exit`.
- The JIT: hot functions and loops become machine code, numbers, arrays, maps and structs included, with the same
  results as the interpreter. It runs on x86-64; on arm64 it is off for now, and programs run interpreted.
- Arrays of three dimensions and more: `matrix.Zeros(2, 3, 4)`, `a[i, j, k]`, `value.Size`, `matrix.Reshape([2, 3, 4], xs)`,
  sums and means along a dimension with `list.Sum(a, dim = 3)`, and arithmetic element by element, natively in the JIT.
- `std/sql` on SQLite, with a pool, typed rows and transactions; channels between fibers; one storage for every map;
  `From` and `Fields` between structs and dictionaries.
- Every error shows in one form, its place and then its message, at the prompt and in the debugger too.
- Releases with their C libraries beside the binary, `install.sh`, `install.ps1` and `cesia upgrade`.

### Breaking changes since 0.2, and what to write

- No name is global. Each file uses the packages of `std/` it needs: `use std/io`, then `io.Print(x)`; `list.Map`,
  `text.Split`, `result.Ok`, also in patterns: `result.Ok(v) -> v`. A name written alone says which use it needs.
- A variable, parameter, function or pattern named as a package the file uses is refused: with `use std/text`, name a
  text `s` or `line`, not `text`.
- A range is written `a..b`, short for `list.Range(a, b)`; `a:b` stops with a message that says so.
- A use says where its code comes from: `use std/csv` for what comes with Cesia, `use src/shapes` for a folder of the
  project, from its root, and `use deps/OWNER/REPO/...` for a dependency. The folder `pkg/` is now `std/`: run
  `cesia pkg install`.
- `--allow net=:8080` listens on this machine only, 127.0.0.1 and ::1. To take connections from other machines, write
  the address too: `net=0.0.0.0:8080`. A test gets `net=own`: its own listeners only.
- `std/sdl`, `std/ui`, `std/rope` and `std/history` left Cesia, for the editor that uses them, and releases no longer
  hold SDL3: a program that opens it gets it from the system.
- A quote inside a text is written `\"` only: two quotes in a row are an error that says what to write.
- The inner parts of `std/http` and `std/websocket` are private. `net.Size`, `net.Find` and `net.SplitAt` are gone:
  `text.ByteLength`, `text.ByteFind` and `text.ByteSlice` do the same. The names renamed or removed before 1.0 are listed
  below.
- `sql.Open` on a file needs read and write for the files SQLite keeps beside it, `-wal`, `-shm` and `-journal`, as for
  the database itself: grant its folder, as `--allow read=data,write=data`.
- A struct of one field shows its value alone, as the code builds it: `Ok(42)`, `Err("no")`, no longer
  `Ok(Value = 42)`. A struct of more fields still shows their names. At the `--repl` prompt, a text shows with its quotes,
  `"HELLO"`, as `-->` writes it.

### Renamed and removed before 1.0, old -> new

One way for each thing: none of the old names stays beside the new one, and a program that uses one stops at its load
with the usual message.

- std/web is merged into std/http; http.Get, http.Post and http.Request become http.Fetch:
  - `use std/web` -> `use std/http`, and `web.X` -> `http.X` for `App`, `Route`, `Get`, `Post`, `Delete`, `AnyMethod`,
    `Wrap`, `Plain`, `Html`, `Redirect`, `NotFound`, `WithHeader`, `SetCookie`, `Form`, `BodyJson`, `Handler`,
    `Websocket`, `Logger`, `Cors`, `FileResponse`, `Static`, `Escape`, `Template`
  - `web.PutRoute` -> `http.Put`; `web.SendJson` -> `http.Json`; `web.Serve(app)` -> `http.Serve(app)`
  - `http.Get(url)` -> `http.Fetch(url)`; `http.Post(url, body)` -> `http.Fetch(url, method = "POST", body = body)`;
    `http.Request(method, url)` -> `http.Fetch(url, method = method)`
  - `http.Serve(handler)` -> `http.Serve(app)`: a bare handler becomes `http.App() then http.AnyMethod("*", handler)`
  - `web.GetHeader` -> `http.HeaderValue`
  - `websocket.Accept(headers, onMessage)` -> `websocket.Accept(key, onMessage)`, the key of the request;
    `http.Websocket` checks the request and calls it
- Private now, with no public name: `http.Blank`, `http.Crlf`, `http.MaxHead`, `http.Render`, `http.ReadResponse`,
  `http.ParseResponse`, `http.WaitForConnections`, `http.Plain` (the wrap without TLS: `wrap` left out of `http.Serve`
  means plain TCP); `net.Arm`, `net.Reap`, `net.OpenCount`, `net.IsHeader` (inside std/http); `debug.Words` (inside
  the debugger); `date.DaysFromCivil`; `text.XorBytes` (inside std/websocket). The connection a `wrap` gives has
  `Read`, `Write` and `Close`: std/http sets the deadlines itself.
- Arguments, the function or the sizes first and the data last:
  - `matrix.Reshape(xs, rows, cols)` -> `matrix.Reshape([rows, cols], xs)`, the shape as a list of sizes
  - `algo.Bfs(start, neighbors)` -> `algo.Bfs(neighbors, start)`; `algo.Dfs` the same
  - `algo.Dijkstra(start, edges)` -> `algo.Dijkstra(edges, start)`
  - `algo.TopologicalSort(nodes, needs)` -> `algo.TopologicalSort(needs, nodes)`
- A question starts with Is or Has: `set.Member` -> `set.Has`; `set.Subset` -> `set.IsSubset`; `cesia.Dev` ->
  `cesia.IsDev`; `debug.Complete` -> `debug.IsComplete`; `crypto.Same` -> `crypto.IsSame`
- Removed, with what does the same:
  - `list.Every(f, xs)` -> `list.All([f(x) for x in xs])`; `list.Some(f, xs)` -> `list.Any([f(x) for x in xs])`
  - `list.Butlast(xs)` -> `list.DropLast(1, xs)`; `list.Rest(xs)` -> `list.Skip(1, xs)`
  - `fn.Pipe(x, f, g)` -> `x then f() then g()`; `fn.Partial(f, a)` -> `x -> f(a, x)`, or `f(a, it)` in an
    argument, as `list.Map(math.Add(2, it), xs)`
  - `set.Count(s)` and `queue.Count(q)` -> `value.Len(s)` and `value.Len(q)`
  - `num.SumCols(m)` -> `list.Sum(m, dim = 1)`; `num.SumRows(m)` -> `list.Sum(m, dim = 2)`: the same lists
  - `num.Seeded(seed)` -> `cesia run --seed N`: `num.Uniform(n)` and `num.Normal(n)` take no generator and give a
    list, drawn by std/random as `random.Float` is
- Renamed: `csv.Write` -> `csv.Text`; `frame.Rows` -> `frame.RowCount`; `fn.Comp` -> `fn.Compose`; `syntax.String` ->
  `syntax.Text`
