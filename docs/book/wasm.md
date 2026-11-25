# Compiling to WebAssembly

In this chapter you compile a Cesia program to WebAssembly and run it in a web page and in Node, with the same output, the
same errors and the same numbers as `cesia run`. [WebAssembly](glossary.md#webassembly-and-wasmgc) is a format of code
that every current browser runs, near the speed of machine code, inside the page's [sandbox](glossary.md#sandbox).
`cesia build` compiles the program [ahead of time](glossary.md#ahead-of-time-compilation): the page holds your program
and the few functions of the runtime it uses, and no interpreter.

This is a first slice: numbers, texts, lists, maps, functions and closures, `if`, `match` and loops, results and `?`,
and errors. What it doesn't compile yet is an error at the build, at its place: see
[What it compiles](#what-it-compiles).

## The command

```bash
cesia build --target wasm file.ce
```

It writes two files beside `file.ce`: `file.wasm`, the module, and `file.js`, its loader, which fetches the module,
starts it and writes what it prints. A program that uses packages gets them in the same module, compiled with it.
Building again replaces both files. `file.js` is plain JavaScript of 80 lines, with no package to install and no step
after it.

When something can't be compiled yet, the build stops at its place, writes no file, and gives the exit code 1:

```text
fib.ce:3:10: std/fiber.Spawn isn't compiled to WebAssembly yet.
  3 | t = fiber.Spawn(() -> 1 + 1)
    |          ^
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

The message comes from the same table as the interpreter's, and the module keeps the places of its errors in a section
of its own, `cesia.sites`, that the loader reads only when an error happens.

The limits are those of `cesia run`: 10,000 calls deep at most, then the error `Limit "depth" reached.`, at the same
place, with the same calls named.

## What it compiles

| Compiled | Not yet |
|---|---|
| integers of 63 bits, checked as `cesia run` checks them; floats; true, false and missing | fibers and channels |
| texts in UTF-8, `$` in texts, comparing them | methods, interfaces |
| lists, arrays of floats and of integers, ranges, comprehensions, `x[i]` and `x[i] = v` | slices, `x[a..b]` |
| maps written as literals, their fields, `m["key"]`, `m.Name = v` | types declared on parameters and results |
| functions, closures, functions as values, recursion | `dict.Put`, `dict.Dict` and most of the standard library |
| `if`, `match` and its patterns, `for`, `while`, `return` | |
| `result.Ok`, `result.Err`, `?`, `bug.Panic` and errors | |

A map is made here for a few keys, as a record of fields: its keys sit in a row, which a new key copies and a read
searches from the first. A map grown key by key to many thousands, as a dictionary of counts, is slow for now: the
500,000 keys of `bench/maps.ce` hadn't ended after 100 seconds, where `cesia run` takes 255 ms
([Speed](speed.md#computing)). Keep such work in `cesia run`, or in a server the page asks, until the next slice gives
maps the hash trie of `cesia run`.

Of the standard library, these compile: `io.Print`; `math.Div`, `Mod`, `Abs`, `Floor`, `Ceil`, `Round`, `Sqrt`, `Exp`,
`Log`, `Sin`, `Cos`, `Tan`, `Asin`, `Acos` and `Atan`; `list.Sum`, `Append`, `Concat`, `Take`, `Skip`, `Reverse` and
`Fill`; `matrix.Zeros`, `Ones` and `Reshape`; `value.Len`, `Text`, `Equal`, `Size` and the tests `IsInt` to
`IsMissing`; and the packages written in Cesia, as `std/result`, as far as they use what this table compiles.

## How it works

The compiler is a plugin of Cesia, `cesia_wasm.cmxs`, which only `cesia build` loads: `cesia run` never pays for it. It
loads the program as `cesia run` does, then compiles each function once for each kind of arguments it is called with, as
the JIT does: where the types are known, an integer is an `i64` of WebAssembly, with the checks of Cesia's 63 bits, and a
float an `f64`, both in the machine's registers; elsewhere, a value is a reference to an object of
[WasmGC](glossary.md#webassembly-and-wasmgc), the garbage collector of the browser itself, so that the module brings no
collector of its own. An integer that fits in 31 bits is an `i31ref`, a reference that holds the number with no object
behind it. A map literal shares its keys with every map of the same literal, and each read of a field remembers the keys
it met last and where the field was in them: the next read of a map of the same keys takes the value at once, as an
[inline cache](references.md#the-jit).

Each function of the runtime, the printing of a float or the arithmetic of two values of unknown type, goes into the
module at its first use only: a program that never divides has no division in its module. The module and the loader are
written by Cesia itself, with no tool of WebAssembly to install.

## Speed and size

Five programs of [Speed](speed.md#computing), `maps` aside (see [What it compiles](#what-it-compiles)), compiled to
WebAssembly and run in Node, beside the same programs written in JavaScript, run in the same Node, and beside `cesia
run`; and `bench/points.ce`, 1,000 maps `{X, V}` each moved 2,000 times and written back into their list, with its
twin `bench/points.js`. One machine, an Intel Core i7-4720HQ of 2015, 8 logical cores, Linux 7.2, Node 26.13 (V8), on
2026-11-25, while other work ran on it (load 5.5 to 6.7): milliseconds, medians of 5 runs, the three sides taken in
turn so that the load fell on each. *Alone* is the time of the program itself, once its module is
loaded; *command* the whole command, Node's start included.

| Program | WebAssembly, alone | JavaScript, alone | WebAssembly, command | JavaScript, command | `cesia run`, command |
|---|---:|---:|---:|---:|---:|
| `fib` | **124** | 176 | 176 | 218 | 74 |
| `mandel` | 91 | **65** | 138 | 106 | 67 |
| `matmul` | 904 | **67** | 952 | 105 | 50 |
| `structs` | 923 | **184** | 980 | 226 | 48 |
| `dyn` | 1,103 | **155** | 1,152 | 206 | 74 |
| `points` | 148 | **37** | 189 | 75 | 47 |

**Where WebAssembly wins.** On calls of functions on numbers: `fib`, 30 million calls on integers of 63 bits checked
at each step, runs in 124 ms against 176 for JavaScript, whose numbers are floats with no check.

**Where JavaScript wins, and why.** Everywhere else, by 1.4 times on `mandel` to 13.5 times on `matmul`; and `cesia
run`, with its JIT, wins every row as a whole command:

- *One long call.* V8 compiles a module first with a quick compiler, then compiles again with its optimizing one the
  functions that run often; a call that is already running goes on in the first code. `matmul` is one call of 27
  million turns: with `node --no-liftoff`, which compiles all at once with the optimizing compiler, the same module
  took 414 ms where it had just taken 1,567, one run of each, one after the other, under a heavier load than the
  table's. JavaScript's engine moves a running loop to its fast code; the next slice cuts the hot loops of a long call
  into functions of their own, which V8 then optimizes.
- *A map made at each step.* `structs` and `points` make a new map at each turn and read its fields through a function
  of the runtime; V8 gives each of JavaScript's objects a hidden class, which its code reads inline. The next slice
  makes a map whose keys the compiler knows a struct of WasmGC with typed fields.
- *A call through a value.* `dyn` calls through a list of two functions, its floats boxed in objects at each call,
  where V8's optimizing compiler can inline the functions a call meets.
- The WebAssembly of `points` written by hand for the design of this compiler, with every value an `i64` and the
  same checks, took 47 ms alone: what the compiler can reach once it knows the types of a map's fields. Rust or C
  compiled to WebAssembly, with no check of overflow, weren't measured here.

**Size.** What a server sends, in bytes, plain and compressed by Brotli at its quality 11, as a server compresses
files once ahead of time:

| Program | Module | Module, Brotli | JavaScript source, Brotli |
|---|---:|---:|---:|
| hello world, `io.Print("Hello from Cesia")` | 431 | 321 | |
| `fib` | 2,615 | 1,173 | 79 |
| `mandel` | 2,928 | 1,409 | 238 |
| `matmul` | 11,194 | 3,243 | 210 |
| `structs` | 13,448 | 4,393 | 250 |
| `dyn` | 11,461 | 4,053 | 199 |
| `points` | 11,754 | 4,271 | 196 |
| `loan.ce` of this chapter | 18,988 | 5,762 | |

The loader, `NAME.js`, adds about 3,820 bytes, 1,525 with Brotli. A program that prints a list, a map or a value of a
type the compiler doesn't know brings the printer of every value, most of the 11 KB above; the hand-written `points`
was 469 bytes. JavaScript's source stays smaller, since its engine is in the browser already.

## Further reading

- Andreas Haas and others, *Bringing the Web up to Speed with WebAssembly*, 2017: the design of WebAssembly, its types
  and its validation.
- Wasm 3.0 and its proposal of garbage collection, 2025: the structs, arrays and `i31ref` that Cesia's values are made of.
- L. Peter Deutsch and Allan M. Schiffman, *Efficient Implementation of the Smalltalk-80 System*, 1984: the inline
  cache, which each read of a field keeps.

Each with its link in [References](references.md#webassembly) and [The JIT](references.md#the-jit).

## Next

The next chapter, [C and C++](c.md), calls the libraries of the system from Cesia.
