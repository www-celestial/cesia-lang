# Speed

In this chapter you see how Cesia makes a program fast without your help, what it makes fast, and how to see it.

Cesia starts at once and runs a program in its [interpreter](glossary.md#interpreter-and-jit). As the program runs, the
parts that run often, the hot functions and loops, become machine code: that is the JIT. You write nothing for it, and a
[type](types.md) never makes code faster: the JIT finds the types itself, in what the program does. The results, the
errors and the limits are the same as the interpreter's, to the last digit. The JIT runs on x86-64, on Linux, macOS and
Windows; on arm64, as Apple's chips, it is off for now, and programs run in the interpreter, with the same results.

## What becomes machine code

- Loops over numbers, and arrays of floats or of values read and written by index.
- Functions on numbers that call each other, as a recursion.
- In a loop, maps and structs: reading their fields, computing with them, making new ones, storing them in a list.

This loop over a list of structs runs as machine code once it is hot, about four times as fast as in the interpreter:

```cesia
use std/list

struct Particle { X, V }

defn move(n, steps)
  ps = list.Fill(0, n)
  for i in 1..n
    ps[i] = Particle(i * 1.0, 0.5)
  end
  for s in 1..steps
    for i in 1..n
      p = ps[i]
      ps[i] = Particle(p.X + p.V * 0.01, p.V)
    end
  end
  ps[n].X
end

move(1000, 300) --> 1001.4999999999986
```

The JIT bets on what it saw: that `p` is a `Particle`, that `p.X` holds a float. When a bet fails, say a field holds a
text, the program goes on in the interpreter from that line, then the loop comes back to machine code: the answer is the
same, a little later.

## What stays in the interpreter

- Calls to the functions of packages written in OCaml, as [text.Split] or [json.Parse]: they are machine code already.
- Loops over the elements of a list, `for x in xs`, and functions passed as values.
- Under a debugger, a function whose code holds a breakpoint, and the code you step through: the rest stays machine code,
  as the chapter [The prompt and the debugger](debug.md#speed) says.
- At the prompt, under `--watch` and under a debugger, the code that uses what the program's own functions give: such a
  function can be defined again while a call to it runs, with results of another type, and that code takes them at once.

## Seeing it

`CESIA_JIT_SHOW=1` prints what became machine code, and why the JIT didn't load; `--no-jit` runs the interpreter alone,
to compare:

```bash
CESIA_JIT_SHOW=1 cesia run particles.ce
cesia run --no-jit particles.ce
```

See [Environment variables](env.md) and [Commands](commands.md#cesia-run).

## A server under load

A server of [std/http] answers about 60,000 small requests per second on one core of a 2015 laptop, 45,000 in JSON, and
22,000 on a new connection each, with a 99th percentile of 4 ms at 100 connections; an idle connection takes 2.3 KB.
On the same core, Node answers 40,000 to 50,000, and 12,000 on new connections. `--workers 2` doubles it, as
[Every core](http.md#every-core) says. These numbers come from the repository of Cesia, which measures them so:

```bash
tools/http-bench.sh    # each load against Node, and Go if it is there
tools/http-gate.sh     # the gate that a change to the server must pass
```

`tools/http-bench.sh` runs a tiny route, a JSON one and new connections, at 10, 100 and 1,000 connections, and 10 beside
10,000 idle ones, and prints the requests per second, the median and the 99th percentile of the latency, the failed
requests and the memory. `tools/http-gate.sh` runs the main loads and fails if one request fails, if Cesia answers
fewer requests than Node or than its floors, if its 99th percentile passes 10 ms, if an idle connection takes more than
4 KB, or if two workers don't give one and a half times one process. `HTTP_GATE_SCALE=0.5` halves the floors on a slower
machine.

## Next

Your programs run fast with nothing to write. The next chapter, [C and C++](c.md), calls the libraries of the system from
Cesia.
