# C and C++

In this chapter you call a library written in C: you open it, bind its functions by their types, and pass it numbers, texts,
memory and callbacks. Cesia's own modules for cryptography, TLS and windows are built this way, on libsodium, OpenSSL and SDL.
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
m = Unwrap(c.Open("m", version = 6))
cos = Unwrap(c.Fn("cos", ["f64"], "f64", m))
pow = Unwrap(c.Fn("pow", ["f64", "f64"], "f64", m))
cos(0.0) -->
pow(2.0, 10.0) -->
```

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

## Callbacks

Some C functions take a function to call: a comparison, a handler of events. [c.Callback] makes a C function pointer from a
Cesia function and the types C will call it with:

```cesia norun
lib = Unwrap(c.Open("mylib"))
applyTwice = Unwrap(c.Fn("apply_twice", ["callback", "i64"], "i64", lib))
triple = c.Callback(x -> x * 3, ["i64"], "i64")
applyTwice(triple, 2)
```

A panic inside a callback comes back to the Cesia code that called C. A C function that keeps a callback and calls it later,
from another of its functions, says so when it is bound, with `callsBack = true`.

## C++

C++ has no stable binary form, so [std/cpp] describes what to reach, writes a small C layer for it, compiles it once with the
C++ compiler, and loads it. [cpp.Wrap] gives a dictionary of functions, with `"Class.new"` and `"Class.method"` for a class:

```cesia norun
use std/cpp

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
  Print(m["Numbers.count"](xs), m["gcd"](12, 18))
  m["Numbers.delete"](xs)
  Ok(missing)
end
```

It compiles again only what changed. A C++ exception becomes a panic with its message.

## Next

Your programs can use the libraries of the system. The next chapter, [Cemacs](cemacs.md), is the editor written in Cesia, for Cesia.
