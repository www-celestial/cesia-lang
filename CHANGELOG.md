# Changelog

## 1.3.0

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

### Science

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
- `cells.Show(x)` shows a value under the cell that runs, at its place among what the cell prints, as `display` does in
  Jupyter: two graphs, or a table then a graph, in one cell. `cells.Run` gives them in its new Shown, each with its place
  among the lines of Output; each graph has its own Key for `cells.Scene`; the page of `cells.Html` shows them in order.
  Out of a session, as under `cesia run`, Show only gives its value.

### Tools

- `cesia doc --site` colors the blocks of `python`, `r`, `matlab`, `ocaml`, `js`, `lua`, `bash`, `sh`, `powershell`,
  `toml`, `ini` and `css`, the tabs too, with the colors of Cesia's code: keywords, called names, texts, numbers and
  comments, the variables of a shell, the keys and sections of `toml` and `ini`, the properties of `css`. It colors them
  as it builds, with no script, in the time the site took before.

### Fixes

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
