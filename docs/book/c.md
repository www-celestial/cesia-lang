# C and C++

In this chapter you call a library written in C: you open it, bind its functions by their types, and pass it numbers, texts,
memory and callbacks. This is the [foreign function interface](glossary.md#foreign-function-interface) of Cesia. Cesia's own modules for cryptography and TLS are built this way, on libsodium and OpenSSL.
C++ goes through a small C layer that Cesia writes and compiles for you.

## Total trust

A C library runs outside Cesia: it ignores every permission and every limit, and a wrong type in a binding can crash the
program. So a program needs `--allow ffi=NAME` for each library it opens, and you give it only to libraries you trust:

```bash
cesia run --allow ffi=m geometry.ce
```

## Opening a library and binding a function

[c.Open] loads a library by its short name, `m` for the C maths library, trying the file names each system uses.
[c.Fn] binds one of its functions: its name, the types of its arguments, the type of its result. It gives a Cesia function:

```cesia allow=ffi=m
use std/c
use std/result
m = c.Open("m", version = 6)!
cos = c.Fn("cos", ["f64"], "f64", m)!
pow = c.Fn("pow", ["f64", "f64"], "f64", m)!
cos(0.0) -->
pow(2.0, 10.0) -->
```

`version = 6` is the major number in the name of the library's file: `libm.so.6` on Linux. The names with that number are
tried first, then those without it.

### Wrong arguments and names

An `Int` where C wants a float becomes one, as for a typed parameter. A name the library doesn't have is an `Err`:

```cesia allow=ffi=m
cos(0) -->
c.Fn("cosine", ["f64"], "f64", m) -->
```

## Types

| Type | In C | In Cesia |
|---|---|---|
| `i8`, `i16`, `i32`, `i64`, and `u8` to `u64` | integers of that size | `Int` |
| `f32`, `f64` | `float`, `double` | `Float` |
| `bool` | `bool` | `Bool` |
| `text` | `const char *` | `Text` |
| `ptr` | a pointer | a block, or `missing` for `NULL` |
| `callback` | a function pointer | a function made by [c.Callback] |
| `void` | no result | `missing` |
| a [c.Struct] | a structure by value | a block |

## Memory and structures

[c.Alloc] gives a block of memory outside Cesia's own, set to zero, for a C function that writes into a buffer or takes a
structure. [c.Set] and [c.Get] write and read a number at a byte offset, [c.Store] and [c.Load] bytes of text. [c.Free]
releases the block:

```cesia allow=ffi=m
point = c.Struct(["f64", "f64", "i32"])
c.Size(point) -->
c.Offset(3, point) -->
p = c.Alloc(c.Size(point))
c.Set("f64", c.Offset(2, point), 2.5, p)
c.Get("f64", c.Offset(2, point), p) -->
c.Store("hi", 16, p)
c.Load(16, 2, p) -->
c.Free(p)
```

[c.Struct] lays out its fields as C does, with the same padding: here the `i32` starts after the two floats, at byte 16. A block
used after [c.Free] stops the program, instead of reading memory that is no longer its own.

A buffer of many numbers of one type, as the vertices of a shape for a renderer or the pixels of an image, is one call:
[c.Write] writes a whole array from a byte offset, each number converted as [c.Set] converts one, a matrix column by
column. It is another operation, not another way to write one: [c.Set] writes one value where the layout puts it, a field
of a structure, and pays a call each time; [c.Write] writes a run of values side by side and pays one call for all of them,
with its bounds checked once, before it writes: an offset or a length past the end of the block writes nothing, and
[c.Write] never writes where [c.Set] would refuse to. For a field, [c.Set]; for a run of numbers, [c.Write]:

```cesia allow=ffi=m
xy = c.Alloc(3 * 2 * 4)
c.Write("f32", 0, [10.0, 20.0, 15.5, 4.0, 30.0, 8.25], xy)
c.Get("f32", 8, xy) -->
c.Free(xy)
```

## Callbacks

Some C functions take a function to call: a comparison, a handler of events. [c.Callback] makes a C function pointer from a
Cesia function and the types C will call it with:

```cesia norun
use std/result
lib = c.Open("mylib")!
applyTwice = c.Fn("apply_twice", ["callback", "i64"], "i64", lib)!
triple = c.Callback(x -> x * 3, ["i64"], "i64")
applyTwice(triple, 2)
```

A panic inside a callback comes back to the Cesia code that called C. A C function that keeps a callback and calls it later,
from another of its functions, says so when it is bound, with `callsBack = true`: a callback that comes through a function
bound without it, or from a thread of the library, stops the program with a message, as running Cesia there would corrupt
its memory. [c.Callback] of a function made a callback before, with the same types, gives that one back: C may keep the
pointer, so each callback is C memory kept to the end of the program, which counts against `--limit memory`.

### Variadic functions

A function such as `printf` takes a *variable argument list*, whose types it doesn't declare. [c.Variadic] binds one: the
types of its fixed arguments, then those of the arguments a call gives. C promotes a small integer or a `float` given
there, so those are refused: write `i32` or `f64`.

```cesia norun
use std/c
use std/result
libc = c.Open("c", version = 6)!
snprintf = c.Variadic("snprintf", ["ptr", "u64", "text"], ["i32"], "i32", libc)!
```

## How a call reaches C

A call of up to 6 arguments, each an integer or a float, with such a result, goes through a C function made for its
*shape*, the kinds of its arguments and of its result: 254 of them, written by `src/gen/gen_calls.ml` when Cesia is built.
More arguments, a structure by value, a variadic function or a callback go through *libffi*, a library that builds a call
of any C signature as the program runs; Cesia finds it on the system at the first such call, so it links nothing more.

Measured on 2026-11-08, `bench/ccall.ce`: 10 million calls of C's `abs` in a loop, 5 runs of each alternated, the median
and the range:

| | Calls per second |
|---|---:|
| Cesia, `std/c` | 11.8 million (10.7 to 12.3) |
| Python, `ctypes`, `bench/ccall.py` | 2.0 million (1.97 to 2.06) |
| LuaJIT, its FFI, `bench/ccall.lua` | 818 million (509 to 868) |

```cesia allow=read,write
use std/plot
perSecond = [11.8e6, 2.0e6, 818e6]
calls = plot.Of([plot.Points(1..3, perSecond, size = 8), plot.Text(1..3, perSecond, ["11.8 million", "2.0 million", "818 million"])],
  title = "Calls of C's abs a second, median of 5 runs", y = "calls a second (log scale)", yscale = "log", ylim = [1e6, 2e9],
  xticks = 1..3, xlabels = ["Cesia, std/c", "Python, ctypes", "LuaJIT, its FFI"], xlim = [0.5, 3.5], size = [640, 320])
plot.Save(calls, "c-calls.svg") -->
```

A call costs Cesia about 85 nanoseconds, 6 times less than Python's `ctypes`, and 70 times more than LuaJIT, whose JIT
compiles the call into the machine code of the loop. A call to C is worth it for work that takes more than that, as a
whole computation of a library, not for one small step in a loop.

### A call that takes long

A call runs on the thread of the fibers: while it runs, no other fiber does, and a server answers no one. For a
function that takes long, as a password hash of 70 ms, `slow = true` runs each call on a thread of its own, while its
fiber waits and the others run:

```cesia norun
use std/c
use std/result
sodium = c.Open("sodium", version = 26)!
verify = c.Fn("crypto_pwhash_str_verify", ["ptr", "ptr", "u64"], "i32", sodium, slow = true)!
```

As many slow calls run at once as `CESIA_CORES` gives, half of the cores of the machine by default; the others wait in
line, at most 64 for each of those places, and one more stops its fiber with an error: a burst of a thousand sign-ins
can't take the memory of a thousand hashes at once. A slow function takes at most 6 numbers, pointers or texts, and
doesn't call back; its texts are copied for it, and the blocks it is given stay alive until it returns, even if a fiber
frees one meanwhile. No other fiber may write into those blocks while it runs: C would read them at the same time.
Each call runs on a *domain*, OCaml's thread on a core of its own. Starting one costs about 220 microseconds on Linux, and
its end empties the young heap of every domain at once, in a *stop of the world*: what lives there moves to the old heap,
2 ms for a server that holds 1.4 MB of young values. So in a burst, each call starting less than 2 ms after the end of
the last, as a loop or a line of sign-ins, the domain of a call waits for the next: 5,000 calls in a row cost 13 µs a call [10, 17] instead of 104 [97, 214] (medians of 21 runs alternated, load 8.8 to 9.3). A call alone still starts a
domain that leaves once done, and a program that never calls slowly has none. A domain that waits takes part in every
stop of the world of the garbage collector, and the major collection goes about half as fast while one waits (the OCaml
manual, chapter "Parallel programming"; Sivaramakrishnan and others, *Retrofitting Parallelism onto OCaml*, 2020): waiting
longer would cost memory. Bursts of 100 calls every 0.3 s in a program that keeps 20,000 lists changing, for 3 s: a
domain that waits 50 ms after each burst took its old heap from 4.0 to 6.0 million words at most, 2 ms from 4.0 to 4.0,
and 126 young collections instead of 1,040. `slow` is for calls of a millisecond or more, or for many in a row.

Measured on 2026-11-13, 50 sign-ins at once against a server of [std/http], each a [crypto.CheckPassword], while a
fiber asks the same server `/ping` every 5 ms (`bench/signin.ce`): before, every sign-in waited for the others, and
nothing else ran; with `slow`, four at once on this machine of 8 cores.

| | All 50 | A sign-in, median | Longest wait of `/ping` |
|---|---:|---:|---:|
| without `slow` | 3,645 ms | 3,641 ms | 3,646 ms |
| with `slow` | 1,518 ms | 800 ms | 66 ms |

```cesia allow=read,write
waits = plot.Bars(["all 50", "a sign-in", "wait of /ping"], [[3645, 3641, 3646], [1518, 800, 66]],
  label = ["without slow", "with slow"])
signins = plot.Of([waits], title = "50 sign-ins at once: milliseconds", y = "milliseconds", size = [640, 320])
plot.Save(signins, "c-slow.svg") -->
```

The 66 ms that remain come with the hashes that run at once, each taking and giving back 64 MiB: four checks at once
leave a fiber that sleeps 1 ms without a turn for up to 48 ms, two for 13 ms, one for 2 ms (`CESIA_CORES=1`, `bench/signin-gap.ce`); a
loop of pure computation, as long, for 3 ms with four.

## C++

C++ has no stable binary form, no [ABI](glossary.md#abi), so [std/cpp] describes what to reach, writes a small C layer for it, compiles it once with the
C++ compiler, and loads it. [cpp.Wrap] gives a dictionary of functions, with `"Class.new"`, `"Class.delete"` and `"Class.method"` for a class:

```cesia norun
(* demo.ce *)
use std/cpp
use std/io
use std/result

spec = {
  Name: "demo",
  Include: ["<vector>", "<numeric>"],
  Classes: [cpp.Class("Numbers", "std::vector<int>", [
    cpp.Method("push", ["i32"], "void", call = "push_back"),
    cpp.Method("count", [], "u64", call = "size")
  ])],
  Functions: [cpp.Fn("gcd", ["i64", "i64"], "i64", call = "std::gcd<long, long>")]
}

defn main()
  m = cpp.Wrap(spec, folder = "build", compiler = "g++")?
  xs = m["Numbers.new"]()
  m["Numbers.push"](xs, 5)
  io.Print(m["Numbers.count"](xs), m["gcd"](12, 18))
  m["Numbers.delete"](xs)
  result.Ok(missing)
end

main()!
```

### Running it

[cpp.Wrap] makes the folder `build` if it isn't there, writes the C layer in it, runs the compiler, which writes the library
beside it, and loads the library. So the program needs `exec` for the compiler, `read` and `write` on `build`, and `ffi` for
the library it made, by its exact path, `lib` and the `Name` of the spec, then `_cesia.so`:

```bash
cesia run --allow exec=g++,read=build,write=build,ffi=build/libdemo_cesia.so demo.ce
```

```text
1 6
```

[result.Unwrap] at the end stops the program with the message of an `Err`, if the compiler or the library fails.

It compiles again only what changed: the source of the layer, a header of the project that it includes by `"name"`, and
those that header includes so, the compiler, as its `--version` tells, or its flags. The first line of the `.cpp` keeps
the fingerprint of them all. The library is compiled under a name of its own, then renamed, so that a program started
meanwhile never loads one half written. Cesia keeps the fingerprint of each library it makes in its own cache, which only
you can read and write (`~/.cache/cesia`, 0700): a library that someone else put in `build`, as one a cloned project
holds, is made again, never loaded. Someone who may write `build` while the program runs can still swap the library
between that check and its load: build into a folder that is yours alone. A C++ exception becomes a panic with its
message. [cpp.Source] gives the text of
the C layer without compiling it, to read what [cpp.Wrap] would build.

## Next

Your programs can use the libraries of the system. The next chapter, [Native packages](native.md), brings new native code
in OCaml, compiled once by a package's author.
