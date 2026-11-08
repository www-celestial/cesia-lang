# Speed

In this chapter you see how Cesia makes a program fast without your help, what it makes fast, and how to see it.

Cesia starts at once and runs a program in its [interpreter](glossary.md#interpreter-and-jit). As the program runs, the
parts that run often, the hot functions and loops, become machine code: that is the JIT. You write nothing for it, and a
[type](types.md) never makes code faster: the JIT finds the types itself, in what the program does. The results, the
errors and the limits are the same as the interpreter's, to the last digit. The JIT runs on x86-64, on Linux, macOS and
Windows; on arm64, as Apple's chips, it is off for now, and programs run in the interpreter, with the same results.

A function that gives a number is *hot* after 1,000 calls, and a loop after 10,000 to 20,000 turns: [How Cesia works](internals.md#the-jit)
says exactly when, what kind of JIT it is, how it bets on types and how it gives back to the interpreter when a bet
fails.

## What becomes machine code

- Loops over numbers, and arrays of floats or of values read and written by index.
- Functions on numbers that call each other, as a recursion.
- In a loop, maps and structs: reading their fields, computing with them, making new ones, storing them in a list.

This loop over a list of structs runs as machine code once it is hot, about four times as fast as in the interpreter:
`bench/real/particles.ce`, the same loop on 1,000 particles, takes 173 ms against 718 ms without the JIT, the medians
of 7 runs on the machine of [Beside the giants](#beside-the-giants):

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

## Beside the giants

The same programs in Cesia, Python, Node, Java, Go, OCaml, Lua and LuaJIT, on one machine: an Intel Core i7-4720HQ of
2015, 8 logical cores, Linux, measured on 2026-11-08 while other work ran on it (load about 2). The versions: Python
3.14.9, Node 26.13 (V8), Java 21 (OpenJDK, HotSpot), Go 1.26.3, OCaml 5.5.0 (`ocamlopt`, without flambda), Lua 5.5.1,
LuaJIT 2.1, and Cesia in its `release` build.

**The method.** Each program does the same work and prints the same answer, which is checked at each run. The runs of
all the languages alternate, one of each in turn, so that a slower minute of the machine falls on all of them. Each time
is the whole process, from its start to its end, start-up included: a Java or a Node program pays 25 to 40 ms before
its first line. Each cell gives the *median* of 11 runs, the middle one, and after it the *95% confidence interval* of
that median: the range that holds the true median with a probability of at least 95%, here 98.8%, found from the
ranks of the sorted runs, the 2nd and the 10th, with no guess about how the times are spread. A wide range means a
noisy measure. The programs are in `bench/` of the repository: `NAME.ce`, `.py`, `.js`, `.lua`, `.go`, `.java` and
`ocaml/NAME.ml`.

### Start-up

A program that prints `1`, 101 runs of each, alternated:

| | Median | 95% interval |
|---|---:|---:|
| `/usr/bin/true`, nothing | 0.53 ms | 0.51 to 0.54 |
| Lua | 0.83 ms | 0.81 to 0.85 |
| LuaJIT | 0.99 ms | 0.96 to 1.01 |
| OCaml, native | 1.08 ms | 1.04 to 1.10 |
| Go | 1.25 ms | 1.23 to 1.28 |
| **Cesia** | **2.89 ms** | 2.86 to 2.90 |
| Python | 14.30 ms | 14.17 to 14.39 |
| Java | 25.39 ms | 25.09 to 25.67 |
| Node | 38.23 ms | 37.74 to 39.00 |

Cesia starts 5 times sooner than Python, 9 times sooner than Java and 13 times sooner than Node. A compiled Go or OCaml
program, or Lua, starts in about half its time: Cesia carries its whole runtime, its standard library and its compiler
in one binary, and the system must fix up the addresses of its data at each start, as
[How Cesia works](internals.md#start-up) shows.

### Computing

Milliseconds, median and 95% interval of 11 runs:

| Program | Cesia | Cesia, no JIT | Python | Node | Java | Go | OCaml | Lua | LuaJIT |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `fib` | **74** (73–77) | 448 (444–451) | 1,453 (1,425–1,498) | 172 (170–282) | 71 (70–74) | 50 (49–57) | 53 (52–57) | 693 (687–712) | 96 (93–103) |
| `mandel` | **64** (63–72) | 464 (455–505) | 2,604 (2,572–2,687) | 91 (87–97) | 82 (81–92) | 52 (51–53) | 58 (56–58) | 431 (428–443) | 55 (55–58) |
| `matmul` | **49** (49–52) | 1,024 (952–1,232) | 4,858 (4,818–4,986) | 97 (97–103) | 93 (87–99) | 33 (33–35) | 61 (60–73) | 839 (825–875) | 87 (86–87) |
| `structs` | **220** (212–234) | 556 (545–611) | 1,804 (1,778–1,836) | 171 (168–181) | 102 (101–113) | 9 (9–9) | 30 (30–30) | 1,536 (1,518–1,607) | 401 (393–423) |
| `dyn` | **714** (679–859) | 763 (731–789) | 1,397 (1,372–1,421) | 172 (166–203) | 98 (97–105) | 28 (28–28) | 69 (67–71) | 740 (717–806) | 59 (57–63) |
| `maps` | **1,201** (1,160–1,265) | 1,171 (1,153–1,210) | 416 (408–429) | 563 (555–583) | 234 (220–269) | 282 (273–373) | 532 (502–596) | 826 (812–891) | 326 (315–342) |

What each program does: `fib` is `fib(35)`, about 30 million recursive calls on integers; `mandel` a loop of floats over
600 × 400 points; `matmul` the product of two 300 × 300 matrices read by index; `structs` 1,000 records of four floats,
each remade at each of 5,000 steps; `dyn` 10 million calls through a list of two functions, on values of mixed kinds;
`maps` a map of 500,000 text keys, written then read.

**Where Cesia wins.** On loops of numbers and on recursion, the JIT puts Cesia beside Java and LuaJIT, and ahead of
Node: `matmul` runs in half the time of Java, Node and LuaJIT, `mandel` and `fib` in about the time of Java. Against
Python, the language most of its users come from, Cesia is 20 times faster on `fib`, 41 times on `mandel` and 99 times
on `matmul`; against Lua, 7 to 17 times.

**Where a giant wins, and why.**

- **Go and OCaml win every line.** They compile the whole program to machine code before it runs, with every type known.
  Go's `structs` keeps its records as plain values inside the array, written in place: no record is ever allocated,
  9 ms. Cesia's records are values of any kind, each a new block in memory, which the JIT builds at each step: 220 ms.
- **`dyn`: Node, Java, OCaml and LuaJIT are 4 to 12 times faster, and Go 25 times.** A call through a function held in a list stays in
  Cesia's interpreter, as [What stays in the interpreter](#what-stays-in-the-interpreter) says; HotSpot and V8 see that
  each place calls the same two functions and compile the call inline, LuaJIT records the loop with its calls as one
  trace. This is the next work of Cesia's JIT.
- **`maps`: Cesia is the slowest, 3 times Python, 4 to 5 times Java and Go.** Three reasons. A Cesia map is persistent,
  a hash trie where each write copies a path of nodes, where the others write a mutable hash table in place, as
  [How Cesia works](internals.md#maps-a-hash-trie) explains: the price of value semantics. The key `"key$k"` is a new
  text at each turn, and its hash is computed each time, where Python and Java keep the hash inside the string. And the
  loop, which calls the natives of texts, stays in the interpreter. It also takes 149 MB, against 72 MB for Python and
  52 MB for Go. OCaml's own persistent map, a balanced tree, takes 529 ms for the same work.
- **Node and Java start slowly but run fast**: their JITs compile more, and later, with more time to spend on it.

### Fibers beside goroutines, async and virtual threads

100,000 tasks that park on one gate, then all end once it opens: Cesia's fibers, Go's goroutines, Node's `async`
functions on one promise, Python's `asyncio` tasks on an event, Java 21's virtual threads on a latch, and Lua's
coroutines, which have no scheduler, resumed by a loop. 7 runs of each, alternated; the time per task is that of 100,000
tasks less that of one, divided by 100,000, and the memory per task the peak memory of the process with 100,000 tasks less
that with one, divided by 100,000:

| | 100,000 tasks | 95% interval | Per task | Memory per task |
|---|---:|---:|---:|---:|
| LuaJIT coroutines | 63 ms | 61 to 74 | 0.6 µs | 0.4 KB |
| Go goroutines | 124 ms | 118 to 127 | 1.2 µs | 2.6 KB |
| Lua coroutines | 139 ms | 133 to 145 | 1.4 µs | 1.0 KB |
| Node `async` | 172 ms | 169 to 181 | 1.3 µs | 1.3 KB |
| **Cesia fibers** | **548 ms** | 538 to 631 | **5.4 µs** | **3.6 KB** |
| Python `asyncio` | 1,136 ms | 1,084 to 1,297 | 10.4 µs | 1.4 KB |
| Java virtual threads | 1,769 ms | 1,631 to 2,055 | 17.2 µs | 2.1 KB |

A Cesia fiber takes half the time of a Python task and a third of a Java virtual thread to start, park and end, and
four times a goroutine. It takes the most memory here, 3.6 KB with its task, since each fiber has three stacks of its
own, for values, integers and floats, beside its OCaml stack. Go's goroutines also run in parallel on every core;
Cesia's fibers run on one, and `--workers` gives a server every core, as [HTTP](http.md#every-core) shows.

## A server under load

[std/http] against Node's `http` module and Go's `net/http`, each on one core, on the machine of
[Beside the giants](#beside-the-giants): the server pinned to the first core, the load client to the second, Go held to
one core with `GOMAXPROCS=1`. Each serves the same two routes, a tiny text and a small JSON object, from
`bench/http.ce`, `bench/http.js` and `bench/http.go`. `tools/http-bench.sh` ran 6 times, alternating the three servers,
each load for 3 seconds; each cell gives the median of the 6 runs, and in parentheses the lowest and the highest, which
hold the median with a probability of 96.9%. No request failed, in any run.

| Load | Cesia | Node | Go |
|---|---:|---:|---:|
| tiny route, 10 kept connections | **65,296** (60,917–67,447) | 42,909 (38,750–45,523) | 65,649 (60,689–66,933) |
| tiny route, 100 kept connections | **62,252** (55,145–64,082) | 45,464 (41,992–49,301) | 61,408 (58,009–65,163) |
| tiny route, 1,000 kept connections | **36,140** (35,106–36,423) | 41,172 (37,732–44,978) | 51,067 (44,919–53,328) |
| JSON route, 100 kept connections | **38,254** (37,754–41,151) | 39,640 (31,714–42,711) | 49,916 (47,016–51,275) |
| a new connection per request, 10 | **22,325** (20,638–22,725) | 11,434 (8,866–12,211) | 19,375 (18,241–19,871) |
| a new connection per request, 100 | **21,618** (20,340–23,030) | 12,860 (12,279–13,439) | 19,426 (18,831–20,095) |

Requests per second. The 99th percentile of the latency, the time under which 99 requests of 100 are answered, at 100
kept connections on the tiny route: Cesia 3.6 ms, Node 4.2 ms, Go 4.0 ms; at 1,000: Cesia 37 ms, Node 19 ms, Go 31 ms. An
idle connection takes 2.3 KB in Cesia, 2.5 KB in Node and 17 KB in Go, and a server at rest 13.6 MB, 54 MB and 10 MB.

Cesia answers as many small requests as Go on one core, and a third to a half more than Node; on new connections it is the
fastest of the three. Go wins the JSON route by 30%: its encoder is compiled code, where Cesia's handler and its response
run partly in the interpreter. Both Go and Node hold 1,000 connections better: Cesia's latency there is twice Node's,
since one core runs 1,000 fibers in turn. `--workers 2` gives Cesia two cores, and about 1.5 times the requests, as
`tools/http-gate.sh` checks at each change; Go's goroutines take every core by themselves.

```bash
tools/http-bench.sh    # each load against Node, and Go if it is there
tools/http-gate.sh     # the gate that a change to the server must pass
```

`tools/http-bench.sh` also runs 10 active connections beside 10,000 idle ones, which gives the memory of an idle
connection. `tools/http-gate.sh` runs the main loads and fails if one request fails, if Cesia answers fewer requests than
Node or than its floors, if its 99th percentile passes 10 ms, if an idle connection takes more than 4 KB, or if two
workers don't give one and a half times one process. `HTTP_GATE_SCALE=0.5` halves the floors on a slower machine.

## Further reading

- Craig Chambers and David Ungar, *Customization*, 1989, and the papers of Self after it on inline caches, deoptimization
  and type feedback: the ideas of Cesia's JIT.
- Andreas Gal and others, *Trace-based Just-in-Time Type Specialization for Dynamic Languages*, 2009: the tracing JIT,
  which LuaJIT is, and Cesia isn't.
- Vladimir Makarov's MIR, which makes Cesia's machine code.

Each with its link in [References](references.md#the-jit); [How Cesia works](internals.md#the-jit) shows the JIT inside.

## Next

Your programs run fast with nothing to write. The next chapter, [C and C++](c.md), calls the libraries of the system from
Cesia.
