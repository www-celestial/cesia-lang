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
- In a loop, a call of a function held in a variable, as `f(x)` where `f` came from a list: the machine code tests the
  functions the call met, at most four, and runs the one it finds, as [How Cesia works](internals.md#calls-through-a-value)
  shows.

This loop over a list of structs runs as machine code once it is hot, about four times as fast as in the interpreter:
`bench/real/particles.ce`, the same loop on 1,000 particles, takes 176 ms against 746 ms without the JIT, the medians
of 11 runs on the machine of [Beside the giants](#beside-the-giants):

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
- Loops over the elements of a list, `for x in xs`, and a call through a value that met five functions or more, or a
  function that captured variables of its own.
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
2015, 8 logical cores, Linux, measured on 2026-11-08 while other work ran on it (load 1.3 to 4). The versions: Python
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
| `/usr/bin/true`, nothing | 0.52 ms | 0.50 to 0.54 |
| Lua | 0.81 ms | 0.79 to 0.83 |
| LuaJIT | 0.98 ms | 0.96 to 1.00 |
| OCaml, native | 1.05 ms | 1.02 to 1.08 |
| Go | 1.29 ms | 1.25 to 1.31 |
| **Cesia** | **2.88 ms** | 2.85 to 2.90 |
| Python | 14.06 ms | 14.02 to 14.13 |
| Java | 24.75 ms | 24.67 to 24.85 |
| Node | 37.78 ms | 37.18 to 38.55 |

Cesia starts 5 times sooner than Python, 9 times sooner than Java and 13 times sooner than Node. A compiled Go or OCaml
program, or Lua, starts in about half its time: Cesia carries its whole runtime, its standard library and its compiler
in one binary, and the system must fix up the addresses of its data at each start, as
[How Cesia works](internals.md#start-up) shows.

### Computing

Milliseconds, median and 95% interval of 11 runs:

| Program | Cesia | Cesia, no JIT | Python | Node | Java | Go | OCaml | Lua | LuaJIT |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `fib` | **73** (73–74) | 441 (438–446) | 1,426 (1,417–1,495) | 171 (169–177) | 70 (70–71) | 49 (49–52) | 52 (52–54) | 691 (689–711) | 95 (92–97) |
| `mandel` | **63** (63–64) | 467 (463–473) | 2,625 (2,578–2,665) | 92 (89–104) | 81 (81–90) | 52 (51–56) | 57 (56–60) | 432 (428–439) | 55 (55–57) |
| `matmul` | **49** (49–51) | 948 (942–975) | 4,736 (4,659–5,031) | 97 (95–99) | 92 (92–93) | 33 (33–34) | 60 (59–65) | 824 (822–829) | 87 (86–88) |
| `structs` | **219** (214–224) | 560 (548–578) | 1,738 (1,724–1,796) | 171 (166–180) | 100 (99–111) | 9 (9–9) | 30 (29–30) | 1,525 (1,502–1,548) | 394 (390–400) |
| `dyn` | **182** (181–188) | 708 (696–738) | 1,363 (1,357–1,380) | 165 (163–166) | 97 (86–97) | 28 (28–28) | 67 (67–72) | 717 (715–721) | 57 (57–59) |
| `maps` | **815** (791–828) | 816 (785–830) | 406 (403–414) | 541 (531–548) | 224 (212–230) | 269 (261–286) | 500 (489–517) | 809 (785–846) | 310 (305–336) |

What each program does: `fib` is `fib(35)`, about 30 million recursive calls on integers; `mandel` a loop of floats over
600 × 400 points; `matmul` the product of two 300 × 300 matrices read by index; `structs` 1,000 records of four floats,
each remade at each of 5,000 steps; `dyn` 10 million calls through a list of two functions, on values of mixed kinds;
`maps` a map of 500,000 text keys, written then read.

**Where Cesia wins.** On loops of numbers and on recursion, the JIT puts Cesia beside Java and LuaJIT, and ahead of
Node: `matmul` runs in half the time of Java, Node and LuaJIT, `mandel` and `fib` in about the time of Java. Against
Python, the language most of its users come from, Cesia is 20 times faster on `fib`, 42 times on `mandel` and 96 times
on `matmul`; against Lua, 7 to 17 times. On `dyn` it is now as fast as Node, 182 ms against 165, and 7 times Python.

**Where a giant wins, and why.**

- **Go and OCaml win every line.** They compile the whole program to machine code before it runs, with every type known.
  Go's `structs` keeps its records as plain values inside the array, written in place: no record is ever allocated,
  9 ms. OCaml makes a new record at each step too, but one block of 5 words, its four floats stored flat inside. A Cesia
  map of four floats is 21 words, 168 bytes a step: the map, its array of values, and each new float a box of its own,
  two blocks of OCaml, since a value of Cesia can hold anything. The JIT builds them at each step, with a test of each
  field's kind: 219 ms, behind Node (171) and Java (100), which keep their objects' layout known in advance. Only an
  array of records stored flat, as Go's, would close it.
- **`dyn`: Java, OCaml and LuaJIT are 2 to 3 times faster, Go 6 times.** The call through a function held in a list is
  machine code now, with a test of the two functions it met, inlined, the *polymorphic inline cache* of
  [How Cesia works](internals.md#calls-through-a-value): 714 ms before, 182 now. What is left: `total` is a value the
  inference can't type, as it comes from such a call, so each step makes a new box for its float and tests the kinds of
  its arguments; HotSpot and LuaJIT keep it in a register for the whole loop.
- **`maps`: Cesia is beside Lua, twice Python's time, 3 to 4 times Java's and Go's.** Three reasons. A Cesia map is
  [persistent](glossary.md#persistent-data-structure), a [CHAMP](glossary.md#champ) trie of 5 bits a level, so a read of
  one of 500,000 keys follows four or five nodes in memory, where Python's hash table reads one or two places; that is
  the price of keeping old versions, which [dict.Put] gives for free. Every key written stays alive, and OCaml's
  collector copies each one out of its young heap and marks it again at each major cycle: a third of the time, which
  Python's reference counting doesn't pay. And the loop, which builds a text at each turn, stays in the interpreter. It
  went from 1,201 ms to 815 since the work of [How Cesia works](internals.md#maps-a-hash-trie) on the trie and on the
  writes of a computed key, and takes 89 MB, against 72 MB for Python, 52 MB for Go and 143 MB for Java. OCaml's own
  persistent map, a balanced tree, takes 529 ms for the same work, and its hash table 500.
- **Node and Java start slowly but run fast**: their JITs compile more, and later, with more time to spend on it.

### Fibers beside goroutines, async and virtual threads

100,000 tasks that park on one gate, then all end once it opens: Cesia's fibers, Go's goroutines, Node's `async`
functions on one promise, Python's `asyncio` tasks on an event, Java 21's virtual threads on a latch, and Lua's
coroutines, which have no scheduler, resumed by a loop. 7 runs of each, alternated; the time per task is that of 100,000
tasks less that of one, divided by 100,000, and the memory per task the peak memory of the process with 100,000 tasks less
that with one, divided by 100,000:

| | 100,000 tasks | 95% interval | Per task | Memory per task |
|---|---:|---:|---:|---:|
| LuaJIT coroutines | 64 ms | 61 to 70 | 0.6 µs | 0.4 KB |
| Go goroutines | 123 ms | 119 to 130 | 1.2 µs | 2.6 KB |
| Lua coroutines | 136 ms | 131 to 141 | 1.3 µs | 1.0 KB |
| Node `async` | 175 ms | 169 to 228 | 1.4 µs | 1.3 KB |
| **Cesia fibers** | **442 ms** | 435 to 445 | **4.3 µs** | **2.5 KB** |
| Python `asyncio` | 1,083 ms | 1,078 to 1,124 | 10.1 µs | 1.4 KB |
| Java virtual threads | 1,595 ms | 1,508 to 1,857 | 15.5 µs | 2.0 KB |

A Cesia fiber takes less than half the time of a Python task and a quarter of a Java virtual thread to start, park and
end, and three and a half times a goroutine; 2.5 KB with its task, a little less than a goroutine's 2.6 KB. Each fiber
has three stacks of its own, for values, integers and floats, beside its OCaml stack: they start at 16 slots and double
when they fill, as a goroutine's stack starts at 2 KB and is copied into a larger one. What a goroutine doesn't pay is
the collector: OCaml's copies each live fiber out of its young heap and marks it again at each major cycle, which is
most of the time of a fiber here. Go's goroutines also run in parallel on every core; Cesia's fibers run on one, and
`--workers` gives a server every core, as [HTTP](http.md#every-core) shows.

### Texts and files

A text of 100 MB, 2.46 million lines of OCaml source: read whole from a warm [page cache](glossary.md#page-cache), a word
searched to its end with case and without, its lines joined back, and 16 MB of it written, with and without
[fsync](glossary.md#fsync). Each timed inside the program, around the one operation, 7 runs of each language alternated;
the median, and the lowest and the highest of the 7, which hold the median with a probability of 98.4%. Milliseconds:

| | Cesia | Python | Node | Go |
|---|---:|---:|---:|---:|
| read the file, its bytes | **22** (22–23) | 20 (19–25) | 19 (19–22) | 18 (17–20) |
| read it as checked UTF-8 | | 56 (51–80) | 47 (45–51) | |
| search a word, exact | **39** (38–40) | 46 (44–48) | 49 (49–52) | 7 (6–19) |
| search a word, case ignored | **41** (40–44), `fold` | 797 (761–906), `re.I` | 26 (25–28), `/i` | 3,296 (3,224–3,562), `(?i)` |
| a lower-case copy, then a search | 317 (314–366) | 100 (95–116) | 74 (73–80) | 186 (183–295) |
| join the 2.46 million lines | 218 (217–223) | 59 (58–88) | 142 (137–151) | 50 (49–53) |
| write 16 MB | **3.5** (3.5–4.0) | 6.0 (5.8–7.0) | 7.2 (6.5–8.9) | 2.6 (2.4–3.1) |
| write 16 MB, then fsync | **44** (43–75) | 60 (47–105) | 50 (45–91) | 44 (41–60) |

Cesia's [sys.Read] reads the bytes in one text of the file's size, as fast as the others read bytes; it doesn't check
the UTF-8 (a program asks with [text.IsUtf8], 26 ms more), where Python and Node decode into their own strings.
[text.ByteFind] with `fold` ignores case as fast as it searches with it, 19 times sooner than Python's `re` and 80
times Go's `regexp`, which run a general pattern engine for it.

**Where a giant wins, and why.** Go's exact search, 7 ms, is assembly that compares 32 bytes at a time with the AVX2
instructions of the processor; Cesia's core is OCaml only, which compares 8 at a time in a 64-bit word. Node's `/i`, 26
ms, is a regular expression compiled to machine code by V8, which skips ahead by the bytes that can't start a match.
And joining lines takes 3.7 times less in Python and 4.4 in Go: the bytes are copied at the same speed, but the
profile puts most of Cesia's time in OCaml's collector, which marks the 2.46 million live lines again while the program
allocates the 100 MB of the result, where Python counts references and Go's collector runs on the other cores. The time of an fsync is the disk's, the same for all.

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
- Urs Hölzle, Craig Chambers and David Ungar, *Optimizing Dynamically-Typed Object-Oriented Languages With Polymorphic
  Inline Caches*, 1991: the test of each function a call met, which Cesia's JIT makes for a call through a value.
- Michael J. Steindorfer and Jurgen J. Vinju, *Optimizing Hash-Array Mapped Tries for Fast and Lean Immutable JVM
  Collections*, 2015: CHAMP, the trie of Cesia's maps.
- Andreas Gal and others, *Trace-based Just-in-Time Type Specialization for Dynamic Languages*, 2009: the tracing JIT,
  which LuaJIT is, and Cesia isn't.
- Vladimir Makarov's MIR, which makes Cesia's machine code.

Each with its link in [References](references.md#the-jit) and [Values and maps](references.md#values-and-maps); [How Cesia works](internals.md#the-jit) shows the JIT inside.

## Next

Your programs run fast with nothing to write. The next chapter, [C and C++](c.md), calls the libraries of the system from
Cesia.
