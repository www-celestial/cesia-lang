# Compiling to WebAssembly

In this chapter you compile a Cesia program to WebAssembly and run it in a web page and in Node, with the same output, the
same errors and the same numbers as `cesia run`. [WebAssembly](glossary.md#webassembly-and-wasmgc) is a format of code
that every current browser runs, near the speed of machine code, inside the page's [sandbox](glossary.md#sandbox).
`cesia build` compiles the program [ahead of time](glossary.md#ahead-of-time-compilation): the page holds your program
and the few functions of the runtime it uses, and no interpreter.

It compiles numbers, texts, lists, maps and dictionaries, functions and closures, `if`, `match` and loops, results, `?`
and `!`, errors, and [fibers](#fibers) with their channels; a program calls the [JavaScript](#javascript) of its page by
`js.Call`, and a long one leaves the page fluid. What it doesn't compile yet is an error at the build, at its place: see
[What it compiles](#what-it-compiles).

## The command

```bash
cesia build --target wasm file.ce
```

It writes three files beside `file.ce`: `file.wasm`, the module; `file.js`, its loader, which fetches the module, starts
it and writes what it prints; and `file.sites`, the places of its errors, which the loader reads at the first error only.
A program that uses packages gets them in the same module, compiled with it, and the JavaScript modules that it calls
by `js.Call` beside it ([JavaScript](#javascript)). Building again replaces them. `file.js` is plain JavaScript of 250
lines, with no package to install and no step after it.

When something can't be compiled yet, the build stops at its place, writes no file, and gives the exit code 1:

```text
area.ce:3:1: a declared result type isn't compiled to WebAssembly yet.
  3 | defn area(r Float) Float
    | ^
  cesia run runs it; cesia build --target wasm compiles part of Cesia for now.
```

An error of the program itself, a syntax error or a name that doesn't exist, is the error `cesia run` gives, at the
build. A `file.js` of the same name that `cesia build` didn't write stays as it is: the build stops with the exit code 2,
and says to move it or to build a file of another name.

## A first program in a page

The program computes the monthly payment of a loan, then, for the first months, how much of each payment goes to
interest and how much is still owed. A loan of nothing is an `Err`, which the program writes as such:

```cesia
(* loan.ce *)
use std/io
use std/result
use std/math
use std/list

(* The monthly payment of a loan, by the classic formula of annuities: p × r / (1 − (1 + r)^−n). *)
defn payment(principal, yearly, years)
  if principal <= 0 or years <= 0
    return result.Err("a loan needs an amount and a number of years above 0")
  end
  r = yearly / 12
  n = years * 12
  result.Ok(principal * r / (1 - (1 + r) ^ -n))
end

cents(x) = math.Round(x * 100) / 100

defn schedule(principal, yearly, years, months)
  pay = payment(principal, yearly, years)?
  owed = principal
  rows = []
  for m in 1..months
    interest = owed * yearly / 12
    owed = owed - (pay - interest)
    rows = list.Append({Month: m, Interest: cents(interest), Owed: cents(owed)}, rows)
  end
  result.Ok({Payment: cents(pay), Rows: rows})
end

defn show(s)
  io.Print("Each month: $(s.Payment)")
  for row in s.Rows
    io.Print("Month $(row.Month): $(row.Interest) of interest, $(row.Owed) still owed")
  end
end

for loan in [{Amount: 200000.0, Years: 25}, {Amount: 0, Years: 25}]
  match schedule(loan.Amount, 0.04, loan.Years, 3)
    result.Ok(s) -> show(s)
    result.Err(e) -> io.Print("No schedule: $e")
  end
end
```

Save it as `loan.ce` in a folder of its own, and build it:

```bash
cesia build --target wasm loan.ce
```

The folder now holds `loan.wasm` and `loan.js`. In Node 22 or later, the loader runs the program at once, and prints
the same lines as `cesia run loan.ce`:

```bash
node loan.js
```

In a page, the loader is a module script. Save this as `index.html` beside them:

```html
<!doctype html>
<meta charset="utf-8">
<title>Loan</title>
<p>The schedule is on the console: press F12.</p>
<script type="module" src="loan.js"></script>
```

A browser runs a module script only from a server, never from a file opened on the disk. [http.Static] serves the files
of a folder, so the server is two lines of Cesia. Save them as `serve.ce`:

```cesia norun
(* serve.ce: the files of this folder, on port 8080 of this machine. *)
use std/http
http.Serve(http.App() then http.Static("", "."))
```

Run it, with the right to read the folder and to listen on the port, then open <http://127.0.0.1:8080/index.html>:

```bash
cesia run --allow read=.,net=:8080 serve.ce
```

The console of the page (F12) shows the five lines that `cesia run loan.ce` prints, one message each. This page ran
so in Chrome 158, and `node loan.js` in Node 26, both the same as `cesia run loan.ce`, byte for byte.

## Output and errors

`io.Print` writes to the standard output in Node, and to the console of the page, one call of `console.log` per line.
An error writes what `cesia run` writes, the message, its line with the mark under it, the hint and the calls that led
there, to the standard error in Node, which then exits with the code 1, and through `console.error` in a page. Then the
program stops: nothing after the error runs. In `typo.ce`, the second call gives `cents` a text where a number was meant:

```text
(* typo.ce *)
use std/io
use std/math

cents(x) = math.Round(x * 100) / 100
io.Print(cents(1055.666))
io.Print(cents("1055.666"))
```

`node typo.js` writes, byte for byte as `cesia run typo.ce`:

```text
1055.67
typo.ce:4:25: Can't multiply the text "1055.666" by the number 100.
  4 | cents(x) = math.Round(x * 100) / 100
    |                         ^
  To put a value in a text, write "...$x" or value.Text(x).
  in cents (typo.ce:4)
```

The message comes from the same table as the interpreter's. The places of the errors, each line of code with the marks
under it, are in `typo.sites`, beside the module, which the loader reads only when an error happens: a page that runs
without one never loads it, and in a page the error is written once that file came.

The limits are those of `cesia run`: 10,000 calls deep at most, then the error `Limit "depth" reached.`, at the same
place, with the same calls named.

## What it compiles

| Compiled | Not yet |
|---|---|
| integers of 63 bits, checked as `cesia run` checks them; floats; true, false and missing | methods, interfaces |
| texts in UTF-8, `$` in texts, comparing them | types declared on parameters and results |
| lists, arrays of floats and of integers, ranges, comprehensions, `x[i]`, `x[a..b]`, a mask, `m[i, j]`, and their writes | `for x in` a channel |
| maps written as literals, their fields, `m["key"]`, `m.Name = v`; dictionaries of keys of numbers and texts, `in` | an index of three dimensions |
| functions, closures, functions as values, recursion | the packages of the system: files, processes, sockets but the WebSocket |
| `if`, `match` and its patterns, `for`, `while`, `return` | |
| `result.Ok`, `result.Err`, `?`, `!`, `bug.Panic` and errors | |
| [fibers](#fibers): `fiber.Spawn`, `Wait`, `Cancel`, `Channel`, `Send`, `Receive`, `Select`, `Close`; `sys.Sleep`, `sys.Now` | |
| [JavaScript](#javascript): `js.Call`, and `std/websocket` through the WebSocket of the page | |

A map keeps its keys in the order of insertion. Past 8 keys it finds them by a table of their hashes, as the table of a
map of `cesia run` that nothing else holds ([How Cesia works](internals.md#maps-a-hash-table-then-a-hash-trie)), each
table with a seed drawn at random, so that nobody outside can choose keys that fall together, and drawn again when keys
fall together all the same. The 500,000 keys of `bench/maps.ce`, written one by one then each read once, take 413 ms in
Node, against 342 for `cesia run` ([Speed and size](#speed-and-size)). A write to a map that another variable holds
copies it whole, where `cesia run`'s trie copies one branch: a map of many keys that a function gets, writes and gives
back costs a copy at each call.

Of the standard library, these compile: `io.Print`; `math.Div`, `Mod`, `Abs`, `Floor`, `Ceil`, `Round`, `Sqrt`, `Exp`,
`Log`, `Sin`, `Cos`, `Tan`, `Asin`, `Acos` and `Atan`; `list.Sum`, `Append`, `Concat`, `Take`, `Skip`, `Reverse`,
`Fill`, `Max`, `Min`, `Sort`, `Order`, `Unique`, `Flatten`, `IndexOf`, `Any`, `All`, `Mean` and `Zip`; `matrix.Zeros`,
`Ones`, `Reshape`, `Matmul` and `Transpose`; `dict.Dict`, `Get`, `GetOr`, `Has`, `Put`, `Drop`, `Keys`, `Values` and
`Pairs`; `text.ByteLength`, `Byte`, `ByteSlice`, `ByteFind`, `StartsWith`, `EndsWith`, `Contains`, `Find`, `Slice`,
`Split`, `Join`, `Replace`, `Trim`, `Lower`, `Upper`, `Repeat`, `Chars`, `Code`, `Char`, `Number`, `Decimals`, `Str`,
`Numbers` and `FromNumbers`; `json.Parse` and `json.Text`; `columns.Pick`, `Positions`, `Kind`, `Groups` and `Split`;
`regex.Test`; `random.Float`; `value.Len`, `Text`, `Equal`, `Size` and the tests `IsInt` to `IsMissing`; and the
packages written in Cesia, as `std/result`, `std/plot` or `std/websocket`, as far as they use what this table compiles.
The fibers have [their section](#fibers).

A page has no interpreter to call a native of: the compiler writes each one in WebAssembly, or, where Cesia says it as
well and fast enough, takes a version of its package written in Cesia, in `src/web/` of Cesia's sources: `list.ce`,
`json.ce`, `columns.ce`, `matrix.ce`, `regex.ce` and `websocket.ce`, each function the native of the same name, with its
results and its errors. `regex.Test` runs the `RegExp` of the page: its patterns are JavaScript's, which the common ones,
classes, groups, anchors and repeats, share with Cesia's.

## Fibers

A program compiled to WebAssembly has the fibers of [std/fiber](fibers.md), with the same order as `cesia run`: a
fiber that waits lets the others run, the first ready first, and a program that waits for what nothing can bring stops
with the same error, `All fibers are waiting and nothing can wake them.` This one runs three fibers, a producer, a
channel of size 1 between them, and a wait with a timeout:

```cesia
(* relay.ce *)
use std/fiber
use std/io
use std/result
use std/sys

ch = fiber.Channel(size = 1)
producer = fiber.Spawn(defn ()
  for k in 1..3
    fiber.Send(k * 10, ch)
  end
  "sent"
end)
got = [result.Unwrap(fiber.Receive(ch)) for k in 1..3]
io.Print(got, fiber.Wait(producer))
io.Print(fiber.Receive(ch, timeout = 0.05).Error.Kind)
slow = fiber.Spawn(() -> sys.Sleep(10))
fiber.Cancel(slow)
io.Print(fiber.Wait(slow).Error.Kind)
```

`node relay.js` and a page print what `cesia run relay.ce` prints:

```text
[10, 20, 30] Ok("sent")
timeout
cancelled
```

*How.* WebAssembly has no fibers of its own yet, and four ways were weighed, each measured or tried:

- [JavaScript Promise Integration](glossary.md#javascript-promise-integration) (JSPI) lets a call of the module wait for
  a promise of JavaScript: the engine sets the whole stack of the call aside, frames, locals and all, and takes it up
  again when the promise is resolved. The main program and each fiber are such calls; a fiber that waits gives the
  loader a promise, which the loader resolves when its turn comes. Measured with a module of 155 bytes that waits
  100,000 times in a row: one wait and its return cost 0.17 µs in Node 26, 0.66 µs in Chrome 158 and 2.9 µs in Firefox
  160; a call that doesn't wait, 9 to 13 ns. A page waits for a socket or a click, not a million times a second, and code
  that doesn't wait pays nothing. It runs in Chrome since its version 137 (May 2025), in Firefox since 153 (July 2026),
  in Safari since 27 (fall 2026), and in Node 26.
- Asyncify, the pass of Binaryen that rewrites each function to unwind its stack into the memory and wind it back,
  can't hold the references of WasmGC that Cesia's values are: `wasm-opt --asyncify` on a module of WasmGC stops with
  "Asyncify does not yet support non-number types, like references".
- The proposal of stack switching (WasmFX), whose continuations are the fibers themselves, runs in no browser without
  a flag yet.
- A program turned by the compiler into a state machine, each function that may wait cut at its waits, would cost
  every call through a value, where the compiler can't know whether the callee waits, and every function of the
  standard library.

So JSPI. The scheduler is the loader's, as the interpreter's: one fiber runs at a time, in the order of the ready queue,
each next one started by a microtask of JavaScript; what wakes a fiber, a value sent, a timer, a message of a socket,
puts it at the end of that queue. A fiber that waits keeps its depth of calls and their sites, so that an error in it
names its own calls, as `cesia run` does; a panic in a fiber is the `Err` of its task, after its message.

*A page stays fluid.* A program runs on the thread of the page: while it computes, the page paints nothing and takes no
click. At each checkpoint of its fuel, every 62,500 steps, the loader looks at the clock; past 8 ms, the program waits
for the event loop of the page, which paints and takes its events, then goes on, first. That costs a message of
JavaScript, a few microseconds, and once a frame's time has passed it goes through the browser's next frame: Firefox,
between messages alone, paints 12 times a second. And every million steps, as `cesia run`, the fibers ready run.
Measured on a loop of 500 million square roots in one call, 2.1 seconds, with a page that counts its frames:

| | Chrome 158 | Firefox 160 |
|---|---|---|
| Frames while the loop runs, yielding | 128 to 130, each 16.7 ms apart | 141 to 144, 17.1 ms apart (p50), 33 to 50 (p99) |
| Frames while the loop runs, without yielding | 0 | 1 to 3 |
| Time of the loop, yielding / without | 2,150 to 2,187 / 2,112 to 2,120 ms | 2,457 to 2,505 / 2,302 to 2,325 ms |

The loop costs 2% more in Chrome and 8% in Firefox, and the page paints every frame. A `setTimeout` instead of the
message cost 55% more, waiting 4 ms each time; `scheduler.postTask` and `scheduler.yield()` left Firefox at 12 frames a
second, and the second Chrome too.

## JavaScript

[js.Call]`(module, name, args)` calls the function `name` of a module of JavaScript: a path
beside the Cesia file that calls it, as a `use` is, which `cesia build` puts beside the program, or `cesia:websocket` and
`cesia:regex`, the loader's own. Both are written in the call, as texts: the module's imports say all that a program
calls. A value goes to JavaScript as JavaScript takes it, and comes back the same way:

| Cesia | JavaScript |
|---|---|
| a text | a `Uint8Array` of its bytes, which `new TextDecoder().decode` makes a string; a string comes back as its UTF-8 |
| an integer, a float | a number; a whole number comes back as an integer |
| true, false, missing | `true`, `false`, `null`; `null` and `undefined` come back as missing |
| a list | an array |
| a channel of std/fiber | a handle: `send(value)` puts a value in it, `close()` closes it |

That is the one way out, a call, and the one way in, a channel that JavaScript fills: a click, a message, a timer of
the page comes to the program as a value on a channel, where a fiber waits for it. A dictionary or a function doesn't
cross: its JSON text does, with `json.Text`.

Here a button counts its clicks. The program asks `page.js` to send each click on its channel, then waits for them one
by one; between two, it waits, and the page is free:

```cesia norun
(* counter.ce: counts the clicks of a button of the page; between two, the program waits and the page is free. *)
use std/fiber
use std/js

clicks = fiber.Channel()
js.Call("./page.js", "Start", [clicks])
n = 0
while true
  _ = fiber.Receive(clicks)
  n += 1
  js.Call("./page.js", "Show", ["$n clicks"])
end
```

`page.js`, beside it, is the page's side:

```js
// page.js: the page's side of counter.ce. A text comes as the bytes of its UTF-8, a channel as a handle.
export function Start (clicks) {
  document.querySelector('button').addEventListener('click', () => clicks.send('click'))
}
export function Show (text) {
  document.querySelector('output').textContent = new TextDecoder().decode(text)
}
```

And `index.html`, which loads the program:

```html
<!doctype html>
<meta charset="utf-8">
<title>Counter</title>
<button>Click</button> <output>0 clicks</output>
<script type="module" src="counter.js"></script>
```

`cesia build --target wasm counter.ce`, then serve the folder as for [the loan](#a-first-program-in-a-page): three
clicks write `3 clicks`, in Chrome 158 and in Firefox 160.

*The WebSocket.* In a program compiled to WebAssembly, [websocket.Dial], `websocket.Send` and `websocket.Close`
are the WebSocket of the page, or of Node, through `cesia:websocket`, with the same arguments and results: `Dial` gives a
`Conn` whose `Messages` receives each message, and that closes when the connection ends. The browser makes the
handshake and sends its own headers, its cookies and its origin: `headers` must be empty there. A message comes whole,
and nothing waits for a full `Messages`, since a browser can't slow its server down.

Ceres, the user interface of the project, runs its pages so: compiled to WebAssembly, its loop waits on a channel of
the page's events, and its live screen is a WebSocket of the page.

## How it works

The compiler is a plugin of Cesia, `cesia_wasm.cmxs`, which only `cesia build` loads: `cesia run` never pays for it. It
loads the program as `cesia run` does, then compiles each function once for each kind of arguments it is called with, as
the JIT does: where the types are known, an integer is an `i64` of WebAssembly, with the checks of Cesia's 63 bits, and
a float an `f64`, both in the machine's registers; elsewhere, a value is a reference to an object of
[WasmGC](glossary.md#webassembly-and-wasmgc), the garbage collector of the browser itself, so that the module brings no
collector of its own. An integer that fits in 31 bits is an `i31ref`, a reference that holds the number with no object
behind it. A map literal shares its keys with every map of the same literal, and each read of a field remembers the keys
it met last and where the field was in them: the next read of a map of the same keys takes the value at once, as an
[inline cache](references.md#the-jit).

Three things make this code fast in the engines of the browsers:

- *Each loop in a function of its own.* V8 and SpiderMonkey, the engines of Chrome and Firefox, compile a function first
  with a quick compiler, then, once it has run a while, again with their optimizing one; a call that is running stays in
  its first code. So each `for` and `while` is a function of its own, a chunk, which runs at most 16,384 turns a call
  and is called again while the loop goes on: its next call runs the optimized code. The variables of the loop go in and
  come back, a `return` or a `?` inside leaves through the caller, and a float array that the loop only reads is taken
  once.
- *Typed maps.* A map literal whose keys are written in the code, and the kinds of whose values the compiler knows, as
  `{X: i * 1.0, N: i}`, is a struct of WasmGC with a field of each kind, an `f64` for a float, an `i64` for an integer,
  nothing in an object of its own. Everything else, `Print`, `==`, a pattern, `m.Name = v`, sees a map.
- *Guesses, tested first.* A statement that reads `p.X` of a variable `p`, where `p` may hold a typed map, the only one
  whose keys hold every field that the function reads of `p`, has two versions: the first tests that `p` holds that map,
  one test, then reads its fields as the numbers they are; the second, for when the test fails, is the general code. A
  variable that the function only ever sets to floats, as a sum, is guessed the same way. A wrong guess costs a test,
  never another result: the general version runs.

Each function of the runtime, the printing of a float or the arithmetic of two values of unknown type, goes into the
module at its first use only: a program that never divides has no division in its module, and only the types that its
code uses are written. The texts of messages are bytes of a data segment, one byte each. The module and the loader are
written by Cesia itself, with no tool of WebAssembly to install.

## Speed and size

The six programs of [Speed](speed.md#computing), `maps` among them, and `bench/points.ce`, 1,000 maps `{X, V}` each
moved 2,000 times and written back into their list, compiled to WebAssembly and run in Node 26.13 (V8), in Chrome 158
(V8) and in Firefox 160 (SpiderMonkey), both headless, beside the same programs written in JavaScript, run in the same
engine, and beside `cesia run`. One machine, an Intel Core i7-4720HQ of 2015, 8 logical cores, Linux 7.2, on 2026-11-25,
while other work ran on it (load 2.0 to 3.0): milliseconds, medians of 5 runs, the sides taken in turn so that the load
fell on each, a new process for each run in Node and a new browser for each round. The times are those of the program
alone, once its module is loaded; `cesia run`'s is the whole command, its start of about 5 ms included. The faster of
each engine is in bold.

| Program | Node, WebAssembly | Node, JavaScript | Chrome, WebAssembly | Chrome, JavaScript | Firefox, WebAssembly | Firefox, JavaScript | `cesia run` |
|---|---:|---:|---:|---:|---:|---:|---:|
| `fib` | **121** | 141 | **116** | 120 | **146** | 187 | 63 |
| `mandel` | 58 | **57** | 58 | **54** | 107 | **56** | 64 |
| `matmul` | 171 | **61** | 198 | **62** | 231 | **84** | 48 |
| `structs` | 151 | **142** | 138 | **112** | 314 | **109** | 42 |
| `dyn` | 310 | **137** | 260 | **129** | 385 | **116** | 64 |
| `points` | 53 | **34** | 41 | **29** | 98 | **37** | 54 |
| `maps` | **413** | 583 | **349** | 414 | 517 | **479** | 342 |

The first slice of this compiler took, in Node, 124 ms for `fib`, 91 for `mandel`, 904 for `matmul`, 923 for `structs`,
1,103 for `dyn` and 148 for `points`, and `maps` hadn't ended after 100 seconds.

**Where WebAssembly wins.** On calls of functions on numbers: `fib`, 30 million calls on integers of 63 bits checked at
each step, in the three engines, against JavaScript, whose numbers are floats with no check. On a map of many keys:
`maps`, 500,000 keys of text, in Node and Chrome. And `mandel` and `structs` come within 2 to 24% of JavaScript in Node
and Chrome.

**Where JavaScript wins, and why.**

- *The checks of `matmul`.* Each of its 27 million turns reads two cells of arrays: Cesia checks each index against the
  count of the array, then WebAssembly checks it again against its store, and each `i * n + k + 1` is checked against
  the 63 bits of Cesia's integers. V8 knows from the loop that the index stays in its array and adds in 32 bits: 2.7 to
  3.2 times.
- *A call through a value.* `dyn` calls one of two functions taken from a list at each of its 10 million turns: the call
  tests that the value is a function of that arity, counts the depth of the calls, and gives back its float in an object
  of its own. V8 sees the two functions that the call meets, puts their code in the loop and keeps the float in a
  register: 2.0 to 3.3 times. An entry of a function value for the kinds its arguments have at the run would take the
  float with no object; it isn't made yet.
- *A new map at each turn.* `points` makes a map at each of its 2 million turns, a struct of WasmGC now, and writes it
  into its list, which tests that nothing else holds the list and that the cell is in it; V8 writes its object in place:
  1.4 to 2.6 times.
- *Firefox.* SpiderMonkey runs these modules 1.2 to 2.4 times slower than Chrome does, where its JavaScript keeps up
  with V8's: a page that must be fast is measured in Firefox too. Of the loops in functions of their own, Firefox gained
  on `matmul` only, 1,069 ms to 439 in its own measures, as if it ran the others in its optimized code from the start;
  why that code is slower on these modules wasn't found in this slice.
- Rust or C compiled to WebAssembly, with no check of overflow, weren't measured here.

And `cesia run`, with its JIT, wins every row but `points` and `mandel` against WebAssembly, though its time holds its
start.

**Size.** What a server sends, in bytes, plain and compressed by Brotli at its quality 11, as a server compresses files
once ahead of time, beside the first slice of this compiler:

| Program | Module | Module, Brotli | First slice | First slice, Brotli | JavaScript source, Brotli |
|---|---:|---:|---:|---:|---:|
| hello world, `io.Print("Hello from Cesia")` | 322 | 244 | 431 | 321 |  |
| `fib` | 2,277 | 1,061 | 2,615 | 1,173 | 79 |
| `mandel` | 3,249 | 1,499 | 2,928 | 1,409 | 238 |
| `matmul` | 10,879 | 3,138 | 11,194 | 3,243 | 210 |
| `structs` | 13,100 | 4,725 | 13,448 | 4,393 | 250 |
| `dyn` | 10,571 | 3,958 | 11,461 | 4,053 | 199 |
| `points` | 10,576 | 4,344 | 11,754 | 4,271 | 196 |
| `maps` | 9,480 | 4,214 | 10,934 | 4,122 | 135 |
| `loan.ce` of this chapter | 20,258 | 6,609 | 18,988 | 5,762 |  |

The loader, `NAME.js`, adds 3,149 bytes, 1,313 with Brotli, where it added 3,820 and 1,525: it comes without the
comments of its source. A module holds only the types its code uses, and the text of a message takes a byte a byte. A
loop in a function of its own, and a statement in two versions, make a program of loops larger, as `loan.ce`. A program
that prints a list, a map or a value of a type the compiler doesn't know brings the printer of every value; JavaScript's
source stays smaller, since its engine is in the browser already.

*A page of Ceres.* The invoices page of Ceres, the user interface of the project, compiled to WebAssembly and live from
its app: a form, a list that the app keeps up to date, a graph of `std/plot` and a table of 100,000 rows. Measured in
`tests/web/frames.html` of Ceres, on the same machine (load 2 to 3), headless: from the browser's frame to the page
painted, its work in WebAssembly and WebGL's, while the wheel scrolls the table 200 notches, one every 16 ms, and while
a field is typed in, medians of 2 to 3 rounds; WebGL took 1.0 to 1.4 ms of it:

| | Chrome 158 | Firefox 160 |
|---|---|---|
| First paint, from the start of the page | 462 to 600 ms | 175 to 231 ms |
| A frame while scrolling, p50 / p99 | 8.2 to 9.7 / 19 to 35 ms | 1.7 to 2.2 / 7 to 19 ms |
| A frame while typing, p50 / p99 | 1.2 to 1.6 / 2.2 to 18 ms | 1.3 to 1.7 / 2.0 to 18 ms |
| Frames of the browser while scrolling, p50 / p99 apart | 16.7 / 33 to 50 ms | 17.1 / 17.1 to 17.2 ms |

V8 runs this page 4 times slower than SpiderMonkey, where it ran the programs above faster; without its first compiler,
Liftoff (`--no-liftoff`), its frames take 7.2 to 7.8 ms, so it isn't that the long loop of the page stays in that code;
why it is so wasn't found in this slice. The page's module is 1,023,363 bytes, 177,562 in Brotli, its loader 10,433
(3,698), and the glue of Ceres 5,765 in Brotli; `browser.sites`, 1,091,744 bytes, comes only at an error. `std/plot`, all
of whose kinds of graphs the module holds though the page draws bars, is most of it: its largest functions draw graphs
of three dimensions.

## Further reading

- Andreas Haas and others, *Bringing the Web up to Speed with WebAssembly*, 2017: the design of WebAssembly, its types
  and its validation.
- Wasm 3.0 and its proposal of garbage collection, 2025: the structs, arrays and `i31ref` that Cesia's values are made of.
- L. Peter Deutsch and Allan M. Schiffman, *Efficient Implementation of the Smalltalk-80 System*, 1984: the inline
  cache, which each read of a field keeps.
- Craig Chambers, David Ungar and Elgin Lee, *An Efficient Implementation of SELF*, 1989: maps, the layout shared by
  the objects of one shape, which V8 calls hidden classes; Cesia's typed maps in a page.
- Python 3.6's compact dict, after Raymond Hettinger, and Donald E. Knuth, *The Art of Computer Programming*, volume 3,
  section 6.4: the table of a map past 8 keys, and what its probes cost.
- Guy L. Steele Jr., Doug Lea and Christine H. Flood, *Fast Splittable Pseudorandom Number Generators*, 2014:
  SplitMix64, which draws the seed of each table.
- The WebAssembly Community Group's proposal *JavaScript Promise Integration*, and V8's *Introducing the WebAssembly
  JavaScript Promise Integration API*, 2024: the fibers of a page.
- Luna Phipps-Costin and others, *Continuing WebAssembly with Effect Handlers*, 2023: stack switching, the fibers that
  WebAssembly may have one day.

Each with its link in [References](references.md#webassembly), [The JIT](references.md#the-jit),
[Values and maps](references.md#values-and-maps) and [Tests](references.md#tests).

## Next

The next chapter, [C and C++](c.md), calls the libraries of the system from Cesia.
