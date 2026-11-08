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

This loop over a list of structs runs as machine code once it is hot, about fifteen times as fast as in the interpreter:
`bench/real/particles.ce`, the same loop on 2,000 particles, takes 49 ms against 811 ms without the JIT, the medians
of 11 and 5 runs on the machine of [Beside the giants](#beside-the-giants):

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
same, a little later. While the bets hold, `p` is never made: the machine code keeps its two floats in registers, and
writes the new `Particle` in place of the old one, which nothing else holds, as
[How Cesia works](internals.md#what-it-makes) shows.

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
| `/usr/bin/true`, nothing | 0.53 ms | 0.52 to 0.54 |
| Lua | 0.85 ms | 0.82 to 0.86 |
| LuaJIT | 1.01 ms | 0.99 to 1.02 |
| OCaml, native | 1.07 ms | 1.05 to 1.09 |
| Go | 1.32 ms | 1.28 to 1.37 |
| **Cesia** | **2.88 ms** | 2.85 to 2.91 |
| Python | 14.15 ms | 14.09 to 14.21 |
| Java | 25.39 ms | 25.11 to 25.65 |
| Node | 38.32 ms | 37.77 to 39.18 |

Cesia starts 5 times sooner than Python, 9 times sooner than Java and 13 times sooner than Node. A compiled Go or OCaml
program, or Lua, starts in about half its time: Cesia carries its whole runtime, its standard library and its compiler
in one binary, and the system must fix up the addresses of its data at each start, as
[How Cesia works](internals.md#start-up) shows.

### Computing

Milliseconds, median and 95% interval of 11 runs:

| Program | Cesia | Cesia, no JIT | Python | Node | Java | Go | OCaml | Lua | LuaJIT |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `fib` | **74** (73–76) | 439 (436–450) | 1,447 (1,422–1,500) | 176 (172–182) | 72 (71–76) | 49 (49–56) | 53 (52–61) | 691 (685–720) | 96 (94–109) |
| `mandel` | **62** (61–62) | 470 (467–489) | 2,668 (2,581–2,819) | 94 (89–98) | 82 (82–83) | 52 (51–54) | 57 (57–59) | 432 (430–437) | 55 (55–56) |
| `matmul` | **47** (46–47) | 959 (944–1,097) | 5,140 (5,020–5,343) | 96 (94–98) | 93 (92–94) | 33 (33–39) | 60 (59–69) | 831 (825–958) | 87 (86–90) |
| `structs` | **49** (47–54) | 608 (588–672) | 1,777 (1,732–1,868) | 175 (169–176) | 111 (110–114) | 9 (9–9) | 30 (30–33) | 1,507 (1,483–1,567) | 393 (390–415) |
| `dyn` | **57** (57–59) | 700 (678–741) | 1,387 (1,368–1,439) | 168 (165–179) | 97 (87–113) | 28 (28–29) | 68 (67–71) | 713 (711–727) | 57 (57–59) |
| `maps` | **258** (253–263) | 258 (249–265) | 410 (404–414) | 547 (536–579) | 226 (219–234) | 272 (265–293) | 516 (492–543) | 842 (798–904) | 324 (306–343) |

Measured again late on 2026-11-08, after the hash table of big maps, the loops entered only at their head, numbers kept
in registers across the turns of a loop, and maps and structs of floats kept as doubles, read and written in place
([How Cesia works](internals.md#what-it-makes)): `maps` took 815 ms that afternoon, `dyn` 182 and `structs` 219, the
other rows within a few percent of today's. The `maps` row is of 2026-11-09, after texts of a word and an integer were
made in one copy: 277 ms before.

What each program does: `fib` is `fib(35)`, about 30 million recursive calls on integers; `mandel` a loop of floats over
600 × 400 points; `matmul` the product of two 300 × 300 matrices read by index; `structs` 1,000 records of four floats,
each remade at each of 5,000 steps; `dyn` 10 million calls through a list of two functions, on values of mixed kinds;
`maps` a map of 500,000 text keys, written then read.

**Where Cesia wins.** On loops of numbers and on recursion, the JIT puts Cesia beside Java and LuaJIT, and ahead of
Node: `matmul` runs in half the time of Java, Node and LuaJIT, and ahead of OCaml's, `mandel` and `fib` in about the time
of Java. Against Python, the language most of its users come from, Cesia is 20 times faster on `fib`, 43 times on
`mandel` and 109 times on `matmul`; against Lua, 7 to 31 times, and 3 times on `maps`. On `dyn` it is ahead of Node,
Java and OCaml, 57 ms against 168, 97 and 68, level with LuaJIT, and 24 times Python. On `structs` it is ahead of Java,
49 ms against 111, of Node, 175, and of LuaJIT, 393. On `maps` it is ahead of every language but Java, Go included:
258 ms against 272.

**Where a giant wins, and why.**

- **Go wins every line but `maps`; OCaml wins `fib`, `mandel` and `structs`.** They compile the
  whole program to machine code before it runs, with every type known.
- **`structs`: OCaml takes 0.6 times Cesia's time, Go a sixth.** A map of four floats now keeps them as doubles, and the
  JIT never makes the map it reads from the list: it keeps its four doubles in registers and writes the new ones in place
  of the old, which nothing else holds ([How Cesia works](internals.md#what-it-makes)). A step allocates nothing:
  219 ms, then 186, now 49. What is left, about 60 instructions and 24 cycles a step against Go's 19 and 5: each step
  reads the map's address from the list and checks its kind, its keys, that it is owned and that its store holds
  doubles, where Go's array holds the records' floats themselves at known places; and about 12 ms of fixed cost, the
  start of the process, the first steps in the interpreter, and the compiling of the loop. OCaml makes a new record of 5
  words at each step, with no check: 30 ms.
- **`dyn`: Go takes half the time; LuaJIT is level; Cesia is ahead of Java, OCaml and Node.** `total` comes from a call
  through a function held in a list, which the inference can't type; the JIT keeps it a float in a register for the
  whole loop, and the call is a test of the two functions it met, inlined, the *polymorphic inline cache* of
  [How Cesia works](internals.md#calls-through-a-value): 714 ms, then 182, 114, now 57. Go's step is a call of all-float
  code with no test of kinds and no count of steps.
- **`maps`: Java takes an eighth less time; Cesia is ahead of every other, Go included.** A big map that one name alone holds is now an
  insertion-ordered hash table, Python's layout, and becomes the [CHAMP](glossary.md#champ) trie of
  [persistent](glossary.md#persistent-data-structure) maps only once it is shared and written
  ([How Cesia works](internals.md#maps-a-hash-table-then-a-hash-trie)): 815 ms before, 275 with the table, 258 since each
  key `"key$k"` is made in one copy instead of three ([How Cesia works](internals.md#running-closures-as-code)), in 68 MB,
  against 70 MB for Python, 50 for Go and 139 for Java. The processor's counters say why: 3.1 misses of its last level of cache an
  operation, where the trie took 18.7, against 3.7 for Python and 4.3 for Go. Java's 224 ms comes from a collector that
  works on the other cores and a hash kept inside each of its strings; and the loop of `maps`, which builds a text at
  each turn, stays in Cesia's interpreter: its share is about a tenth of the time, and native code would have to call
  back into OCaml for the hash, the table and the text ([How Cesia works](internals.md#what-stays-in-the-interpreter)).
  The price of the table: the first [dict.Put] on a big map that was built in place turns it into the trie, about
  0.25 s for a million keys, once.
- **Node and Java start slowly but run fast**: their JITs compile more, and later, with more time to spend on it.

### Fibers beside goroutines, async and virtual threads

100,000 tasks that park on one gate, then all end once it opens: Cesia's fibers, Go's goroutines, Node's `async`
functions on one promise, Python's `asyncio` tasks on an event, Java 21's virtual threads on a latch, and Lua's
coroutines, which have no scheduler, resumed by a loop. 11 runs of each, alternated, on 2026-11-09; the time per task is
that of 100,000
tasks less that of one, divided by 100,000, and the memory per task the peak memory of the process with 100,000 tasks less
that with one, divided by 100,000:

| | 100,000 tasks | 95% interval | Per task | Memory per task |
|---|---:|---:|---:|---:|
| LuaJIT coroutines | 59 ms | 58 to 69 | 0.6 µs | 0.4 KB |
| Node `async` | 167 ms | 165 to 173 | 1.3 µs | 1.3 KB |
| Go goroutines | 129 ms | 127 to 134 | 1.3 µs | 2.6 KB |
| Lua coroutines | 132 ms | 131 to 134 | 1.3 µs | 1.0 KB |
| **Cesia fibers** | **351 ms** | 348 to 353 | **3.4 µs** | **2.1 KB** |
| Python `asyncio` | 1,072 ms | 1,055 to 1,083 | 10.0 µs | 1.4 KB |
| Java virtual threads | 1,663 ms | 1,562 to 1,738 | 16.2 µs | 2.3 KB |

A Cesia fiber takes a third of the time of a Python task and a fifth of a Java virtual thread to start, park and end,
and 2.7 times a goroutine; with its task it takes 2.1 KB, less than a goroutine's 2.6 KB and a virtual thread's 2.3 KB.
It took 4.3 µs and 2.5 KB until 2026-11-08: its stacks now start at 8 slots, not 16, its body and its end make no
closure, a fiber that waits for a task leaves its own wake there, and one handler, made once, serves every fiber. Each
fiber has three stacks of its own, for values, integers and floats, beside its OCaml stack: they double when they fill,
as a goroutine's stack starts at 2 KB and is copied into a larger one. About 1 KB of the 2.1 is that OCaml stack: OCaml
starts a fiber at 64 words and doubles it at the first call of the interpreter inside it (gdb counts one growth per
fiber), so a parked fiber holds 128 words. What a goroutine doesn't pay is
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
