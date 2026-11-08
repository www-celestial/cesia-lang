# How Cesia works

In this chapter you look inside Cesia: what happens between the text of a program and its output, how its values sit in
memory, how the JIT makes machine code, how fibers take turns, and how a server uses every core. You need none of it to
write programs. It tells you why a program is fast or slow, what a guarantee rests on, and which words to search for to
learn more. Each part names the file of the repository where the code lives, under `src/`, and the
[References](references.md) give the papers.

Every number on this page says how it was measured, on one machine: an Intel Core i7-4720HQ of 2015, at 2.6 GHz, 4 cores
and 8 logical cores, Linux, OCaml 5.5, the `release` build; the others come from `bench/RESULTS.md` in the repository,
with their date.

## The path of a program

Cesia is an interpreter written in OCaml, with a JIT for what gets hot. An *interpreter* runs a program from a form of it
held in memory, without making a file of machine code first; a *JIT*, a just-in-time compiler, makes machine code for parts
of the program while it runs. A program goes through these steps, each one a module of `src/lib/`:

| Step | What it makes | File |
|---|---|---|
| The lexer | the tokens: names, numbers, texts, operators, ends of lines | `lexer.ml` |
| The parser | the syntax tree: one node per expression | `parser.ml` |
| The resolver | each name tied to its place: a variable of the function, a captured one, a name of the file or of a package | `resolve.ml` |
| Inference | a type for each variable and node of a version of a function | `infer.ml` |
| The compiler | OCaml closures, one per node, which run the program | `compile.ml` |
| The JIT | machine code for the hot functions and loops | `src/jit/`, loaded when needed |

The steps run per file, when the program first needs it, and per function, when it is first called: a function that never
runs is never compiled. `cesia check` runs the first three steps and its own checks of calls and types (`check.ml`), and
never runs the program.

## Reading: the lexer and the parser

The *lexer* cuts the text into tokens, the words of the language: `count`, `=`, `42`, `"a text"`. It reads UTF-8 and
rejects a file that isn't. A text with a `$` inside becomes its parts: the plain text, and the tokens of each piece of
code, which the parser reads as a call of [text.Str].

The *parser* turns the tokens into a *syntax tree*: a tree whose nodes are the expressions and statements of the program,
each with its line and column. For `total = price * (1 + tax)`:

```text
Assign total
└── Bin *
    ├── Name price
    └── Bin +
        ├── Int 1
        └── Name tax
```

The parser is written by hand, as a *recursive descent* parser: one function per rule of the grammar, each calling the
others, so the nesting of the calls follows the nesting of the code. Each level of operators has its function, from the
loosest to the tightest: `then`, `or`, `and`, `not`, the comparisons, `..`, `+` and `-`, `*` and `/`, the unary `-`, `^`,
and the calls, indexes and fields. That order is the *precedence* of the operators: `1 + 2 * 3` is `1 + (2 * 3)` because
`*` is read at a deeper level. A line ends a statement, except inside `( )` and `{ }`; inside `[ ]` it starts a new row of
a matrix.

A syntax error stops the load with its file, line and column, and most messages say what to write instead. Code nested
deeper than the `nesting` limit, 600 by default, is refused here, before anything runs: the parser calls itself once per
level, and a limit keeps a hostile file from overflowing its stack.

## Names: the resolver

The *resolver* walks the tree once and decides what each name means. Cesia has *lexical scope*: the names a piece of code
sees are those written around it in the text, not those of whoever calls it. A name is one of:

- a *local variable*: a parameter, or a name given a value in the function. It gets a slot, a numbered place in the
  function's frame;
- a *captured variable*: a name of an enclosing function, used by a function written inside it;
- a name of the file, or of another file of the same package;
- a name of a package that the file uses, as `list.Map`.

The resolver also checks *definite assignment*: a name read before any value reaches it is an error at load, `"x" has no
value yet.`, not a surprise at run time. It marks the calls in *tail position*, a call whose result is the function's own
result with nothing left to do after it: a function that calls itself there runs as a loop, so its depth doesn't grow.

```cesia
defn countdown(n)
  if n == 0
    return "done"
  end
  countdown(n - 1)
end
countdown(100000) --> "done"
```

The call to `countdown` is in tail position, so 100,000 calls run in one frame, under the depth limit of 10,000.

### Closures

A function written inside another one is a *closure*: a function together with the variables it captured from where it
was written. Cesia makes *flat closures*: when the inner function is made, the values of the variables it captures are
copied into it, in a small array. So a closure sees the values its variables had when it was made:

```cesia
n = 10
f = () -> n
n = 20
f() --> 10
```

This is what [value semantics](#values-in-memory) give for every value, and it lets a closure be sent to another fiber
with nothing shared.

## Types: inference and versions

Cesia has *dynamic types*: a variable can hold an integer at one time and a text at another, and an operation checks the
kinds of its operands when it runs. Checking costs time at every operation, so Cesia proves, where it can, that a check
can't fail, and removes it.

A function gets one *version* for each combination of the types of its arguments that it meets: `area(2, 3)` and
`area(2.0, 3.0)` call two versions of `area`, one for two integers and one for two floats. This is called
*specialization*, or *customization* in the language Self, where it began. For each version, *inference* gives a type to
each variable and each node, among five: none yet, an integer, a float, an array of floats, or anything. Inference is a
*dataflow analysis*: it follows the values through the code until the types stop changing. Two types that meet, as an
`if` that gives an integer on one side and a float on the other, become "anything". A type that inference gives is
proven, never guessed: in a version for integers, `a + b` adds two machine integers with an overflow check, and nothing
else.

A function has at most 8 versions; past them, a *generic version*, typed "anything" everywhere, takes the other calls.
`--no-spec` runs every function in its generic version only, which the tests use to check that both give the same
results. A type written in the code, as `n Int`, is checked when a value comes in, and is never used to make code faster:
an untyped program runs as fast as a typed one, by the owner's choice.

## Running: closures as code

The compiler turns the syntax tree into *closures*: OCaml functions made once per node, each calling those of its
children. `a + b` becomes a function that runs the function of `a`, the function of `b`, and adds. Running a closure is
much faster than walking the tree again at each step, because the work of looking at the node is done once, when the
closure is made. This is *closure compilation*, an old technique of interpreters, from the 1980s.

A version makes three kinds of closures, by what they give: a value, an unboxed integer, or an unboxed float. A *boxed*
number sits in its own block of memory, behind a pointer, with a tag that says its kind; an *unboxed* one is the bare
machine number, in a register or a slot. A version for floats keeps its floats unboxed, so `x * y + z` allocates nothing.

A running function keeps its variables in a *frame*: a run of slots on a stack. Cesia has three stacks per fiber, one of
values, one of integers and one of floats, so an unboxed number never needs a box to be stored. The stacks start at 4,096
slots for the main program and 16 for a fiber, and double when they are full.

### Steps and checkpoints

The program counts *steps*: a call is one, a turn of a loop is one, and a native that builds a list of `n` values counts
about `n / 16`. Every so often, at a *checkpoint*, the interpreter looks at the limits:

- at least every 10,000 steps, under the default depth limit: the `steps` limit, and the depth of the calls;
- every 1,000,000 steps, a *full checkpoint*: the output is flushed, the memory limit checked, a changed file reloaded
  under `--watch`, and the other fibers get their turn (see [Fibers](#fibers-and-the-scheduler)).

Under `--watch`, a full checkpoint comes every 100,000 steps, so that a changed file takes effect within 100 ms. Counting
is a subtraction and a test at each call and turn of a loop; the depth of the calls is counted only at a checkpoint, each
frame once, so a call costs no more for the depth limit. A limit is exact all the same: the steps between two checkpoints
are bounded by what is left before the limit.

### Caches at each site

A field read, as `p.X`, finds the place of `X` in the struct or the map. Each place in the code that reads a field keeps
the last *shape* it met and the place of the field in it, a *monomorphic inline cache*: when the next value has the same
shape, as it nearly always does in a loop, the read is one comparison and one load. A shape is described in
[Values in memory](#values-in-memory).

## Values in memory

Every value of Cesia is a value of one OCaml type, `Types.t` in `src/lib/types.mli`, a *tagged union*: a word that is
either a small constant or a pointer to a block whose header says which case it is.

| Value | In memory |
|---|---|
| `missing`, `true`, `false` | a constant in the word itself: no allocation |
| an integer | 63 bits, in the word itself: OCaml keeps one bit to tell numbers from pointers |
| a float | 64 bits of IEEE 754, in a block of its own; unboxed in a typed version and in an array of floats |
| a text | its bytes, in UTF-8, in a block that never changes |
| a list, a matrix, an array | a size per dimension and one store of cells, column by column: floats, integers or values |
| a struct | its *shape*, the names of its fields, shared by every struct of its kind, and an array of the values |
| a map | see [Maps: a hash table, then a hash trie](#maps-a-hash-table-then-a-hash-trie) |
| a function | its code, and the values it captured |
| a task, a channel, a connection | a *handle*: a kind and a number, which the system keeps track of |

An integer that grows past 63 bits is an error, not a silent wrap and not a slow bigger number: the message says to use a
float.

```cesia fails
4611686018427387903 + 1
```

### Value semantics and copy-on-write

Cesia values have *value semantics*: giving a value a second name, or passing it to a function, acts as a copy, and a
change through one name never shows through the other.

```cesia
xs = [1, 2, 3]
ys = xs
ys[1] = 10
xs --> [1, 2, 3]
ys --> [10, 2, 3]
```

Copying a list at every assignment would be slow, so Cesia copies only when it must, which is called *copy-on-write*. A
list, a struct or a map carries one bit, *owned*: true while one place alone holds it. A write to an owned value changes
it in place; a second name clears the bit, and a later write copies the value first, then owns the copy. In the loop
below, `xs` is owned all along, so each of the 1,000 writes changes the list in place:

```cesia
use std/list
xs = list.Fill(0, 1000)
for k in 1..1000
  xs[k] = k * k
end
xs[1000] --> 1000000
```

The bit is never set back once cleared: a value that was shared is copied at its next write even if the other name is
gone. That costs one copy, never a wrong result. A list made by [list.Append] keeps free cells behind its last one,
doubled when they run out, so a loop of appends costs a constant time per element on average: an *amortized* constant.

## Maps: a hash table, then a hash trie

A map, which Cesia calls a dictionary, takes any number or text as a key. It is a
[persistent data structure](glossary.md#persistent-data-structure): [dict.Put] gives a new map and leaves the old one as
it was, and both share most of their memory. Its storage, in `src/lib/trie.ml`, has three forms, and a program sees
none of them: the same keys, values, order, `==` and errors in each.

**Up to 32 keys, one block.** The keys sit in the order they came in, beside their hashes, and the values in a second
array. The maps made at one place of the code share their array of keys, as the structs of one kind share their shape:
`{X: 1, Y: 2}` in a loop makes many maps with one array of keys. A field read then caches the place of its key, as for a
struct. This sharing is the idea of *hidden classes*, from Self, where they were called maps, and from V8.

**Past 32 keys, while one name alone holds the map, a hash table.** A map that is *owned*, the bit of
[copy-on-write](#value-semantics-and-copy-on-write), keeps its keys in an *insertion-ordered hash table*, the layout of
Python's `dict` since 3.6, after a design of Raymond Hettinger. The entries sit in arrays in the order they came in, the
keys in one and the values in another; the values are bare machine integers in an array of integers while all of them
are integers, a *storage strategy* as Cesia's lists have (Bolz, Diekmann and Tratt, 2013), and a value of another kind
turns that array into one of values, once. Beside the entries, an *index* of slots, a power of two at least twice the
number of entries, each empty or holding the hash of an entry and its number. A key is found by *linear probing*: from
the slot its hash names, the slots one after the other until the key, compared first by the hash in the slot, or an
empty slot. At this half load, a key that is there takes 1.5 slots on average and one that isn't 2.5 (Knuth, *The Art
of Computer Programming*, vol. 3, 6.4), all in one or two cache lines of the index, where the trie below follows four or
five nodes. The order of the keys is free: it is the order of the entries.

```text
a map of 4 keys, its index of 8 slots
slots     [  -  | h2 #2 |  -  | h0 #0 | h3 #3 |  -  | h1 #1 |  -  ]    each empty, or a hash and an entry's number
entries   #0 "apple" -> 3   #1 "pear" -> 9   #2 "fig" -> 1   #3 "kiwi" -> 4    in the order they came
```

A write puts a new key at the end of the entries and in the first empty slot from its hash: in place, a constant time on
average. When the entries are full, both arrays double and the slots are placed again from their hashes: an
*amortized* constant time per key.

**Once a map is shared and written, a hash array mapped trie**, a HAMT. A write that must keep the old map, as
[dict.Put] on any map, or a write to a map that another name holds, first turns the table into the trie, in place and for
good, with the same keys, values and order: the next writes then copy only a path, as below. It is built in one pass: each
entry's hash, its six pieces of 5 bits reversed, is sorted by three passes of a *radix sort* (by 10 bits at a time,
counting), so that the keys of each node of the trie are next to each other, and each node is made once at its size.
That costs about 0.11 s for a million keys when they fit in the processor's caches and 0.25 s past them (109 and 245 ns a
key, at 100,000 and 1,000,000 keys), once per map; a program that keeps old versions of a big map pays it at its first
[dict.Put], then each Put costs a path. A *hash* is a number computed from a key, the same for the same key;
a *trie* is a tree where each level is chosen by a piece of the key. In a HAMT, each level takes 5 bits of the key's hash,
so a node has up to 32 places, kept compact by a 32-bit *bitmap* that says which places are used: the place of a key in
the node's arrays is the number of bits set below its own, counted by a few operations on the word. Cesia uses 30 bits of
hash, so a key is at most 6 levels down.

Cesia's nodes are those of *CHAMP*, the compressed hash-array mapped prefix tree of Steindorfer and Vinju, 2015. A node
has two bitmaps. The first marks the keys held in the node itself, inline, each beside its hash and its value: the keys
whose 5 bits at this level no other key under the node shares. The second marks the places that several keys share, each
holding a node of the next level for them. So a key goes down a level only when another key shares its bits, and no
node ever holds a lone key below it: when a key is dropped and leaves one beside it, that one comes back up into its
parent. A read follows one path from the root, about log₃₂ n levels, written O(log₃₂ n): 3 for 30,000 keys, 4 for a
million. A write copies only the nodes on that path, and of each only the array it changes, sharing the rest with the
old map: this is *structural sharing*.

```text
a map of 100,000 keys
root: 32 places, each a node, by bits 1-5 of the hash
└── place 17: a node of 32 places, by bits 6-10
    └── place 4: a node of about 98 keys under 32 places
        ├── "apple" -> 3, "pear" -> 9, ...      the keys alone at their place, inline
        └── place 12: a node of the 3 keys that share it
```

When nothing else holds a map that became a trie, its owned bit lets a write change its own nodes in place: each node
carries the mark of the map that made it, and its arrays keep room for a few more keys, doubled when they fill, up to 32.
A write to a map that is shared makes nodes of no mark, which nobody changes in place.

Before CHAMP, Cesia's deep maps ended in blocks of up to 8 keys, each made with room for 8 whatever it held: at 500,000
keys, a level of blocks of one or two keys each, five levels deep, and a heap of 16 million words, 128 MB, where CHAMP's
takes 7.7 million, with a fifth of the allocation (`bench/maps.ce`, the counters of OCaml's collector).

Each key of the trie carries its rank in the order of insertion, so [dict.Keys] gives the keys in the order they came
in, at any size.

**Why the table first.** The benchmark `bench/maps.ce`, 500,000 text keys written then read, took 815 ms in the trie and
takes 275 ms in the table (11 runs of each language, alternated, [Speed](speed.md#computing)): a read of the trie followed four or five nodes, each a miss of the processor's caches once the
map outgrows them, 18.7 misses of the last level of cache an operation against 4.3 for Go and 3.7 for Python (counted by
the processor's own counters); and every node, key and boxed integer was copied out of OCaml's young heap and marked
again at each major cycle of its collector. The table holds a key in one entry and its integer value in an array of
integers that the collector scans without following anything. A map is shared and then written far less often than it
is built or read, and when it is, it becomes the trie that persistence needs, once.

Three details matter for safety and for numbers:

- **The hash takes a seed**, a random number drawn once per run. Without it, someone who knows the hash function could
  send a server keys that all share one hash, and every read would walk them all: a *hash flooding* attack, a denial of
  service.
- **Keys whose 30 bits of hash are all equal** go to a balanced binary tree, sorted by key, so even keys chosen to collide
  cost O(log n), never O(n). In the table, keys that fall together make long runs of full slots: a new key whose probe
  passes 128 slots turns the map into the trie, which no choice of keys makes deeper. Random keys don't come near it: in a
  simulation of our table at its load, the longest probe of an insert was 45 slots in ten runs of a million random keys,
  and 51 in two runs of four million.
- **`1` and `1.0` are one key**, as they are equal numbers: a number hashes by its value.

```cesia
m = {1: "one"}
m[1.0] --> "one"
```

## The JIT

Cesia's JIT is in `src/jit/`. It is a *method JIT* that also compiles *loop regions*: it makes machine code for a whole
version of a function, or for one loop of it, rather than for a single path through the program as a *tracing JIT* does.
It is not loaded at start-up: it is a plugin, `cesia_jit.cmxs`, loaded once, at the first unit that gets hot, so a
program that never gets hot never pays for it.

### When code gets hot

- A version of a function whose result inference proves to be a number, an integer or a float, after 1,000 calls.
- A loop, at the second checkpoint met inside it: after 10,000 to 20,000 turns of a loop that runs alone. A loop that runs
  often but briefly, as in a function called for each request, gets hot once its runs add up to 100,000 steps.

`CESIA_JIT=always` compiles every candidate at its first call or run, which the tests use to compare both tiers on the
whole suite. `CESIA_JIT_SHOW=1` prints each unit compiled, or why the JIT didn't load.

### What it makes

The JIT turns a hot unit into its own *intermediate representation*, an IR: basic blocks of typed instructions on virtual
registers, of three kinds, integer, float and value. It writes the IR as text for
[MIR](references.md#the-jit), a small compiler of Vladimir Makarov, written in C and copied into `src/sys/mir/`, which makes
the machine code. Integers sit in registers doubled, `2n` for `n`, so that the processor's own overflow flag tells the
63-bit overflow of Cesia's integers at no cost.

**One join per loop.** The run of a loop's machine code can leave for the interpreter and come back: at a full
checkpoint, when the collector must make room, or after a step that a failed guard left to the interpreter. Each of these
comes back *before* the loop, where the same test of its counter and the same step lead into it, never into its body:
the entry at the head of a loop of Fink and Qian, 2003. MIR works in *SSA form*, where each variable is assigned once and
a *phi*, a merge of its versions, stands at each block where paths meet; leaving SSA puts a copy on each path into such
a block (Boissinot and others, 2009). When the run came back into the body, every variable of the loop met there, at each
turn, and MIR, which keeps most of them in stack slots, copied each from one slot to another: about 60 instructions a turn
of `dyn` and of `structs`. Now only what the loop changes meets at the start of its body: `dyn` runs in 1,340 million
instructions instead of 1,919, and 114 ms instead of 184; `structs` in 1,220 instead of 1,500, 187 ms instead of 225
(11 runs each, alternated, beside main's binary).

It compiles numbers and loops on them, arrays of floats and of values read and written by index, calls between compiled
versions, recursion, in a loop the fields of maps and structs and new ones made there, and calls of a function held in a
variable, as the next part shows.

A division or a modulo of integers by a power of two, as `math.Mod(i, 4)`, becomes a shift or a mask of bits: a
division instruction costs tens of cycles, a mask one. The results are those of the floor, which Cesia's `Div` and `Mod`
give, for negative numbers too: `math.Mod(-7, 4)` is 1 in both.

### Bets, guards and bails

Where inference can't prove a type, the JIT *speculates*: it looks at the values in the frame when it compiles, the
*type feedback*, and bets that they keep their kind, that `p` stays a `Particle` and `p.X` a float. Each bet is a *guard*,
a test in the machine code. When a guard fails, the machine code stops before the statement where it failed, every
variable back in its slot as the interpreter wants it, and the interpreter runs on from that statement: a *bail*, which
other JITs call *deoptimization*. The loop gets its machine code back at its next turn. The answer is the same, a little
later.

Entering machine code in the middle of a loop that is already running, at a checkpoint, is called *on-stack replacement*;
Cesia does it for loops, with the counter and the bound of a `for` put in their slots.

### Calls through a value

A call of a function held in a variable, as `f(total, x)` where `f` came from a list of functions, can reach a
different function each time. The interpreter notes, at each such call, the functions it reached, at most four. The JIT
bets on them: the machine code tests the function against the first, then the second, and calls the one that matches as
it calls a function named in the code, or copies its body in place, *inlining* it; a function it didn't see bails, as a
failed guard does. This is a *polymorphic inline cache*, the idea of Hölzle, Chambers and Ungar (1991), which V8 and
HotSpot use for the same kind of call. A call that reached five functions or more is *megamorphic*: the JIT leaves it to
the interpreter, and so does a call of a function that captured variables, or that takes or gives values other than
numbers.

```text
f(total, x)                      in machine code
├── f is (a, b) -> a + b ?       total + x, unboxed, inline
├── f is (a, b) -> a * 0.5 + b ? total * 0.5 + x, inline
└── else                         back to the interpreter, before the statement
```

### The contract

The same program gives the same output, the same errors at the same lines, and the same limits, in the interpreter and in
machine code. Machine code counts steps as the interpreter does, checks bounds and overflow as it does, and leaves for
the interpreter at each full checkpoint, where the other fibers get their turn. It never runs the garbage collector: each
turn of a compiled loop reserves the memory it will need first, and leaves if there isn't enough, so the collector runs in
OCaml as usual. The tests run the whole suite in both tiers, and a difference is a bug of the JIT.

### What stays in the interpreter

- the natives, functions of `std/` written in OCaml, as [text.Split]: they are machine code already;
- `for x in xs` over the elements of a list, and a call through a value that reached five functions or more, or a
  function that captured variables;
- under a debugger, the functions that hold a breakpoint and the code you step through;
- everything on arm64, as Apple's chips, for now: programs run in the interpreter there, with the same results.

### What it gains

Measured on the evening of 2026-11-08, `release` profile, on the machine of [Speed](speed.md#beside-the-giants) while
other work ran on it: each program of `bench/` 11 times with the JIT and 11 times with `CESIA_JIT=off`, alternated with
the giants, from the start of the process to its end (`real/particles`, against main's binary, alternated). The median,
then its 95% interval:

| Program | What it does | With the JIT | Interpreter only |
|---|---|---:|---:|
| `fib` | `fib(35)`, recursive calls on integers | 73 ms (73–74) | 438 ms (436–470) |
| `mandel` | a loop of floats | 61 ms (61–63) | 469 ms (468–477) |
| `matmul` | matrices of floats, read by index | 47 ms (46–47) | 950 ms (938–1,093) |
| `structs` | 1,000 maps of 4 floats, remade 5,000 times | 186 ms (182–188) | 553 ms (546–571) |
| `real/particles` | 1,000 structs, gravity and walls | 136 ms (135–139) | |
| `dyn` | calls through a list of functions | 114 ms (112–115) | 720 ms (693–769) |
| `maps` | 500,000 text keys written then read | 275 ms (272–278) | 278 ms (274–282) |

`dyn` calls each function through a value, which the JIT now makes machine code with its inline cache of functions,
and its `math.Mod(i, 2)` and `math.Mod(i, 4)` a mask of bits: before both, on the same day, it took 714 ms with the JIT, as
long as without it, then 182 ms before its loop was entered only at its head; `structs` took 219 and `real/particles`
175. The loop of `maps` builds a text at each turn and stays in the interpreter: its gain is the hash table's.

[Speed](speed.md#beside-the-giants) puts these programs beside Python, Node, Java, Go, OCaml, Lua and LuaJIT.

## Fibers and the scheduler

A [fiber](fibers.md) is a function that runs beside the others, in the same program, with its own stack: what other
languages call a *green thread* or a *coroutine*. All fibers run on one system thread, one at a time. They are
*concurrent*, several in progress and taking turns, not *parallel*, several at the same instant on several cores.

### How a fiber stops and starts

Cesia's fibers are OCaml 5's *effect handlers*, from `src/lib/fiber.ml`. An *effect* is like an exception that can come
back: a fiber that must wait performs the effect `Suspend`, and the handler around the fiber receives the rest of the
fiber's work, its *continuation*, a value that can be resumed once. The handler stores it in the thing the fiber waits for,
a channel, a timer, a socket, and returns to the scheduler. When the thing is ready, the continuation goes on the queue of
fibers ready to run, and is resumed in its turn. A continuation holds the fiber's OCaml stack, which starts small and grows
as needed: a new fiber takes about 320 words, 2.5 KB, as `tools/fiber-size.sh` measures, with its three stacks of 16
slots. The main program is no fiber: it
keeps its own stack, and when it waits, it runs the scheduler itself until it is woken.

The *scheduler* keeps one queue, first in, first out, of the fibers ready to run. A fiber runs until one of these:

- it waits: [sys.Sleep], a read or a write on the network that would block, [fiber.Wait], [fiber.Receive],
  [fiber.Select], a [fiber.Send] on a full channel, a database that is busy;
- it reaches a full checkpoint, every 1,000,000 steps, while another fiber is ready: it then goes to the back of the
  queue;
- it ends, or panics.

So a long computation can't hold the others for more than a million steps. This is close to what Erlang does by
counting *reductions*, and it is called *preemptive* there: nobody writes a yield. It is not the preemption of a system
thread, which a timer can interrupt anywhere: a fiber is switched only at a wait or a checkpoint. Two consequences:

- a native runs to its end: [list.Sort] of a million elements, or [json.Parse] of a large file, runs whole before another
  fiber gets its turn;
- in machine code that calls itself, a recursion compiled by the JIT, a switch waits until the outermost compiled call
  returns or its loop reaches its next step. Results never change; only the order in which fibers print can differ there.

Since a fiber is switched only at those points, code between two of them sees no other fiber: there are no *data races*,
two threads changing the same memory at once, and no locks to take. Values are not shared anyway: a value sent on a
channel acts as a copy.

### Waiting on the system

A socket of Cesia is *non-blocking*: a read that has nothing gives back at once, and the fiber parks. When no fiber is
ready, the scheduler asks the system which sockets are ready, and wakes their fibers. On Linux it uses *epoll*, which
watches any number of sockets at the cost of the ready ones only; on macOS and Windows, *select*, which watches up to 1,000.
While fibers are ready, it still looks at the system every 256 turns, so a busy program keeps hearing the network. Timers,
for [sys.Sleep] and the timeouts, are kept in a tree sorted by their deadline.

When every fiber waits, nothing is ready and nothing can be, as no socket, timer or signal is awaited, the program would
wait forever: a *deadlock*. Cesia stops it with the line of the wait:

```cesia fails
use std/fiber
ch = fiber.Channel()
fiber.Receive(ch)
```

### Cancel and panics

[fiber.Cancel] marks a fiber. If the fiber is waiting, it is woken at once; otherwise it stops at its next wait or full
checkpoint. Either way the fiber unwinds as a panic does, quietly, and [fiber.Wait] gives an `Err` of kind `"cancelled"`
with the file and line where it was. A panic in a fiber ends that fiber only, and its task gives an `Err` with the message.
A fiber that takes more memory than the limit, or nests a value too deep, stops alone as well: a server's request that
takes too much fails alone, and frees what it took.

## Channels

A channel, [fiber.Channel], is a queue of values between fibers. It comes from *communicating sequential processes*, CSP,
the model of C. A. R. Hoare in 1978, where processes share no memory and only exchange messages, and from Go, whose
channels follow it. Cesia's are close to Go's, with these exact rules:

- **Unbounded by default.** [fiber.Send] never waits on a channel made without a size: it can hold any number of values,
  as many as the memory allows.
- **Bounded with a size.** With `size = n`, the channel holds `n` values at most, and a send on a full channel parks its
  fiber until a receiver takes a value: [backpressure](glossary.md#backpressure).
- **A size of 0 is a rendezvous.** Each send waits for a receiver, so the two fibers meet: the synchronous channel of
  Hoare's CSP, and Go's unbuffered channel.
- **First come, first served.** The oldest receiver parked on a channel gets the next value, and the oldest sender
  parked on a full channel goes first.
- **Close.** After [fiber.Close], the values already in the channel still come, then [fiber.Receive] gives an `Err` of kind
  `"closed"`. A send on a closed channel, or a second close, is a bug, and panics.
- **Select in order.** [fiber.Select] takes from the first channel of its list that has a value, in the order of the
  list. Go picks at random among the ready ones; Cesia's order lets a program give one channel priority, as a stop before
  the work.

## The server

[http.Serve] is written in Cesia, in `src/std/http.ce`, on [std/net]. One fiber accepts the connections, and each
connection gets a fiber of its own, which reads the requests, calls the handler, and writes the responses. A connection is
kept open between requests, *keep-alive* in HTTP/1.1. A last fiber, the reaper, closes each connection that passes its
deadline. A slow client only parks its own fiber, so the others go on.

### On every core

One process uses one core. `cesia run --workers N` serves on `N` processes, from `src/sys/workers.ml`, in the
*pre-fork* model of servers such as nginx:

1. The first process runs the program until it opens its listener, the socket that takes new connections. It then becomes
   the *supervisor*: it starts the workers, and serves nothing itself.
2. Each worker is a `cesia run` of the same program, which gets that listener as its standard input, and accepts its
   connections from it. The workers share the listener and nothing else: each has its own memory, fibers and values.
3. On Linux, each worker watches the listener with `EPOLLEXCLUSIVE`, so a new connection wakes one worker, not all of
   them, which would race for it: the *thundering herd* problem.
4. A worker that ends is started again; one that ends within a second of its start waits first, 0.1 s, then twice as long
   each time, up to 30 s, so a worker that can't start doesn't spin.
5. On HUP, the supervisor starts a new set of workers from the files as they are now. Once each of them accepts, the old
   ones get TERM, and each finishes the requests in progress. The listener stays open all along, so no connection is
   refused: a *zero-downtime reload*. New workers that don't accept within 30 seconds are stopped, and the old ones stay.

The workers write their lines on one standard output. A write of at most 4,096 bytes that ends a line is *atomic* on a
pipe, by the rule of POSIX called `PIPE_BUF`: no other worker's write can cut it, so the lines of [std/log] never mix.

### What it serves

On one core of the machine above, a tiny route answers about 62,000 requests a second at 100 kept connections, as many as
Go's `net/http` on one core and a third more than Node, with no request lost, and an idle connection takes 2.3 KB:
the medians of 6 runs of `tools/http-bench.sh`, which [Speed](speed.md#a-server-under-load) gives in full, beside Node and
Go, with where they win. `tools/http-gate.sh` fails a change to the server that loses a request, falls under Node or
under its floors, passes 10 ms at the 99th percentile, or lets `--workers 2` give less than one and a half times one
process.

## Memory and the garbage collector

Cesia doesn't free memory itself: OCaml's *garbage collector* does, the GC, which finds the blocks that nothing points to
any more and reuses their memory. OCaml's is *generational*: new blocks go to a small *minor heap*, which is emptied often
and fast, because most blocks die young, as the boxed floats of a computation do; the blocks still alive move to the
*major heap*, which is collected little by little, in slices, so a program never stops for long. Cesia sets the minor
heap to 16 MB, 2 million words, at start-up, since its trees, closures and boxed floats nearly all die young there.

The memory limit, 80% of the machine's memory unless `--limit memory=` says otherwise, is checked at full checkpoints and
before each large allocation. When the heap seems past it, Cesia runs a full collection first, and stops the program only
if the memory still in use is past the limit: garbage alone never reaches it.

The work on whole arrays and columns of [std/num], [std/frame] and [std/sql] runs on several cores, through OCaml 5's
*domains*, its system threads: half the logical cores, at most 16, unless `CESIA_CORES` says otherwise. A small array
stays on one core, since starting a domain has its cost. That work touches no value of the program while it runs, so it
can't race with the fibers.

## Start-up

A program starts at once. Measured on 2026-11-08 on the machine above, 300 runs of each alternated, from the start of the
process to its end, the minimum then the median:

| Program | Time |
|---|---:|
| `/usr/bin/true`, a program that does nothing | 0.41 / 0.51 ms |
| `cesia version` | 2.22 / 2.59 ms |
| `use std/io` and `io.Print(1)` | 2.49 / 2.80 ms |

So running a program, once Cesia has started, takes about 0.3 ms. What a start does:

- the system loads the binary, and fixes up the addresses of its data, 28,458 of them in the count of 2026-11-07, as a
  *position-independent executable* needs: one that can be loaded at any address, which makes a bug in C harder to
  exploit;
- the OCaml runtime starts, and Cesia sets its minor heap;
- the sources of `std/` are inside the binary, so nothing is read from the disk but the program itself. A package of
  `std/` is read when a file first uses it: one written in Cesia, as `std/list`, costs about 0.8 ms more to parse and
  resolve, at each run, as `bench/RESULTS.md` measured on 2026-11-07; the parts in OCaml cost nothing until called;
- the JIT, SQLite, the runner of `cesia test` and the engine of the debugger are plugins beside the binary, loaded at
  their first use. None of them costs a program that doesn't use it.

Loading, the lexer, the parser and the resolver together, reads about 500,000 lines a second: 320,000 lines in 631 ms,
`bench/load.sh`, on 2026-11-07.

## Reloading code: --watch

Under `cesia run --watch`, Cesia looks every 50 ms at the time, size and file number of each file of the program. A
changed file is parsed and resolved again at the next full checkpoint. If it has an error, the old code stays and the
error is shown; otherwise its functions and structs replace the old ones, every function is compiled again at its next
call, and the code already compiled that calls an old version reaches the new one. The values and fibers of the program
stay as they were: this is *hot reload*. `tools/reload-test.sh` measured 12 to 19 ms from the save to the new function
running, on 2026-11-01.

## Further reading

The [References](references.md) give each work with its link. The ones this chapter rests on:

- the hash table of an owned map: Python 3.6's compact `dict`, after Hettinger; linear probing and its cost, Knuth, *The
  Art of Computer Programming*, vol. 3, 6.4; its integer values, Bolz, Diekmann and Tratt, *Storage Strategies for
  Collections in Dynamically Typed Languages*, 2013;
- the hash trie: Bagwell, *Ideal Hash Trees*, 2001, and Clojure's persistent maps, after it;
- versions by type, inline caches, hidden classes and deoptimization: the papers of Self, by Chambers, Ungar and Hölzle,
  1989 to 1994;
- closures as code: Feeley and Lapalme, *Using Closures for Code Generation*, 1987;
- fibers: Sivaramakrishnan and others, *Retrofitting Effect Handlers onto OCaml*, 2021;
- channels: Hoare, *Communicating Sequential Processes*, 1978, and the Go specification;
- the garbage collector: Sivaramakrishnan and others, *Retrofitting Parallelism onto OCaml*, 2020;
- hash flooding: Crosby and Wallach, *Denial of Service via Algorithmic Complexity Attacks*, 2003.

## Next

The [References](references.md) list the papers, standards and books that Cesia follows, each with what Cesia took from
it.
