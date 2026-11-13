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
slots for the main program and 8 for a fiber, and double when they are full.

A text made by [string interpolation](glossary.md#string-interpolation) from a word and an integer, as `"key$k"`, is
written in one piece: the word, then the digits, into a buffer the interpreter keeps, and the text copied out of it once.
Made in three steps, the digits, a text of them, then a text of both, it took three allocations and three copies; one
copy is the floor in OCaml without its unsafe functions, which Cesia's core never uses: a buffer becomes a text only by
a copy. `bench/maps.ce` makes a million
such keys: 277 ms before, 253 after, 1,830 million instructions before, 1,643 million after (the processor's counters,
one run each). An integer shown alone, as `"$k"` or [io.Print], is made the same way.

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
| a struct | its *shape*, the names of its fields, shared by every struct of its kind, and a store of its values: their doubles while all are floats, as an array of floats keeps them, else the values |
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

The values of such a map, and the fields of a struct, have a [storage strategy](glossary.md#storage-strategy) of their
own: while all of them are floats, they are kept as bare doubles, as an array of floats keeps its cells; a value of any
other kind written into one turns that store into an array of values, once. An integer stays an integer: `{X: 1}` keeps
an `Int`, unlike a list of numbers, which keeps its integers as floats. A map of four floats takes 11 words of memory
this way, the map, its store and four doubles, against 25 when each float was a value of its own: a float value is two
blocks of OCaml, the case of the value and the boxed double it points to (Leroy, 1992, says why OCaml boxes a float
outside a float array or record). The price is in the interpreter: reading `p.X` from such a map makes a float value,
4 words, where it took the one stored; inside arithmetic, as `p.X + 1.0`, the interpreter reads the double without making
one. The interpreter alone runs `bench/structs.ce` 8% slower for it, 595 ms against 550 (5 runs each, alternated);
machine code, which reads and writes the doubles themselves, runs it in about 50 ms, as [What it makes](#what-it-makes)
shows.

```text
{X: 1.0, Y: 2.0, Vx: 1.0, Vy: 0.5}
before: map 4 words -> values 5 words -> 4 floats of 4 words each      25 words, 6 blocks
now:    map 4 words -> store 2 words  -> 4 doubles, 5 words           11 words, 3 blocks
```

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
parent. A read follows one path from the root, about $\log_{32} n$ levels, written $O(\log_{32} n)$: 3 for 30,000 keys, 4 for a
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
275 ms in the table, 258 since its keys are made in one copy (11 runs of each language, alternated,
[Speed](speed.md#computing)): a read of the trie followed four or five nodes, each a miss of the processor's caches once the
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
  cost $O(\log n)$, never $O(n)$. In the table, keys that fall together make long runs of full slots: a new key whose probe
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

**A number stays a number across the turns.** In `dyn`, `total` comes from a call through a value, so inference can't
type it, and before, each turn boxed its float into a new value and unboxed it at its next use. A variable of the loop
that the frame holds as a float or an integer when the loop compiles, and that the loop reads before it assigns it in a
turn, or assigns only with arithmetic, now gets a float or integer register for the whole run: the machine code checks
its kind once, when it enters, each assignment gives that kind or bails, and the box is made once, when the run writes
its variables back for the interpreter. This is *unboxing* by speculation, the way HotSpot and LuaJIT keep a loop's
accumulator in a register. With it, a register read after the calls of the write barrier was kept by MIR in a stack
slot for the whole loop, so the run now writes its numbers back before those calls: `total` lives in a register, and a
turn of `dyn` costs 64 instructions and 18 cycles of the processor, against 126 and 34 before this part and the next
(the processor's counters, the cost of one more turn, measured as the difference of 10 and 20 million turns).

**A value is marked shared once.** A list or map read from a list into a variable is held twice, so it must lose its
*owned* bit ([copy-on-write](#value-semantics-and-copy-on-write)) before anything may write it in place. Machine code
writes no such variable in place, so it now clears the bit once, when the run writes the variable back, instead of at
each read; a value the code knows is a number needs no mark at all.

**Bounds proved.** `math.Mod(i, 4)` by a positive constant is between 0 and 3, so `math.Mod(i, 4) + 1` can't overflow:
the addition goes unchecked. This is *range analysis*, the smallest form of it, on the bounds of integer registers. The
tests of the program prove bounds too, in each branch of an `if` that compares a parameter with a constant, when the
function never assigns that parameter: from the `else` of `if n < 2` on, `n` is at least 2, so `n - 1` and `n - 2` go
unchecked. A bound may hold on one side only: `n >= 2` says nothing of how big `n` is, yet `n - 1` can't overflow, as it
goes down from at least 2 and can't go up. The tests that guard branches are how ABCD (Bodík, Gupta and Sarkar, 2000)
proves its bounds, as constraints that hold along each edge of the program.

**A leaf at the call.** `fib` is a tree of calls, and half of its 30 million calls are leaves, `fib(0)` and `fib(1)`,
which only give back their argument; each paid a whole call, the saving and restoring of five registers included. When
the body of a callee starts with a test of its parameters that gives one of them or a constant, as `if n < 2 then n`,
the JIT makes that test at the call, on the arguments:

```text
fib(n - 1)        before: a call, whatever n - 1 is
                  after:  if n - 1 < 2, and its frame is under the limit of depth, and the fuel has a step left:
                              one step counted, the result is n - 1, no call
                          else the call, as before
```

When the test fails, or when the frame or the fuel is short, the call is made, and the callee does what it always did
at its entry, so the limits of depth and of steps, and the traces, stay the interpreter's. This is *partial inlining*
(Zhao and Amaral, 2005): the part of a function that returns early is copied into its callers, the rest stays a call. A
call of `fib` costs 18.8 instructions and 5.5 cycles instead of 26.4 and 7.2 (the processor's counters, the cost of one
more call, measured as the difference of `fib(30)` and `fib(35)`), Go's 14.5 and 5.9.

**A map that is never made.** In `structs`, each turn reads a map from a list, computes with its fields, and writes a
new map back to the same place:

```text
p = ps[i]
vy = p.Vy - 9.81 * dt
ps[i] = {X: p.X + p.Vx * dt, Y: p.Y + vy * dt, Vx: p.Vx, Vy: vy}
```

`p` is used only for its fields, so the machine code never makes it: when it reads `ps[i]` it checks that the map
there has these keys and a store of floats, and loads its four doubles into registers, which stand for `p`. This is
*scalar replacement* (Stadler, Würthinger and Mössenböck, 2014). If the run must give back to the interpreter, the map is
made then, of those registers, and only then: *allocation sinking*, as LuaJIT does on its traces (Pall, 2012). And the
new map written back has the same keys, all floats: when the map it replaces is owned, nothing else can see it, so its
four doubles are written in place, into the old map's store, which value semantics allows, the reuse of a unique value
that Lorenzen, Leijen and Swierstra (2023) make the rule of *fully in-place* functional programs. A turn then allocates
nothing and calls no write barrier; when the map there can't take them, the interpreter makes that one write and the
loop goes on in machine code. A struct gets the same, as `ps[i] = Particle(x, y, vx, vy, p.M)` in
`bench/real/particles.ce`. The values of a map that are all floats are doubles in its store
([Maps](#maps-a-hash-table-then-a-hash-trie)), so a field is one load and the check of its kind is gone too: a turn of
`structs` costs 60 instructions and 24 cycles, against 235 and 122 before, measured the same way.

**Lists of integers by index.** A list whose cells are all integers keeps them in a store of integers, as the part
Values in memory says. A loop reads and writes such a list by index as it does an array of floats: one load, the check
of the index, and the cell's integer, with no box, as a sparse product reads the rows of each column. In
`for q in colptr[j]..colptr[j + 1] - 1`, the statement `i = rowidx[q]` is a load from the list of integers, its index
proved inside before the loop, and `y[i] = y[i] + vals[q] * xj` checks `i` once, for the read and the write of `y`.

The index read from the list is the program's, so it is checked at each turn: an index outside `y` is the interpreter's
error, at the same line. An index checked in a block is not checked again in it, as `y[i]` read then written.

**A guard inside an if.** A guard that fails used to send the run back to the interpreter before the statement of the
loop that held it, and only while nothing of that statement showed: a write into an array, or a step, ruled it out. Now
each statement of a branch of an if inside the loop is a point of its own, which the interpreter can go on from: it runs
the rest of that branch, then the rest of each block around it, then the statements of the loop after them. And a step
or a call before the guard no longer rules it out: the run goes back with the fuel it had at the statement's start, so
the interpreter counts those steps again, as if native code had never made them. This is *deoptimization* at the
statement, as HotSpot does at the bytecode (Hölzle, Chambers and Ungar, 1992, who named it).

**What it can't make, it leaves.** A statement in a branch of an if that the JIT can't make, as `return failed(...)` or
`io.Print`, no longer leaves the whole loop to the interpreter: the run goes back to the interpreter before it, the
interpreter makes it, and the loop comes back to machine code at its next turn. Such statements are *cold*: they run
rarely, as the error paths and the end of a loop do. The loop is then made again with them out of what the JIT looks at,
so that a variable they alone assign, as a buffer made anew when it is full, is still an array of the loop. A call of a
small function whose body gives a text in one place and a number in another is made the same way: inlined, its number
path in machine code, and its text path a way back to the interpreter, which makes the call again.

**Tests and kinds.** `(fa > 0.0) == (fb > 0.0)` compares two tests; `value.IsNumber(x)`, `value.IsText(x)` and the other
tests of kind look at the tag of the value's block, or need no test at all when the JIT knows the kind; and a small
function that is one test, as `isFinite(x) = value.IsNumber(x) and x - x == 0.0`, is made in place, a test like any
other.

**Small arrays of floats.** An array of at most 15 floats that a loop makes again at each turn, as the state of an
equation, `y = y + h * f(t, y)`, is never made while the run lasts: its cells sit in slots of the frame, in a part of the
float stack, and each operation cell by cell becomes a few instructions on those slots, the operations of one statement
fused, with no array between them. In `k2 = f(t + c2 * s, y + (s * a21) * k1)`, the argument is made cell by cell,
`y[j] + (s * a21) * k1[j]` for each of the 3 cells, into 3 slots; and `f`, here
`lorenz(t, y) = [sigma * (y[2] - y[1]), ...]`, is inlined: the 3 cells of its literal go into the slots of `k2`.

Each operation counts its steps as the interpreter's natives do, one for an array under 16 cells, and the same cells,
in the same order, give the same floats: a sum adds from 0.0, each cell in turn, as the interpreter's. When the run ends,
or goes back to the interpreter, each such variable it assigned becomes an array again, of the same shape; a function
that gives an array of another size goes back to the interpreter. This is *scalar replacement* of the arrays, as for maps
above, and the fusion of operations on arrays that APL compilers made (Abrams, 1970).

It compiles numbers and loops on them, arrays of floats, of integers and of values read and written by index, small
arrays of floats made and worked on cell by cell, calls between compiled versions, recursion, in a loop the fields of maps
and structs and new ones made there, and calls of a function held in a variable, as the next part shows.

A division or a modulo of integers by a power of two, as `math.Mod(i, 4)`, becomes a shift or a mask of bits: a
division instruction costs tens of cycles, a mask one. The results are those of the floor, which Cesia's `Div` and `Mod`
give, for negative numbers too: `math.Mod(-7, 4)` is 1 in both.

### What it costs to make

The machine code takes time to make, which a run pays before it gains anything. MIR spends 6 to 7 µs on each line of
the text the JIT gives it, at its level 2, where it works in SSA form, numbers values, moves what a loop doesn't change
out of it and allocates registers (a copy of MIR with a clock on each of its passes: making SSA form takes a quarter of
the time, allocating registers a sixth, the liveness of values a tenth). Its level 1 makes code in 40 % less time, and
`matmul` then runs half again as long: level 2 stays. So the JIT gives MIR fewer lines:

- The paths a run takes when something rare happens, a failed check, a limit, an error, write what the interpreter needs
  to go on, and were four fifths of `fib`'s lines. The stubs of those that never come back now end in a block their
  function shares, one for an error, one for a frame past the limit of depth, one for a call on its way up after its
  callee stopped: each stub puts its own values in a few registers and jumps there.
- The outermost frame of a version, which the interpreter calls, calls a nested copy of the version instead of holding
  itself inlined: it runs once per call from the interpreter, and the nested copy does the work. This also fixed a loop
  that called its own function: MIR refused the call, and its error turned the JIT off for the rest of the program.
- The checks of a run's arrays, and its constants, are written once for its start and its resumes, not twice.
- The base of an inlined callee's frame is written from the function's own base and a constant, so no register holds it
  across a call.

`fib`'s unit went from 1,200 lines and 7.4 ms of compiling to 700 lines and 3.4 ms; `matmul`'s two units from 1,310
lines to 1,090, 10.4 ms to 8.4. A stub that comes back into its loop, the one that takes a new quantum of fuel, stays
inline: as a call, it made MIR keep every float of the loop in memory at each turn, around a call it almost never makes.
What is left of the fixed cost, beside the start of the process (2.6 ms): loading the plugin, 0.65 ms, and MIR's
compiling, 3 to 4 ms a unit.

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
the interpreter, and so does a call of a function that captured variables. A function that takes or gives other values
than numbers, as a small array of floats or a text on an error path, is inlined when it is small, with no loop: its
body is made in place, and what it can't make goes back to the interpreter, which makes the call.

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
- in a loop, a statement inside an if that it can't make, as a `return` of a struct or an `io.Print`: that statement
  alone, each time it runs, and the loop comes back to machine code at its next turn;
- arrays of more than 15 floats made in a loop: the interpreter's operations on them, which work on many cells at a
  time, already cost little a cell;
- a map read or written with a key computed as the program runs, as `m["key$k"]`, and the text built for it. Native code
  never calls back into OCaml: nothing collects during a run, which lets the values it holds stay in registers, where the
  collector couldn't find them to move them. The hash, the probe of the table, its growth and the new text would each
  need such a call, with every value written back to its slot first and read again after; what native code could save
  is the interpreter's own share of `bench/maps.ce`, a tenth of its time in its profile, and those calls would take much
  of it back;
- under a debugger, the functions that hold a breakpoint and the code you step through;
- everything on arm64, as Apple's chips, for now: programs run in the interpreter there, with the same results.

### What it gains

Measured on 2026-11-09, `release` profile, on the machine of [Speed](speed.md#beside-the-giants) while other work ran on
it: each program of `bench/` 11 times with the JIT and 11 times with `CESIA_JIT=off`, alternated with the giants, from
the start of the process to its end (`real/particles`, against main's binary, alternated). The median, then its 95%
interval:

| Program | What it does | With the JIT | Interpreter only |
|---|---|---:|---:|
| `fib` | `fib(35)`, recursive calls on integers | 58 ms (57–59) | 441 ms (438–489) |
| `mandel` | a loop of floats | 61 ms (61–62) | 456 ms (453–467) |
| `matmul` | matrices of floats, read by index | 44 ms (43–45) | 977 ms (963–1,017) |
| `structs` | 1,000 maps of 4 floats, remade 5,000 times | 46 ms (44–48) | 587 ms (579–594) |
| `real/particles` | 2,000 structs, gravity and walls | 53 ms (49–59) | |
| `dyn` | calls through a list of functions | 55 ms (55–57) | 761 ms (692–802) |
| `maps` | 500,000 text keys written then read | 257 ms (254–263) | 256 ms (251–278) |

`fib` took 74 ms the day before, until the leaves of its recursion were tested at their call and its unit took MIR half
the time to compile. `dyn` calls each function through a value, which the JIT makes machine code with its inline cache
of functions, its `math.Mod(i, 2)` and `math.Mod(i, 4)` a mask of bits, and its `total` a float in a register: before
those, on 2026-11-08, it took 714 ms with the JIT, then 182 before its loop was entered only at its head, and 114
before `total` stayed a register. `structs` took 219, then 186 before its maps were kept as doubles, and
`real/particles` 175, then 136. The loop of `maps` builds a text at each turn and stays in the interpreter: its gain is
the hash table's.

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
as needed: a new fiber takes about 270 words, 2.1 KB, as `tools/fiber-size.sh` measures, with its three stacks of 8
slots; about 1 KB of it is the OCaml stack, which OCaml starts at 64 words and doubles at the fiber's first call. One
handler, made once, serves every fiber: the effect carries the fiber that performs it, and the wake of a parked fiber is
kept in the fiber's context, where [fiber.Cancel] finds it. The main program is no fiber: it
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

On one core of the machine above, a tiny route answers about 64,000 requests a second at 100 kept connections, and the
JSON route 47,700, ahead of Node, with no request lost, and an idle connection takes 2.3 KB: the medians of 6 runs of
`tools/http-bench.sh`, which [Speed](speed.md#a-server-under-load) gives in full, beside Node and Go, with where they
win. `tools/http-gate.sh` fails a change to the server that loses a request, falls under Node or under its floors,
passes 10 ms at the 99th percentile, or lets `--workers 2` give less than one and a half times one process.

Each request runs its handler in a fiber of its own, which starts with small stacks and grows them in its first calls.
Each growth asked OCaml for the size of its heap, to check the limit of memory, and OCaml counts it by walking its pools
of blocks: a tenth of a server's time, in the profile of the JSON route (gdb's stacks, sampled every 3 ms). Stacks of
fewer than 4,096 entries are now left to the check of the full checkpoints. The timers of the scheduler, one or two a
request, are kept in a balanced tree ordered by their time, which now compares a time and a number directly, not
through OCaml's generic comparison. Both made the tiny route a fifth faster and the JSON route 14 % faster than the
binary before.

At 1,000 kept connections, one core serves 1,000 fibers in turn, and *Little's law* sets the floor of the latency: a
server that answers $\lambda$ requests a second with $L$ of them waiting answers each in $L / \lambda$ on average,
$1{,}000 / 36{,}200\ \text{s} = 27.6\ \text{ms}$ here, so its 99th percentile can't come under that until it answers
more. The requests in flight also live through more of OCaml's minor collections: a request's data is copied to the
major heap, 478 words a request at 1,000 connections against 69 at 100 (OCaml's counters, `v=0x400`), and the
collector takes about a fifth of the time there.

## Memory and the garbage collector

Cesia doesn't free memory itself: OCaml's *garbage collector* does, the GC, which finds the blocks that nothing points to
any more and reuses their memory. OCaml's is *generational*: new blocks go to a small *minor heap*, which is emptied often
and fast, because most blocks die young, as the boxed floats of a computation do; the blocks still alive move to the
*major heap*, which is collected little by little, in slices, so a program never stops for long. Cesia grows the minor
heap from OCaml's 2 MB to 16 MB, 2 million words, at a program's first checkpoint, or once it has loaded 32 KB of
source, since its closures and boxed floats nearly all die young there. Growing it costs about 0.15 ms, which a short
program that loads little never pays.

The trees of the code that a load makes are another case: they live as long as the program, and the first minor
collection after them copies them all to the major heap, about 15 ns a word. In the middle of the load of a program of
324 KB of source in 44 modules, that was 740,000 words and 11 ms, a third of its load, at whatever place the minor heap
filled. So the lexer, the parser and the resolver make as little garbage as they can: no closure for each node of the
tree or each name, and a file's array of tokens is emptied once the file is parsed, as an array of more than 256 places
is made in the major heap and the young tokens it points to would be copied with the trees, though nothing reads them
any more. The load of that program makes 1.84 million words instead of 3.38 million and ends before the minor heap is
full: 24.4 ms instead of 38.2, the medians of 21 runs, on 2026-11-11. A larger load gets a minor collection for each 2
million words it makes, each copying the trees made since the one before: every tree is copied once, so the cost grows
as the code does.

The memory limit, 80% of the machine's memory unless `--limit memory=` says otherwise, is checked at full checkpoints and
before each large allocation. When the heap seems past it, Cesia runs a full collection first, and stops the program only
if the memory still in use is past the limit: garbage alone never reaches it.

The work on whole arrays and columns of [std/num], [std/frame] and [std/sql] runs on several cores, through OCaml 5's
*domains*, its system threads: half the logical cores, at most 16, unless `CESIA_CORES` says otherwise. A small array
stays on one core, since starting a domain has its cost. That work touches no value of the program while it runs, so it
can't race with the fibers.

## Start-up

A program starts at once. Measured on 2026-11-09 on the machine above, 101 runs of each alternated with the binary
before this change, from the start of the process to its end, the median:

| Program | Time |
|---|---:|
| `/usr/bin/true`, a program that does nothing | 0.53 ms |
| OCaml's own `print_endline "1"`, compiled | 1.10 ms |
| `use std/io` and `io.Print(1)` | 2.62 ms, 2.84 before |

What a start does, counted by the processor's counter of the instructions run in the program, read at points of the
start in a debugger, and by the system's count of *page faults*, each a 4 KB page of memory that the kernel maps, copies
or zeroes the first time the program touches it, about 2 µs each on this machine:

- **The loader fixes up the binary's addresses**: 850,000 instructions, against 283,000 for OCaml's own program. Cesia
  is a *position-independent executable*, one that can be loaded at any address, which makes a bug in C harder to
  exploit; so each of the 30,332 pointers of its data gets the address the binary landed at added to it, and each page
  of 4 KB they are on, 256 of them, is copied for the process: a page fault each.
- **OCaml's runtime reads its frame descriptors**: 722,000 instructions. A frame descriptor says, for one place in the
  code where a call returns, which slots of the stack hold values, so that the garbage collector can find them; OCaml
  puts all of them in a hash table at start, 19,723 for Cesia, whose interpreter, compiler, parser and natives of
  `std/` are in the binary, against 322 for OCaml's own program. The table takes 512 KB, 129 page faults, and the
  descriptors themselves are two thirds of the relocated pages above.
- **The modules start**: 190,000 instructions, their tables of natives and of messages among them.
- **The program runs**: 400,000 instructions, from reading `cesia.toml` if there is one to the last flush; the sources
  of `std/` are inside the binary, so nothing is read from the disk but the program itself. A package of `std/` is read
  when a file first uses it: one written in Cesia, as `std/list`, costs about 0.8 ms more to parse and resolve, as
  `bench/RESULTS.md` measured on 2026-11-07, at its first run, and less once it comes from the
  [cache of loaded packages](#the-cache-of-loaded-packages); the parts in OCaml cost nothing until called.
- The JIT, SQLite, the runner of `cesia test` and the engine of the debugger are plugins beside the binary, loaded at
  their first use. None of them costs a program that doesn't use it.

The young heap grows to 16 MB only at a program's first checkpoint, or once it has loaded 32 KB of source
([Memory](#memory-and-the-garbage-collector)): growing it at start cost every program 0.2 ms, about 260,000 instructions
and 70 page faults, the first collection included, which a short program never needed. Moving the code that a run
rarely needs into plugins would take about 6 % of the frame descriptors off the start: the hash table halves only under
16,384 of them.

Loading, the lexer, the parser and the resolver together, reads about 520,000 lines a second: the 320,001 lines of
`bench/load.sh` in 614 ms, the median of 11 runs, against 648 ms before the load made less garbage, on 2026-11-11.
That is the first run of a package: the next ones read it from the cache below.

## The cache of loaded packages

Lexing, parsing and resolving cost about 3 µs a line, at each run: a program that uses [std/plot] read 2,300 lines
before its own first line ran, about two thirds of its time. So Cesia keeps the loaded form of each package, its trees
as the resolver leaves them, in the *cache of loaded packages*: the folder `cesia/load` of the folder of caches,
`$XDG_CACHE_HOME`, or `~/.cache` without that variable. At the next run, a package whose files are the same is neither
lexed, parsed nor resolved again: its trees are read back, and its statements run as before. Nothing else changes: the
same output, the same errors on the same lines, and the same speed once the program runs. The code is in `cache.ml` and
`src/sys/entries.ml`.

**What an entry holds.** One file per package, named by a digest of where the package is (its folder, or the name of a
file of `std/` inside the binary), and replaced when the package changes: the tree of each of its files after the
resolver, the names each file reads from each package it uses, and the questions the resolver asked about other modules,
with their answers. A name that the resolver tied to a module of another package keeps that module by its place: the
j-th module of the package of the file's u-th use. In another run, the modules get other numbers, and the places find
them. Nothing is kept for what the debugger adds (`--debugger`), what `cesia check` and the verdicts of `cesia test`
read with their own rules, and packages of less than 512 bytes, which parse faster than their entry is found and
checked.

**What a run checks before it uses an entry**, in this order:

- the file is the person's own, and no one else's: a plain file, not a link, that no one else may read or write, in a
  folder that is theirs alone, which Cesia makes so (permissions 0700 for the folder, 0600 for each file); the file
  opened is the one looked at, the same device and inode, so a link put in its place in between isn't followed;
- its *digest* is the one written at its start. A digest is a fingerprint of all the bytes of a file that changes when
  any of them does; Cesia's is BLAKE2b, of 16 bytes. A damaged or cut entry is never decoded;
- the entry names this build of Cesia, a digest of its sources made when it is built, the same `nesting` limit, and the
  digest of each source of the package, in order: a file changed since the last run is read again. A file of `std/`
  inside the binary changes only with the build, and needs no digest of its own;
- each use is found again on the disk, as without a cache, and each question the resolver asked is asked again: what a
  name of a used package is, in which cell it lives, whether it is a struct. The entry is used only if every answer is
  the same; otherwise the package is resolved from its sources, as when a package it uses gained a function before the
  one it calls, and its entry is written again.

The reader of an entry is plain OCaml, without `Marshal`, OCaml's own reader of values, which trusts its bytes: it
checks every count against the bytes left and every reference inside the entry, to a text, a module or a definition,
against what is there, so a wrong entry can only mean "not used". Any failure, an entry missing, damaged, of another
build, a folder that can't be written or a full disk, means only that the package loads as without a cache. Permissions
are never in an entry: they come from the command line and `cesia.toml` at each run, as the files that a use names come
from the disk.

**Writing.** The entries of a run are written once it ends, its output out and its exit code set, by a copy of the
process that the end doesn't wait for, made with `fork`: a run takes no longer than without a cache. Before anything
else, the copy closes every descriptor of the program, its files, sockets and pipes, and the run ends only once it has:
a port the program listened on, a lock it held and a pipe it wrote to are free as soon as it has ended, and nothing more
reaches a file it wrote. The copy then puts its input and output on `/dev/null`, leaves the terminal's session and takes
none of the program's signal handlers, so a shell that waits for the end of the output, or a key that stops the program,
neither waits for it nor stops it; it ends within 10 s whatever happens, without running the program's end a second
time. A run that is killed, or that ends while work still runs on other cores, leaves no entry, and neither does a run
on Windows, which has no `fork`: the next run reads its packages as without a cache. A program that runs for a long
time, as a server, writes its entries when it stops. Each entry is written to a new file beside it, which no other file
can be (Cesia makes it with `O_EXCL`), then renamed in place of the old one, which is removed first: btrfs writes a file
renamed over another to the disk at once, about 8 ms. A run that reads an entry while another writes it sees the old
one, the new one or none, never a half, and two runs that write it at once both write a whole one. At the first write of
a run, past 256 MB of entries, those used least lately go, down to 128 MB; reading an entry keeps its date fresh, once a
day. The folder can be deleted at any time, as any cache.

**What it saves.** From the start of the process to its end, the median of 21 runs of each and its 95 % interval, the
three taking turns, on 2026-11-12 while other work ran on the machine: before the cache; the first run, with an empty
cache, whose entries are written once it has ended; and the next runs, which read them. Cemacs is its start to its
first frame, as its book measures it.

| Program | Before | First run | Next runs |
|---|---:|---:|---:|
| `use std/io` and `io.Print(1)`, no package of Cesia code | 4.50 ms [3.37, 5.17] | 3.99 ms [3.00, 4.55] | 3.75 ms [3.05, 4.26] |
| `use std/plot`, 2,300 lines | 9.66 ms [9.58, 9.85] | 9.61 ms [9.45, 9.88] | 5.69 ms [5.58, 5.75] |
| `use std/cells`, 1,250 lines | 6.79 ms [6.75, 6.91] | 6.86 ms [6.78, 7.19] | 4.36 ms [4.29, 4.57] |
| Ceti's `src/browser`, 1,500 lines | 7.14 ms [7.00, 7.46] | 7.22 ms [7.14, 7.91] | 4.70 ms [4.61, 4.95] |
| Cemacs, 8,300 lines in 28 packages | 52.16 ms [51.52, 53.09] | 54.26 ms [52.47, 57.66] | 36.97 ms [35.88, 38.63] |
| Cemacs with its notebook, 10,000 lines in 32 packages | 61.27 ms [59.22, 66.12] | 62.88 ms [60.62, 73.07] | 39.62 ms [38.74, 42.10] |

The first run takes the time it took before the cache, within what the runs spread, but for about 2 ms in Cemacs: about
1 ms is the `fork` of a larger process, the rest the questions noted while it resolves. Reading an entry back is two to
three times faster than lexing and parsing its source, and the resolver doesn't run at all; what is left of a load is
mostly that reading, and the young collections that copy the new trees to the major heap, as for trees just parsed.

**Tested** by `tests/cache_test.ml`, which damages each entry at 60 places, cuts it at 8 lengths, grows it, swaps it
with another and reads it with another build, each time with the same output and the entry written again as it was, and
changes a file and a dependency; by `tests/cache/entries.cmd`, the same with the binary, and with a link, an entry that
others may read, a folder that others may read and one that can't be written, and four runs at once; and by the golden
tests, run once with no cache, once with an empty one and once with it full.

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
