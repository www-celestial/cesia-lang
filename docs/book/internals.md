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

![The path of total = price * (1 + tax) through Cesia: per file, when the program first needs it, the lexer makes its tokens, the parser its syntax tree and the resolver ties each name to its place; per function, at its first call, inference gives types and the compiler OCaml closures; when it gets hot, the JIT writes it for MIR, which makes machine code; a failed guard goes back to the interpreter.](images/internals-path.svg)

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
value yet.`, not a surprise at run time. This costs the same for each statement whatever the number of variables: a
branch, as each side of an `if`, notes the variables it assigns, and takes them back once it is done, and where two
branches meet, only what they assigned is compared. Copying the set of all the variables at each branch instead made a
function of 4,000 variables, or a script of as many, take 120 to 190 ms to resolve, against 6 to 7 ms now.

The resolver marks the calls in *tail position*, a call whose result is the function's own result with nothing left to do
after it: a function that calls itself there runs as a loop, so its depth doesn't grow.

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
Named arguments and defaults left out loop too: the frame makes the defaults again at each turn. The loop is in the
version of the function its first call entered: a call that leaves out a parameter that call gave, or gives one it left
out, can enter one frame more, the version for those arguments, and loops there.

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

A version is inferred at its first call, or before, when a caller needs the type of what it gives back. The resolver
notes, for each function, whether a value it gives back can be a number, as its code shows: a literal, a variable,
arithmetic, an index or a call can; a text, a list, a dictionary, a struct, a result, a Bool or a comparison can't, and
the call of a function that gives no number gives none either. The call of a function that gives no number is
"anything" to its caller, which is what inferring it would find, so the caller doesn't infer it: it is inferred when it
runs, or when a function that calls it is compiled, which needs the slots of its parameters. Before 2026-11-19 a caller
inferred every function its code calls, whether the call runs or not, and every function those call: a first
[plot.Svg] of a line inferred 140 versions of [std/plot] and read their bodies from the
[cache](#the-cache-of-loaded-packages), its 3D graphs and its animations among them, for the 65 it compiles and runs;
now 110, which cost 0.8 ms instead of 1.1, and 99 bodies instead of 120. The types are the same, so the code that runs
is the same.

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
are bounded by what is left before the limit. Each step carries its *site*, the place in the code that it names: a turn
of a loop names the loop, a native its call, and the first step of a frame its function, at the line that defines it, as
Python names the frame being entered; the trace then names the call that made the frame. The `steps` and `depth` limits
name the site of the step that went past them, and machine code names the same as the interpreter: it writes no site as
it runs, and the JIT finds that of the step from the place where the code stopped, only then.

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

![A map m of 100,000 keys, then dict.Put of the key City: the new map copies the three nodes on the path of the key, the root, the node at place 17 and the node at place 4, which gets City inline, and shares the rest with m, as the node at place 12; m is unchanged.](images/maps-trie-put.svg)

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

- A version of a function, whatever it gives, after 1,000 calls; one that gives a value other than a number, while no
  hot loop or version of numbers has loaded the JIT yet, after 16,000 (below, *Versions that give values*); when
  its calls from the interpreter make fewer steps than coming into machine code and going back costs, as one with a loop
  of two turns does, they go back to the interpreter, which keeps its machine code and tries it again now and then, and
  its calls inside it, as a recursion's, stay machine code. The top of a file, a cell or code typed at a prompt is never
  one: once it ran, its variables are copied from its frame to their cells, where other files, the functions defined
  later and the variables of a session read them, and machine code of the whole of it would keep them in registers,
  written to the frame only at a checkpoint: under `CESIA_JIT=always`, which made it so at its first run, the cells got
  the numbers of the last checkpoint. Its loops get machine code of their own, which writes them back when they end.
- A loop, at the second checkpoint met inside it: after 10,000 to 20,000 turns of a loop that runs alone. A loop that runs
  often but briefly, as in a function called for each request, gets hot once its runs add up to 100,000 steps; one whose
  runs make fewer steps than coming into machine code and going back costs, about a dozen, stays in the interpreter
  while they do, and a loop around it can still take it into its machine code.

`CESIA_JIT=always` compiles every candidate at its first call or run, and makes its level 2 (below, *What it costs to
make*) as soon as that first run ends, which the tests use to compare the interpreter and both levels on the whole
suite. `CESIA_JIT_SHOW=1` prints each unit compiled, or why the JIT didn't load.

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

**A variable of a module in a register.** A variable of a file that one of its functions reads lives in the file's
module, where the function finds it, and so does a name that code typed at a prompt gave a value, which code typed there
later gives a new one in place. The interpreter writes the module at each assignment, and a loop that assigned such a
variable stayed in the interpreter: `n = n + 1` over 10^6 turns at the top of a file took 21.7 ms, against 8.9 with `n`
read by no function, and the same loop typed a second time at a prompt 26.8 ms, against 3.6 the first time. Now a loop
of a file's top keeps each variable of a module that it assigns, the variable of its `for` too when it is one, in a
register of the kind the variable holds when the loop compiles, an integer or a float. Before each run the engine reads
the variable into the register's slot, and after each run that wrote its variables back it writes it to its module: at
the end of the loop; at each checkpoint, where another fiber, a stop or the variables of a session may look at it; at a
guard that failed and at a statement left to the interpreter, which go on from there; and at an error, so that the
variable holds what the interpreter would have left. This is *register promotion*, as Lu and Cooper (1997) made it for
the scalars of C, a load before the loop and a store after it, for a variable that nothing else in the loop can reach,
and as Lo, Chow and others (1998) place those loads and stores where they are needed, and only there. Here what can
reach the variable is a function the loop calls: one inlined reads the register, and one called, which would read the
module, leaves the loop to the interpreter, as an assignment of another kind does, a Float given to an Int.

Measured on 2026-11-24, `release` profile, 21 runs of each alternated with main's binary, from the start of the process
to its end, or the run's own time for code typed at a prompt; the medians and their 95% intervals, in ms:

| Loop | Before | Now |
|---|---:|---:|
| `n = n + 1`, 10^6 turns at the top of a file, `n` read by a function | 21.7 (21.3–25.8) | 8.4 (8.1–8.8) |
| the same, `n` read by no function | 8.9 (8.1–9.5) | 8.6 (8.3–9.5) |
| the same over 10^7 turns, `n` read by a function | 161.9 (158.5–168.4) | 17.3 (16.7–18.3) |
| the loop of 10^6 turns typed a second time at a prompt | 26.8 (26.4–27.3) | 2.96 (2.89–3.05) |
| a branch left to the interpreter every 4 turns, 10^6 turns | 47.7 (47.2–48.9) | 47.8 (47.2–48.7) |
| a call that isn't inlined reads `n`, 3 × 10^5 turns | 83.1 (80.8–84.3) | 82.2 (80.8–83.0) |

Where it gains nothing, it loses nothing either: a loop whose statement left to the interpreter runs every few turns
goes back to the interpreter for good, as below, and one whose call reads the variable stays there, both as fast as
before. Beside the giants, the same loop over a global variable, the whole process: 10^6 turns take 7.8 ms, Python 3.14
114, Node 26 43.6, Lua 5.5 23.1 and LuaJIT 3.2; 10^7 turns 16.9, Python 982, Node 49.3, Lua 206 and LuaJIT 11.4.
LuaJIT wins: it starts in about a millisecond, where Cesia loads its JIT at the first hot loop, and a turn then costs
each about a nanosecond. The tests run these loops with the JIT off, hot and always, and compare: another fiber that
reads the variables at each checkpoint, a stop in the middle of the loop, an error and an overflow, a guard that fails
in a loop of the loop, the variable of a `for`, a slider set, and a function inlined that reads them; the fuzzer makes
such loops at random.

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

**Checks before the loop.** An index that moves with the loop's counter, as `x[j]` or `colptr[j + 1]` in
`for j in 1..n`, is inside its array at every turn when it is inside at the first and the last turn. So the JIT makes two
copies of a loop: a *fast copy*, with no check of such an index, and the checked copy it had. Before the loop, a few
tests decide which one runs. In the sparse product above, they are made once, before `for j in 1..n`: `j` starts at 1,
at least 1, and `n` and `n + 1`, the last turn's `j` and `j + 1`, are at most the sizes of `x` and of `colptr`. When
they hold, the fast copy runs, with no check of `x[j]`, `colptr[j]` and `colptr[j + 1]`; when one fails, the checked
copy runs, which gives the interpreter's error at the index outside, at its line.

This is *loop versioning*, which Midkiff, Moreira and Snir (1998) made for the array checks of Java. The inner loop is
the innermost one: its fast copy also checks, before it starts, that the fuel covers all its steps, so it never tests
the fuel at a turn, and `rowidx[q]` and `vals[q]` need no check either. Only `y[i]` is checked at each turn, as `i` comes from
the list. An index `j + k` is read at the counter's own register, `k` cells further, so the fast copy keeps no register
of its own for it, for a `k` near 0. The loop around keeps its steps counted at each turn, as its inner loops' steps
aren't known before it starts. When the run leaves inside it, at a full checkpoint or for the collector, it comes back
into the checked copy, which made every check, and the next turn of the loop around goes through the tests again: so a
run never comes back into the middle of a fast copy, whose tests it would not have made. The inner loop of the fast copy
is made once more, its fast copy only: when its own tests fail, the run goes on in the checked copy's.

A copy of a loop costs MIR time to compile, so it is made only where it pays: for an innermost loop, and for a loop
whose loops inside are innermost `for` loops that allocate nothing. A sparse product's unit then has 499 lines of MIR
instead of 453, and gets its level 2 one call later. Measured on 2026-11-13, `release` profile, 21 runs alternated with
main's binary, each run 14 products of the 2-D Poisson matrix of 300 × 300 points (448,800 non-zeros), the medians and
their 95% intervals, in ns a non-zero:

| Product | Before | Now |
|---|---:|---:|
| the first, at level 1, compiling included | 5.01 (4.92–5.31) | 5.05 (4.82–5.37) |
| the first five, added | 26.5 (23.4–28.3) | 27.3 (23.6–27.8) |
| each one at level 2, from the 8th | 3.75 (3.73–3.78) | 2.79 (2.75–2.85) |

A product then takes 1.25 ms. A histogram of 10^6 keys from a list of integers, already an innermost loop, takes 2.28 ns
a key instead of 2.31, and a permutation of 10^6 floats, `y[k] = x[p[k]]`, 11.7 ns an element either way: it waits on
memory, a cell 63 KB from the one before.

What keeps it safe: a fast copy reads or writes without a check only a cell that the tests before it proved inside its
array at every turn, the first and the last turn computed with their overflow checked; an array keeps its size while a
run lasts, its size and store checked at each entry. A row read from the list is checked at each turn, so a wrong one is
the interpreter's error, never a write outside `y`. A `k` of 2^20 cells or more gets a register or its check, so that
the bytes `k` adds to an address are exact. The tests run each such loop with the JIT off, hot and always, with an index
outside, a float in the list, the list written while the loops run, and the overflow of `colptr[j + 1] - 1` and of
`j + k`, and the fuzzer makes sparse products whose last call breaks a list in one of those ways.

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
rarely, as the error paths and the end of a loop do. The loop is then made again with those that assign a variable, and
the statements after them in their branch, out of what the JIT looks at, so that a variable they alone assign, as a
buffer made anew when it is full, is still an array of the loop. One that assigns none, as `buf[used + 1] = t` after
that branch, is tried again then, as what kept it out may have been only that the buffer was not yet an array of the
loop. A call of a small function whose body gives a text in one place and a number in another is made the same way:
inlined, its number path in machine code, and its text path a way back to the interpreter, which makes the call again.

A cold statement that runs at nearly every turn costs more than it saves: each turn leaves machine code and comes back,
about 450 ns, what native code gains on 8 to 20 steps of a loop of floats. So once a loop has gone back for cold
statements 64 times, and its machine code made fewer than 12 steps for each of them on average, its code goes and the
loop is the interpreter's for good, never slower than the interpreter. Measured on 2026-11-14 on a loop of 10^6 turns whose branch
left to the interpreter runs every e turns, the best of 5, in ms:

| e | Before | Now | Interpreter only |
|---:|---:|---:|---:|
| 1 | 1,011 | 75 | 75 |
| 4 | 136 | 31 | 31 |
| 8 | 60 | 25 | 25 |
| 16 | 28 | 28 | 21 |
| 64 | 8.2 | 8.1 | 17 |

`stats.MonteCarlo` first gathered its single draws with `x = f()` under `if k > 1`, which native code couldn't call:
10^6 draws took 539 ms (the median of 21 runs), against about 120 interpreted. That loop now runs as machine code from end to end, `f`
and its draw included (below): 8.9 ms.

**Tests and kinds.** `(fa > 0.0) == (fb > 0.0)` compares two tests; `value.IsNumber(x)`, `value.IsText(x)` and the other
tests of kind look at the tag of the value's block, or need no test at all when the JIT knows the kind; and a small
function that is one test, as `isFinite(x) = value.IsNumber(x) and x - x == 0.0`, is made in place, a test like any
other.

**Draws.** `random.Float()` is made in place, as `math.Sqrt(x)` is: the step of SplitMix64 (Steele, Lea and Flood,
2014), the same instructions as the interpreter's, on the same state, so the same floats come in the same order whoever
draws them. The state is 64 bits, held as the bits of the one cell of an array of floats that the interpreter and machine
code both read and write. A draw changes something the program sees, as a write into an array does: no guard after it
may send its statement back to the interpreter, which would draw again, and only the unit's own code and the bodies it
inlines draw, so that no call of another compiled function hides one. The one memory a draw writes is that cell's 8
bytes, in an array std/random keeps to itself and never gives to a program. A loop of 10^6 calls of `f()`, where
`f = () -> random.Float()`, takes 7.3 ms instead of 65 (the medians of 21 runs, 2026-11-14).

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
`matmul` then runs half again as long: so the JIT uses both, one after the other (below), and gives MIR fewer
lines:

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

**Two levels.** MIR makes code at levels: level 2, the one above, and level 1, which skips the passes in SSA form and
takes 30 to 60 % less time, the more the bigger the unit, for code that runs up to half again as long, as `matmul`'s.
Each suits a run: a short run should pay only the faster compile, a long one should run the faster code. So a unit's
machine code is first made at level 1, and its level 2 comes later, from another core:

- **Level 1 first.** Every unit is made at level 1, on the main domain, as before. The unit of `ode.Solve` with Lorenz's
  equations, 3,612 lines of MIR, takes 18 ms at level 1 instead of 42 at level 2 (MIR alone).
- **Hot at level 1.** Each run of the unit adds the steps it took, which the run counts anyway for its checkpoints. Once
  they reach 1,000 steps for each line of the unit's text, it gets its level 2. A step of machine code takes 3.8 to 5.3
  ns on Lorenz's step and the sparse product, and MIR takes 5 to 6.5 µs a line at level 1: 1,000 to 1,700 steps a
  line, so a unit gets its level 2 once it ran about as long as its level 1 took to make. The size of the unit is in the
  threshold, as V8 asks a function for more ticks of its budget before TurboFan the bigger its bytecode: bigger code
  costs more to make, so it must run longer first. Thresholds of 2,000 and 4,000 steps a line were slower or even on
  every program below.
- **In another domain.** An OCaml domain makes level 2 from the same text, in a context of MIR of its own, without the
  domain lock, so the main domain and its collections go on. One level 2 is made at a time; a unit hot meanwhile asks
  again at its next run.
- **Taken at a safe point.** Before each run of any unit's machine code, the main domain looks whether a level 2 is
  made, and puts it in its unit. There no machine code runs anywhere: it never calls back into OCaml, and a program runs
  on one domain. Both levels come from the same text, so the frame, which is the interpreter's, and every point where a
  run starts again, after a quantum of steps, a collection or a bail, mean the same in both: the swap is one address
  written, and a fiber stopped between two quanta of level 1 goes on in level 2. HotSpot and V8 install new code at a
  method's next call, and replace a running frame by *on-stack replacement* at a loop's back-edge, which translates the
  frame from one compiler's layout to the other's; here nothing needs translating.
- **Freed.** Each unit has its own context of MIR, so its code can go alone: level 1's at the swap, and a unit's once
  nothing holds it, by a finaliser of the collector, as when its loop is made again for new values. A context costs
  about 0.13 ms to make and 120 KB, which a program of a hundred small units, each hot just before its end, pays: 147
  ms instead of 139, and 39 MB instead of 27 (`units.ce` below).
- **Safe.** The other domain reads only the unit's text, which only Cesia's own generator writes, and two atomic cells;
  it never touches the unit, which the main domain holds until it takes its level 2, so no unit dies while its level 2
  is made. MIR's state is a context's own: the two tables that its contexts share are written by the first one only,
  before any other domain starts. Code pages are never writable and executable at once, and a unit's level 2 is
  written in pages of its own while its level 1 runs. The tests make code on two domains at once, free contexts while
  the other domain's code runs, swap levels under four fibers that take turns in one unit, and check that units that
  die leave no context behind.
- **`CESIA_JIT=always`** makes level 2 at the end of a unit's first run and waits for it, so the tests and the fuzzer
  run the interpreter, level 1 and level 2, at the same points in every run.

Measured on 2026-11-13, `release` profile, on the machine of *What it gains*, below: each program 11 times, alternated
with the binary before, which made level 2 only, from the start of the process to its end; the shortest run, then the
median, in ms:

| Program | Before | Two levels |
|---|---:|---:|
| Lorenz on [0, 100] and [0, 50] | 83.0, 85.7 | 66.2, 67.8 |
| Lorenz on [0, 2,000] | 255.1, 263.3 | 252.6, 261.5 |
| `structs` | 51.3, 56.1 | 40.0, 41.2 |
| `real/particles` | 53.8, 53.8 | 48.3, 48.7 |
| `optimize.Root`, 22,000 roots | 71.2, 72.4 | 67.8, 68.5 |
| `matmul` | 44.6, 46.2 | 44.4, 45.0 |
| `dyn` | 59.5, 61.0 | 60.1, 61.4 |
| `units.ce`, 100 small units | 138.8, 139.8 | 146.8, 148.2 |
| `io.Print(1)`, the start | 2.5, 2.7 | 2.5, 2.8 |

`fib`, `mandel`, `nd`, `nd-2d` and the sparse product are within 3 % at their shortest, and so are `real/csv` and
`real/json`, which spend their time outside machine code. Short runs gain what level 1 saves of the compile; long ones
keep level 2's speed, and gain its compile too, made on another core. `dyn` loses a millisecond: its loop runs its level
1 until its level 2 comes.

Where the giants do more: HotSpot has five levels, the interpreter, C1 with and without profiles, and C2, which compiles
with what the profiles saw; V8 has four, Ignition, Sparkplug, Maglev and TurboFan. Their top levels speculate on the
types and the branches that the levels below saw, and can be several times faster than those; Cesia's two levels are
the same text, made better, at most half again apart, as its speculation is in the text already, from the
interpreter's frame. They compile on several threads, from queues of methods, and flush the code of methods gone cold;
Cesia makes one level 2 at a time, and keeps a unit's code as long as the unit lives. The Jalapeño virtual machine of
Arnold and others (2000) recompiles a method when the time it is expected to save beats the time to compile it,
expecting a method to run as long again as it ran. Cesia's rule is simpler, as level 2 is made on another core: a unit
only has to have run as long as its level 1 took to make, which keeps the units that stop soon from taking the one level
2 being made.

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

The test is on the function's *code*, not on the function: each function has the identity of its code, its own. When
the prompt or a cell of a session defines a function again with the same code, the new one takes the identity of the old
one's, and the machine code of a loop that called the old one through a value runs the new one at once, made again
neither by the JIT nor by MIR. The same code means: the same name, the same text on the same lines of the same file, so
that an error prints the same; the same tree, each name bound to the same variable or function; and nothing whose
meaning depends on the module that defines it, which is another at each run of a cell: no named struct, no private
field, method or key read by name, and the same packages used with no interface declared in the cell, since a method
found through an interface is looked up from there. A function that calls another of its own cell, or itself, reads a
name of that new module: it is made again, as the first time; so are the loops of the function itself, which belong to
the function and not to its code. The solve cell of a Lorenz notebook, `lorenz` defined again and `ode.Solve` on
[0, 50], takes 2.2 ms instead of 53 to 64 ms, the time to make ode's loop again with one more function at its call of
`f`, and of 22.7 ms for good once that call had met five (medians of 21 runs, 2026-11-18). A function defined again in
the same place, the same or changed, takes the old one's place among the four a call remembers.

A loop whose machine code is dropped, as when a variable it took as a constant holds another number, makes it again, and
after eight drops stays the interpreter's for good, so that code that keeps failing isn't made over and over. Two drops
don't count: that of code whose runs took as many steps as making it cost, which paid for itself; and that of code which
took a variable of a cell that the session ran again, which the session forgot and which can never hold a number again,
as an edit of the parameter cell of that notebook makes. Each such edit makes ode's loop again, 43 ms instead of 22.7
interpreted, and the runs after it take 2.2 ms again.

A number given to a variable of a module *in place*, as [cells.Set] gives a slider's, keeps the variable where it is.
Machine code reads such a variable from a slot: before each run the engine writes the variable's value there, checked of
the kind the code takes, an Int or a Float, and the code loads it into a register when it starts, wherever the unit
reads it, in the loop, in a function inlined in it or in a function it calls. It does so for the variables of the
modules a session runs, the only ones a session can set in place, from their first code on; and for any other variable
once it moved under machine code, as one that the top code of a file gives again: the code that took its number as a
constant is dropped once, as above, and the variable is marked. Each new number of that kind then runs the same code: a
step of the slider of `rho` in the Lorenz notebook, `rho` set and `ode.Solve` on [0, 50] run again, takes 2.6 ms instead
of 24, where each step made ode's loop again, 40 to 70 ms, until the loop stayed interpreted for good (medians of 21
steps, 2026-11-18). A variable of another module stays a constant of the code until it moves, as the 38 coefficients of
ode's step: nothing is read at each run that doesn't need to be. A number of the other kind, an Int where the code took a
Float, drops the code, as a changed constant does. The marks hold at most 4,096 variables, then start again, which costs
one code made again. A fuzzer of sessions, `tests/jit/slider-fuzz.ce`, moves sliders at random among edits of cells and
checks that each answer is the interpreter's.

None of this runs code with a wrong value: the identity of a code is a number the session gives, never a hash that two
codes could share; the session compares the two whole trees before it gives the old one's; the numbers a code took are
checked before each of its runs, as for any code; and the session keeps the last function of at most 1,024 names, so
that a session defining functions for hours holds no more. A fuzzer of sessions, `tests/jit/twins-fuzz.ce`, defines
functions again at random, the same or changed, and checks that each answer is the interpreter's.

A call with no argument, as `f()` in the single draws of `stats.MonteCarlo`, is made the same way: the interpreter notes
the functions it reaches, as it does for one to three arguments, and a function of no parameter infers its variables
and its result, as one called with typed arguments does, so that `() -> 0.25` is known to give a float. Such a call took
37 ns, always in the interpreter; it takes 2.2 ns, as `f(k)` does, and 4.1 ns when `f` draws, `() -> random.Float()`
(the medians of 21 runs, 2026-11-14).

```text
f(total, x)                      in machine code
├── f is (a, b) -> a + b ?       total + x, unboxed, inline
├── f is (a, b) -> a * 0.5 + b ? total * 0.5 + x, inline
└── else                         back to the interpreter, before the statement
```

### Calls with defaults and named arguments

A parameter can have a default, as `defn f(x, step = 1)`, and a call can leave it out, `f(i)`, give it, `f(i, 2)`, or
name it, `f(i, step = 2)`, the names in any order. The interpreter binds such a call once, when it compiles it: each
argument goes to its parameter, by its place or by its name, and the arguments are made in the order of the
parameters, whatever the order they are written in, so that the first error is always the same one. A parameter left
out has the type *none yet* in the version's types: the version is the one for those types, and it makes the default
in its own frame, after the step of the call, as a Python frame makes its defaults when it starts.

Machine code left every call of a function that has a default, and every call that names an argument, to the
interpreter, and the loop around such a call stayed interpreted: 10^7 calls of `f(i)` took 321.6 ms, against 27.3 for a
function without a default. It now binds the call as the interpreter does and calls the same version. Inlined,
the callee's body made in place, the default is made after the step of its frame, into the parameter's register.
Called, the caller passes any number in that register, and the callee's own entry makes the default after its step, as
it already did for a call from the interpreter. A leaf test that reads a default, as `if n < lim` with `lim = 3`, is
made at the call when the default is a literal, which then costs nothing before the step (the partial inlining of
[What it makes](#what-it-makes)). A self tail call into another version, as `count(n - 1, acc + 1)` in the frame that
`count(50)` made with `acc = 0`, is a call, in a frame of its own, as the interpreter's, where it ended the machine code
of the whole function: the interpreter then ran the outer frame of each `count(50)`.

Measured on 2026-11-25, `release` profile, 21 runs of each alternated with main's binary, from the start of the process
to its end; the medians and their 95% intervals, in ms:

| Call in a loop, 10^7 times | Before | Now |
|---|---:|---:|
| `f(i)`, `step` left to its default | 321.6 (320.6–324.3) | 27.0 (27.0–27.3) |
| `f(i, 2)` | 284.4 (283.3–285.6) | 27.3 (26.9–27.7) |
| `f(i, step = 2)` | 283.0 (282.0–285.3) | 27.1 (27.0–27.3) |
| `f(i, 1)`, a function with no default | 27.3 (27.1–27.8) | 27.4 (27.1–28.8) |
| `count(50)` 20,000 times, a self tail call into the version that gives `acc` | 16.4 (16.2–16.6) | 10.5 (10.5–10.7) |

V8 made a call with fewer arguments than parameters through an *arguments adaptor frame*, a frame put between the two
that filled the missing ones with `undefined`, until 2021, when it removed that frame and gained up to 40% on such
calls (Gomes, 2021). Beside the giants, 10^7 calls of `f(i)`,
`step` left out, take 26.7 ms, against Python 3.14 1,017, Node 26 59.2, Lua 5.5 280, where `step = step or 1` stands for
the default, and LuaJIT 2.1 11.4; given, 26.9, against 980, 59.8, 272 and 11.4; named, `f(i, step = 2)`, 27.1, against
Python 1,142, Node 63.6 with an object for the names, Lua 1,675 with a table, and LuaJIT 11.4 (the whole process,
medians of 21 runs alternated). LuaJIT wins: it starts in about a millisecond and makes the loop machine code at once,
where Cesia starts in 4 and loads its JIT at the first hot loop; a turn then costs Cesia 1.7 ns and LuaJIT 1.

What stays interpreted: a default that isn't a number, as a text or a list; a call through a value of a function that
has defaults; a self tail call that leaves an argument out; and a recursion whose two versions call each other, as
`fib(n, lim = 2)` calling `fib(n - 2, lim)`, the version for `lim` left out calling the one for `lim` given, which calls
the first: inference doesn't follow a cycle between versions, so it types them as anything, and they run in the
interpreter, which then boxes every integer.

### Calls of natives

A native, a function of `std/` written in OCaml, as `math.Abs` or `text.ByteLength`, is machine code already. Until
2026-11-26 machine code never called it, so that nothing collected during a run, and a loop with a statement that called
one stayed in the interpreter; machine code now calls it through OCaml when that pays
([Machine code that calls OCaml](#machine-code-that-calls-ocaml)). The JIT makes some of them itself, inline: those of libm, as
`math.Sqrt`, `math.Log10` to `math.Atanh` and `math.Hypot`, the angles in degrees, `math.SinDegrees`,
`math.CosDegrees` and `math.TanDegrees`, reduced by libm's `fmod` and `round` as the interpreter reduces them, and
`math.Abs`, `math.Div`, `math.Mod`, `list.Max` and `list.Min` of two numbers, `value.Len` of an array, `random.Float`, and a few on
small arrays of floats. `math.Cbrt` is Cesia's own, correctly rounded, and no function of libm: a loop that calls it
stays in the interpreter, and an array takes it in one call.
The interpreter's call of the others took 28 to 36 ns. A sampling profiler, `gdb` stopping the process every 10 ms and
reading its stack, 300 times, on 3 × 10^8 calls of `math.Abs(i)`, said where:

```text
math.Abs(i) in a loop, 31 ns a turn, interpreted    share of the samples
├── the turn of the loop, its sum and its store     26 %
├── the result looked for among the arguments       15 %   Array.memq
├── the argument boxed, an Int made of i            13 %
├── math.Abs itself, its Int made                   11 %
├── the wrapper of the native                       10 %
├── the call's closure, its site written             8 %
├── calls of closures of unknown arity               8 %   caml_apply2
└── the result unboxed                               6 %
```

The look for the result among the arguments is for a native that gives back one of them, as `dict.GetOr` gives back the
default it was given: the call doesn't share its arguments, so that measuring a variable leaves it owned, and a result
found among them must be shared before it has a second name, or a write through one would change the other
([copy-on-write](#value-semantics-and-copy-on-write)). Only an owned list, struct or map has anything to share: a
number, a text or a value already shared now skips the look, a test of the result's tag. A native of no argument, as
`sys.Now`, no more makes its empty array through a map of the arguments. And machine code makes `math.Abs` of an integer
itself, a negative one negated with its overflow checked, so that the smallest integer is the interpreter's error at the
call; a loop that took it stayed interpreted.

An error of the system that a native lets out, a `Sys_error` of OCaml or an error of Unix, instead of giving an `Err`,
ended the program with a line that named no place, or with an internal error, and stopped every fiber. It is now a panic
of the kind io at the native's call, which stops its fiber alone, as any panic: a safety net, since every native of
`std/` tried gives an `Err` already, the current folder removed included. Installing an OCaml handler of exceptions
pushes two words on the stack, the handler's address and the previous handler, and removing it pops them
(Sivaramakrishnan and others, 2021); a handler in the wrapper of every native also kept the context and the native
across the call, nine instructions more: with it, 10^7 calls of `text.ByteLength` took 274.7 ms instead of 269.8, and of
`sys.Now` 437.0 instead of 422.9, 0.5 and 1.4 ns a call, and the difference on `text.Slice` was inside the noise of its
allocations. So no handler is installed at a call: the error goes up, as a panic does, to what catches panics already,
the run of the program, of each fiber and of each test, which makes it the panic it is, at the site the native's call
wrote before it ran. It costs nothing until something is raised.

Measured on 2026-11-25, `release` profile, 21 runs of each alternated with main's binary, the whole process; the medians
and their 95% intervals, in ms:

| Loop of 10^7 calls | Before | Now |
|---|---:|---:|
| `math.Abs(i)`, now machine code | 302.1 (300.2–305.4) | 20.2 (20.1–20.6) |
| `text.ByteLength(s)` | 322.7 (319.5–324.4) | 269.8 (267.8–273.4) |
| `sys.Now()` | 517.6 (515.7–520.5) | 422.9 (420.9–424.2) |
| `text.ByteLength(text.Slice(2, 4, s))`, two calls | 1,250.4 (1,247.5–1,262.8) | 1,098.5 (1,097.0–1,106.9) |

CPython 3.11 calls a builtin function written in C, as `len()`, straight from the instruction of the call, which its
adaptive interpreter specializes for it once it has seen it there, without the general convention of a call: up to 20%
faster (PEP 659, and the notes of Python 3.11). Beside them, 10^7 calls of the absolute value of an integer take 19.8 ms
in Cesia, now machine code, against Python 730, Node 83.3, Lua 192 and LuaJIT 11.4; of the length of a text, 268,
against Python 641, Node 50.6, where the length is a property and no call, Lua 239 and LuaJIT 11.4; of `math.Sqrt`,
which Cesia's machine code makes, 49.2, against 763, 53.2, 205 and 11.4. Lua's interpreter calls `string.len` in 24 ns a
turn, against Cesia's 27: its call passes the arguments on its stack, where Cesia's makes an array and boxes them, as a
native takes them. Node and LuaJIT make such calls machine code; Cesia does so inline only for the natives its JIT
knows, and calls the others through OCaml ([Machine code that calls OCaml](#machine-code-that-calls-ocaml)).

### Versions that give values

Until 2026-11-25, a version was machine code as a whole only when inference proved its result to be a number. A test
that loops and gives a Bool, as `isPrime(k)`, a search that gives an index or `missing`, a recursion that makes maps,
stayed interpreted, and so did a loop that called one, as machine code calls only machine code: around `if isPrime(k)`,
`for k in 1..300000` ran in the interpreter, and each call of `isPrime` entered machine code for its `while` and left
it. Now a version is a candidate whatever it gives:

- Its variables of no type are values in registers, as its parameters and its result. A value is marked shared where the
  interpreter marks it ([copy-on-write](#value-semantics-and-copy-on-write)): when a variable takes one that another
  variable, a field or a cell holds, when a `return` gives one, and when a call passes one to a parameter that the
  callee keeps, as one it gives back. Machine code lacked that last mark, for the calls it inlined too: after `q =
  same(p)`, with `same(p) = p`, `q.X = 5.0` changed `p` as well, in machine code only, a bug of the JIT that
  `tests/jit/value-results.ce` now checks in the three modes.
- A value as a condition is tested as `true` or `false`; anything else is the interpreter's error at the condition, with
  its message: native code puts the value in a slot of the frame and gives the error's code, and the interpreter's own
  test makes the message. A value compared with `missing`, `true` or `false` is a comparison of two words.
- A loop's call of such a version is a call from native code to native code once that version lowers, with the versions
  it calls. A *dry lowering*, made and thrown away, decides it before the call commits its unit to it, so that a call
  that machine code can't make, in a branch the loop rarely takes, stays a statement left to the interpreter. A version
  whose body calls a native the JIT doesn't make, or holds a text made of parts, a `match`, a `?`, an `in`, a
  comprehension or a function literal, is refused at once, before the versions it calls are lowered for nothing.

The hard part is memory. Native code calls OCaml only as the next part says, so nothing else collects while it runs:
each turn of a loop
*reserves* the words it will make, and when the young heap lacks them, the run leaves, the interpreter's allocation
collects, and the run comes back. A nested frame, the frame of a call that native code makes, can't leave, as its
caller's registers would be lost. So a nested frame short of room *stops*: a loop's call then goes back to the
interpreter, which makes that statement, and the loop goes on in machine code at its next turn; a version as a whole,
called by the interpreter, runs once more after a collection, and when it is short again, the interpreter makes the call
from its start, with the same steps, as nothing of it showed. A version short of room twice makes more than the young
heap holds between two collections: its calls are the interpreter's after that. To make stops rare, a loop whose calls
make values checks, at each turn, room for an eighth of the young heap besides its own words, 262,144 words once the
heap has grown, so that a collection comes at the top of a turn, where the run can leave, rather than deep in a
recursion. And what native code makes after a call checks its room again, right after that call, whose nested frames may
have taken what the turn checked: the fuzzer found that case, a tree of maps made by a recursion past the young heap,
which wrote below it.

Loading the JIT costs about a millisecond. A short program that calls a helper of texts 1,500 times, which no JIT
compiles, took 4.0 ms, and 5.0 once such versions got native at 1,000 calls; a version that gives a value now waits
16,000 calls while nothing has loaded the JIT, and the program takes 4.43 ms, against 4.39 with main's binary (medians
of 21 runs). And the way into native code from the interpreter cost about 250 ns, most of it the engine's own work
before and after a run, over arrays that a version as a whole leaves empty; such a unit now skips it, and the way in
costs about 85 ns (10^6 calls of a small version that calls another, from a loop the interpreter keeps, against the
interpreter alone).

Measured on 2026-11-26, `release` profile, 21 runs of each alternated with main's binary, from the start of the process
to its end, while other work ran on the machine (load 2.6 to 4.0); the median, then the fastest and the slowest run, in
ms:

| Program | Before | Now | Interpreter only |
|---|---:|---:|---:|
| primes below 300,000, `isPrime(k)` a test that loops | 244.6 (233.6–321.5) | 159.0 (152.0–238.3) | 615.6 |
| 20,000 trees of 127 maps made by a recursion, from a loop | 131.7 (124.3–142.5) | 49.9 (42.6–62.8) | 114.8 |
| the same recursion, 100,000 calls from a loop the interpreter keeps | 283.1 (271.7–308.4) | 110.0 (103.2–134.2) | 286.0 |
| a search that gives an integer or `missing`, 200,000 calls | 189.8 (178.7–236.5) | 113.1 (110.6–193.6) | 769.5 |

The programs of `bench/` are the same as before, within the noise: they make no such calls. Beside the giants, the same
programs, the whole process: the primes take 159 ms, against Python 3.14 1,061, Node 26 110, Go 1.26 121, Lua 5.5 337
and LuaJIT 2.1 57; the trees 49.9, against Python 438, Node 80, Go 89, Lua 661 and LuaJIT 198. Node, Go and LuaJIT win
the primes: the loop is a division, `math.Mod(n, d)`, at each turn, which Go and Cesia make on 64 bits, Node on 32 when
its numbers fit, and LuaJIT as floats; Cesia also checks each `d * d` for overflow and counts its steps. The trees are
Cesia's: a map is a few words taken from the young heap by moving a pointer, made whole, so with no write barrier, and a
run collects nothing until it ends.

What still keeps a version out is in [What stays in the interpreter](#what-stays-in-the-interpreter). A server's code is
the case: the request path of Centauri, its door,
its session and its route, calls natives at every step, `dict.GetOr`, `text.Contains`, `sys.Now`, the functions of
`std/http`, builds texts and holds closures, and none of its versions lowers, before or now: a public request takes 19.2
µs, as with main's binary (medians of 21 runs of 20,000 requests each, without the network), and a server of Centauri
answers 13,000 requests of `/hello` a second on one core, beside 28,000 for `std/http` alone and 28,000 a core for Go's
`net/http`. Machine code now calls OCaml for its natives, and its versions still don't lower: the end of the next part
says what keeps each out.

### Machine code that calls OCaml

Until 2026-11-26, machine code never called OCaml: nothing collected while it ran, and a unit that called a native of
`std/` stayed in the interpreter, as did the loop around the call. Now machine code calls a native as the interpreter
does: with its arguments as values, at its site, from its frame. The call goes through the C glue, `cesia_jit_native`
in `src/sys/jit.c`, which runs an OCaml function of the JIT, and that function runs the native.

**Which natives.** Those of `std/` that ask for no permission and never wait. A wait parks a fiber through an effect of
OCaml, and an effect can't cross a call from C to OCaml: it raises `Effect.Unhandled` where it is performed (the OCaml
manual, *Effect handlers*, *Semantics*). So the natives of `std/fiber` but its tables, of `std/websocket`, whose
sockets call back, of `std/cells`, `std/debug` and `std/sqlite3`, `sys.Sleep`, those that ask for a permission (files,
the network, processes, C) and those of the packages, as Cepheus's, which may wait on a server, stay the interpreter's,
and the unit with them: `CESIA_JIT_SHOW=1` names the native. A native that calls back into Cesia, as `value.Len` calls the
`len` of a struct, may still reach a wait: its fiber then waits where it is, running the scheduler as the main program
does, rather than parking.

**How the collector and machine code agree.** Machine code keeps values in registers, and MIR keeps them across a call
in the registers that the call preserves, or in its stack slots, as the convention of C on the platform says (System V
on Linux and macOS, Microsoft's x64 on Windows): the collector looks at none of them. OCaml's rules for C say why that
matters (the OCaml manual, *Interfacing C with OCaml*, *Living in harmony with the garbage collector*): a collection
moves the values of the young heap and writes their new addresses only where it knows them, so a C function declares
every value it holds across an allocation or a call of OCaml, its parameters with `CAMLparam`, its variables with
`CAMLlocal`, an array of them with `CAMLlocalN`. Machine code follows the same rule. Around each call that may collect,
a native, a call of another function of its unit, which may call one, and the slow paths of room and stack below, it
writes the values it needs after the call into a block of local roots on its own stack, laid out as those macros lay
theirs (`caml/memory.h`: the next block, the number of tables, the number of values, the tables), links it into the
list of the domain for the call only, and reads the values back from it after: the collector reads them there, moves
them, and writes where they went. Which values: those that a backward liveness analysis over the blocks of the IR says
are read after the call (Aho, Lam, Sethi and Ullman, *Compilers*, 2nd edition, 9.2.5), every variable, which a way back
to the interpreter writes to its slot, and the first fields of the constants. Each value register holds a value from
the start of its function, the integer 0 before anything else, so that the collector never reads a stray word. MIR's
optimizer reloads nothing from a stale copy: a call clears what it knows of memory, and a block whose address escapes
is never assumed private.

The stacks move too: a new fiber's hold 8 entries and the main program's 256, so they sit in the young heap until they
grow, and a native that calls back may grow them. Machine code reads their addresses again after each such call, and
the C glue hands it the new ones, from the context.

**Errors.** An exception that OCaml code raises skips the C code between it and the OCaml that called it (the manual,
*Callbacks from C to OCaml*): here it would skip machine code's frames, their links never written and their block of
roots left in the list. So the function of the JIT catches every exception, and the C glue tells machine code it
failed: machine code then takes its error path, each frame writing its link for the trace as it returns, and the engine
raises the exception again, from the frame where it was raised. The message, the line and the trace are the
interpreter's (`tests/jit/natives-errors.ce` and `natives-deep.ce`, in the three modes).

**Steps and depth.** Before the call, the interpreter's fuel is set to what it would be after the steps the run made, so
that the native counts its own steps, and those of what it calls back, as the interpreter does: a limit of steps falls
at the same step, with the same site (31 limits across a loop of `text.Repeat`, in the three modes); the run goes on
after from what is left. Each frame's link is written before the call, so that the interpreter's frames called back
above it count the frames of machine code, as the limit of depth must, and a trace taken there holds them. Past 64
natives called from machine code at once, what they call back runs in the interpreter: each level keeps machine code's
frames and the glue's on the system's stack, 8 MB on Linux and 1 MB on Windows, where the interpreter's frames are
OCaml's, on a stack that grows (`natives-deep.ce` recurses 40,000 levels through `value.Len`).

**Never twice.** A native's effect shows, and the interpreter must never make it again: nothing after a native in its
statement may go back to the interpreter, and a call of a function of a unit that calls natives counts as one. A unit
that calls natives so never starts again: where its stacks are short it grows them, and where the young heap lacks room
it collects, both through the same call into OCaml, its values held.

**What it costs.** The way into OCaml and back is the price: `caml_callback`, its change of stack and its handler, and
the work of the engine around the native. It costs about 100 ns more than the interpreter's own call of the same
native, measured on this machine: a loop of 20 operations of floats takes 27 ns a turn in machine code and 137 in the
interpreter, and 200 and 210 with a call of `dict.Has` in each turn. So a unit is machine code only when it makes at
least 24 operations for each of its calls of natives; else the interpreter keeps it, and `CESIA_JIT_SHOW=1` says how
many it counted. A loop made only of such calls stays where it was.

Measured on 2026-11-26, `release` profile, 21 runs of each alternated with main's binary, the whole process, while
other work ran on the machine (load 6.3 to 9.4); the median, then the fastest and the slowest run, in ms:

| Program | Before | Now | Interpreter only |
|---|---:|---:|---:|
| 10^7 calls of `text.ByteLength`, 2 operations a call | 513.6 (354.7–642.8) | 526.8 (373.2–630.1) | 464.8 |
| 10^7 calls of `dict.Has` | 792.8 (554.5–1,122.5) | 792.3 (543.8–1,180.4) | 769.8 |
| 10^7 calls of `sys.Now` | 504.6 (403.5–648.9) | 498.5 (400.7–593.8) | 488.3 |
| 10^7 times `text.ByteLength(text.Slice(2, 4, s))` | 2,167.8 (1,498.0–3,112.4) | 2,270.0 (1,528.8–3,082.2) | 2,111.8 |
| 10^6 turns of 20 operations of floats and a `dict.Has` | 218.0 (157.9–329.8) | 220.6 (158.6–347.0) | 210.1 |
| 10^6 turns of 60 operations of floats and a `dict.Has` | 490.9 (358.4–589.0) | 243.0 (173.6–332.9) | 490.0 |

The first five stay in the interpreter, before and now: what separates them is inside the noise of the machine. The
last is machine code now, twice as fast. Node and LuaJIT make the calls of their builtins inside their machine code,
and Go compiles its library with the program: in none of them does such a call cross from one runtime to another, as
Cesia's crosses from the machine code that MIR makes into OCaml.

**Centauri.** Its request path, the public route, a thing by its id and a page, gets no machine code yet: a public
request takes 20.5 µs, as with main's binary, a thing by its id 35.5 against 36.0, a page 135.2 against 135.7 (medians
of 21 runs of 2,000 requests each, without the network, load 6.5 to 8.6), and under load a server answers 12,715
requests of `/hello` a second, against 12,285, on 0.95 core, beside 27,516 for `std/http` alone and 92,869 for Go's
`net/http` on 3.18 cores (21 measures of 2 s each, 256 kept connections, load 4.1 to 8.7). The natives were the
first thing that kept its hot versions out; now each stops at the next thing the JIT doesn't make (`CESIA_JIT_SHOW=1`,
on `bench/micro.ce` of Centauri):

| What keeps it out | Versions and loops |
|---|---:|
| a closure: the handler of a route, as `r -> {Text: "Hello"}` | 18 |
| a field read, or arithmetic on a value of no type, in a version as a whole: no frame to bet on | 7 |
| a text made of parts, `"$x"` | 6 |
| a statement the JIT doesn't make, as a write into a field | 5 |
| a `match` | 4 |
| a function literal | 4 |
| too few operations for its calls of natives | 4 |
| an `if` that gives a value, or another form of expression it doesn't make | 3 |
| a native of a package, Cepheus's | 3 |
| a cell of a list that is no variable of its frame, as `parts[2]` of a list given | 2 |
| an `in` | 2 |
| a comprehension | 2 |
| the larger or the smaller of two values that are no numbers | 2 |
| a native that waits, of `std/fiber` | 1 |
| a `?` | 1 |
| an empty map, `{}` | 1 |
| a call of a function held in a field | 1 |
| a variable that a closure shares | 1 |

Before, the first refusal of 32 of them was a native. The next part tells what lowers them now:
[Versions as a whole without a bet](#versions-as-a-whole-without-a-bet).

### Versions as a whole without a bet

A loop gets its machine code in the middle of a run: the frame then holds the values its bets read, and a bet that
fails goes back to the interpreter before the statement it is in. A version as a whole gets its machine code at the
start of a call, with no frame to look at, and the interpreter takes over no function in its middle: until 2026-11-26,
a field read, a test or arithmetic of values of no type, or a text of parts kept the whole version out. Such versions
are most of a server's code: the handlers of its routes and what they call. Now each of those operations has a fast
path in machine code, which needs no bet, and a slow path, which is the interpreter's own operation, called through
OCaml as a native is ([Machine code that calls OCaml](#machine-code-that-calls-ocaml)): the same roots for the
collector, the same error at the same site, the same steps.

**Fields.** A field read goes through an inline cache (Deutsch and Schiffman, POPL 1984; Hölzle, Chambers and Ungar,
ECOOP 1991): a constant of the unit holds the keys of the map, or the shape of the struct, that the field was last read
from, and the place of the field there. Machine code compares the first word of the value with the cache's, checks that
its values are in a store of values that has that place, and reads it: ten loads from memory and four tests. Anything else, a
map of other keys, a struct of another shape, a map of floats, a deep one, another kind of value, calls the
interpreter's read (`Compile.field_slow`), whose value or error is the interpreter's, and which fills the cache with
what it found. The place of a field depends only on the keys or the shape, so the cache is written as one word, a new
constant that holds both: machine code never reads the keys of one and the place of another. Its privacy depends on the
package that reads it, so the sites of one name share a cache within a package only. `dict.Get`, `dict.Has` and
`dict.GetOr` of a key written in the code go through the same cache, which also holds that keys made whole, those of a
literal, lack the key: every map that holds them has all of them.

**Values of no type.** A test of two values is made in machine code when it can tell: two words (`missing`, `true`,
`false`) are equal when they are the same word, two texts when their strings' blocks have the same words (OCaml pads a
string's block alike for each length, as `caml_string_equal` reads it), two Ints or two Floats by their numbers, as the
interpreter's `eq_b` and the others; anything else, as a list against a value, is the interpreter's test, through OCaml.
Arithmetic of two Ints or two Floats is made in machine code, the Ints checked for overflow as the interpreter checks
them; anything else is `Arith`'s. `text.ByteLength` of a text reads the length of its string from its block.

**Through OCaml.** A text of parts, `"$a and $(f(b))"`, is joined by a native of the JIT's own, which makes a text of
each hole with the memory and the steps that costs, as the interpreter's; before a hole whose evaluation may fail or
show, the holes before it are made texts first, so that what fails, fails in the interpreter's order. A literal of a
list, the larger or smaller of two values, `math.Div` and `math.Mod` of values, and a native given named arguments, in
the order of its parameters as the interpreter evaluates them, go through OCaml too. A call that machine code can't
make, of a function whose version doesn't lower or of a value that none of its bets takes, is the interpreter's call
of that value (`Compile.call_back`), above the frame of the call, whose site names it in a trace.

**Closures.** The interpreter's call of a closure writes its captured values to their slots before the frame starts
(`Compile.finish`); the outermost frame of a closure's machine code reads them there as it reads its parameters. A
variable captured before it had a value holds `Undef`: such a call is the interpreter's, whose read of it is the error.
A closure called from machine code still goes through OCaml: its captured values are in the function value, which a
nested frame doesn't read yet.

**What it changes for Centauri.** Its request path now lowers: of the versions that a run of `bench/micro.ce` makes hot
(`CESIA_JIT_SHOW=1`), the closures, the field reads and arithmetic of values in a version as a whole, the texts of parts and the larger or
smaller of two values, 33 refusals, are gone; 28 versions now lower whole, against 7 before, and the JIT then keeps them interpreted by its measure of what
they cost, 23 of them for their calls through OCaml (fewer than 24 operations a call: their work is in the natives they
call, `fiber.Admit`, `list.Concat`, `json.Text`) and 5 because they have neither a loop nor a call: the way into
machine code and back would cost more than it saves. Each of the others stops now at the next thing the JIT doesn't
make:

| What keeps it out | Before | Now |
|---|---:|---:|
| a closure: the handler of a route, as `r -> {Text: "Hello"}` | 18 | 0 |
| a field read, or arithmetic on a value of no type, in a version as a whole | 7 | 0 |
| a text made of parts, `"$x"` | 6 | 0 |
| the larger or the smaller of two values that are no numbers | 2 | 0 |
| lowered whole, its calls through OCaml too many for what it computes | 4 | 23 |
| lowered whole, with neither a loop nor a call | 3 | 5 |
| a statement the JIT doesn't make: `for x in xs` over a list, a write into a field | 5 | 7 |
| a function literal | 4 | 7 |
| a call of a function held in a field, as `env.Who(req, env)`, which may be a method | 1 | 4 |
| a `match` | 4 | 4 |
| a native of a package, Cepheus's | 3 | 4 |
| a cell of a list that is no variable of its frame, as `routes[k]` of a list given | 2 | 3 |
| a comprehension | 2 | 3 |
| an `in` | 2 | 2 |
| another form: an `if` that gives a value, a call with named arguments of a function, a map in a variable of a module | 3 | 3 |
| a native that waits, of `std/fiber` | 1 | 1 |
| a `?` | 1 | 1 |
| an empty map, `{}` | 1 | 1 |
| a variable that a closure shares | 1 | 1 |

Under `CESIA_JIT=always`, which makes every unit as it gets hot, for the tests, 37 versions of the path are machine code
against 27: `door`, `SessionKey`, `Json`, `Cookie`, the handlers' closures and those of the shapes among them. In the
default mode, none: a version that lowers whole and calls OCaml as often as these do runs as fast in the interpreter,
which calls a native for less ([Machine code that calls OCaml](#machine-code-that-calls-ocaml)).

So Centauri's request takes the time it took, measured on 2026-11-26, `release` profile, against main's binary,
alternated, while other work ran on the machine: a public request 21.1 µs [19.1, 33.0] against 20.7 [18.8, 34.1], a
thing by its id 34.7 [31.3, 39.9] against 35.9 [31.7, 57.5], a page 132.0 [119.7, 158.8] against 134.6 [121.6, 202.8]
(medians of 21 runs of 2,000 requests each, without the network, [the fastest, the slowest], load 4.1 to 5.2); its time is
in the natives it calls, in its allocations and in the collector: a sampling of `/hello` (a timer of 500 µs of CPU, the
instruction where each tick fell) gives 53% to the interpreter's closures, 33% to the natives and the library, 12% to
the collector and the allocation. Where the same calls of natives sit in a loop, the cached keys and lengths make the
difference (21 runs, alternated, load 3.5 to 5.9):

| Program | Before | Now |
|---|---:|---:|
| 10^7 calls of `dict.Has` of a key written in the code | 557.5 (522.5–625.4) | 52.4 (50.0–106.1) |
| 10^7 calls of `text.ByteLength`, 2 operations a call | 375.3 (342.8–454.8) | 57.2 (52.3–77.3) |
| 10^6 turns of 20 operations of floats and a `dict.Has` | 173.3 (155.9–295.7) | 40.5 (38.0–80.0) |
| 10^6 turns of 60 operations of floats and a `dict.Has` | 181.3 (169.2–279.2) | 77.1 (71.7–133.9) |
| 10^7 calls of `sys.Now` | 409.7 (392.9–514.3) | 418.8 (389.0–481.2) |
| 10^7 times `text.ByteLength(text.Slice(2, 4, s))` | 1,630.5 (1,545.5–1,899.4) | 1,645.3 (1,501.5–2,047.5) |

```cesia allow=read,write
use std/plot

loops = ["dict.Has", "ByteLength", "20 ops + Has", "60 ops + Has", "sys.Now"]
times = plot.Bars(loops, [[557.5, 375.3, 173.3, 181.3, 409.7], [52.4, 57.2, 40.5, 77.1, 418.8]], label = ["before", "now"],
  color = ["#999999", "#3a5ad9"])
cached = plot.Of([times], title = "Loops that call natives: median of 21 runs", x = "loop", y = "milliseconds",
  size = [640, 360])
plot.Save(cached, "internals-cached.svg") -->
```

The first four are machine code now with no call of OCaml in their loop: the map's keys checked against the cache, the
length read from the string. `sys.Now` and `text.Slice` still cross into OCaml at each call, and stay where they were.

### The contract

The same program gives the same output, the same errors at the same lines, and the same limits, in the interpreter and in
machine code. Machine code counts steps as the interpreter does, checks bounds and overflow as it does, and leaves for
the interpreter at each full checkpoint, where the other fibers get their turn. It runs the garbage collector only through
a call into OCaml, its values held as OCaml's local roots: each turn of a compiled loop reserves the memory it will need
first, and leaves if there isn't enough, or, in a unit that calls natives, makes the room where it is. The tests run the whole suite in both tiers, and a difference is a bug of the JIT.

### What stays in the interpreter

- a call of a native that waits, asks for a permission or comes from a package, and a unit whose calls of natives come
  too often for what it computes, fewer than 24 operations a call
  ([Machine code that calls OCaml](#machine-code-that-calls-ocaml)): the interpreter calls a native for less;
- `for x in xs` over the elements of a list, and a call through a value that reached five functions or more, or a
  closure called from machine code: such calls go through OCaml
  ([Versions as a whole without a bet](#versions-as-a-whole-without-a-bet));
- in a loop, a statement inside an if that it can't make, as a `return` of a struct or an `io.Print`: that statement
  alone, each time it runs, and the loop comes back to machine code at its next turn; the whole loop, when such
  statements run every few steps;
- arrays of more than 15 floats made in a loop: the interpreter's operations on them, which work on many cells at a
  time, already cost little a cell;
- a map read or written with a key computed as the program runs, as `m["key$k"]`, and the text built for it. The hash, the
  probe of the table, its growth and the new text would each be a call into OCaml, which costs about 100 ns more than
  the interpreter's ([Machine code that calls OCaml](#machine-code-that-calls-ocaml)); what native code could save is the
  interpreter's own share of `bench/maps.ce`, a tenth of its time in its profile, and those calls would take it all
  back;
- a loop of a file's top that assigns a variable of the module which a function it calls, and doesn't inline, reads:
  that function would read the variable in its module while the machine code holds it in a register;
- in a version as a whole, a function literal, a `match`, a comprehension, an `in`, a `?`, a write into a field, and a
  call of a method or of a function held in a field: when it gets hot there is no frame to bet on, and a bet that fails
  would have no way back but its whole call; fields, tests and arithmetic of values, texts of parts and other calls
  lower without a bet ([Versions as a whole without a bet](#versions-as-a-whole-without-a-bet));
- a version as a whole with a loop whose calls make values, or that writes an array: a nested frame short of room could
  not go back to the interpreter, which takes over no function in its middle; its loops get their own machine code;
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
thread, which a timer can interrupt anywhere: a fiber is switched only at a wait or a checkpoint. Three consequences:

- a native runs to its end: [list.Sort] of a million elements, or [json.Parse] of a large file, runs whole before another
  fiber gets its turn;
- in machine code that calls itself, a recursion compiled by the JIT, a switch waits until the outermost compiled call
  returns or its loop reaches its next step. Results are those of a run where the switch came there instead: they can
  differ only for fibers that read a module's variable the top code changes, and the order in which fibers print can
  differ.
- when the top code gives a module's variable another number at a switch inside machine code that reads it, a code that
  reads it from a slot reads the new one at its next run, as the interpreter does, when it is of the same kind. A number
  the code took as a constant, or one of the other kind, it can't read: a loop gives the rest of its turns to the
  interpreter at its next step, which reads the new number; machine code made for a whole function goes on to the end of
  the call with the numbers it started with, as if the switch came there.

Since a fiber is switched only at those points, code between two of them sees no other fiber: there are no *data races*,
two threads changing the same memory at once, and no locks to take. Values are not shared anyway: a value sent on a
channel acts as a copy.

The steps of `--limit steps` belong to the whole program, and each fiber counts its own between two checkpoints. Under
such a limit, the steps a waiting fiber spent since its last checkpoint are now taken off what is left while it waits,
and one that runs again, or starts, takes no more fuel than the steps the others left: so the limit is reached at the
step that goes past it, in whatever fiber, as in the main program alone. Without a limit, nothing of this runs.
Before, a fiber started with a whole quantum of 10,000 steps, whatever was left, and a main program that waited kept its
last steps uncounted while the fibers ran: the limit was reached later, at a place that depended on where the
checkpoints fell, which machine code, whose budget is exact, put elsewhere than the interpreter. A loop that spawned
fibers of 500 steps under `--limit steps=20000` stopped at the spawn of one, after it ended; it stops inside it, at the
step past 20,000 (`tests/limits/fiber-short.ce`), in the interpreter and in machine code alike.

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

An array that grows, as the table of the places in the code that the compiler makes, doubles by copying itself twice
into the new one. Made with `Array.make` and the young value it grows for, an array past 256 places would first empty
the whole minor heap, as OCaml does so that the major heap points to no young block: until 2026-11-19, a first
[plot.Svg] of a line crossed 512, 1,024, 2,048 and 4,096 places that way, four minor collections that copied 175,000
words of trees and code to the major heap, then a major cycle, 2.2 ms of its 6.9 in the process. Now it makes no
collection at all: its 460,000 words fit in the minor heap, and the program ends before it is full.

A package read from its entry in the [cache of loaded packages](#the-cache-of-loaded-packages) met the same wall: the
statements of a file, its functions and its other arrays were each made of their first item, young, and a file of more
than 256 of them paid a minor collection for each, every tree read so far copied out, then a major cycle. Since
2026-11-23, an array that long is read in pieces of 256, young, which `Array.concat` joins in the major heap with no
collection: the cells of Cemacs, past 256 functions, load with none, and its first frame takes 30.84 ms instead of
32.96, the 30.86 it took before them, the medians of 21 runs, alternated.

The memory limit, 80% of the machine's memory unless `--limit memory=` says otherwise, is checked at full checkpoints,
before each large allocation, and at each megabyte of a text that values are written into, as by `value.Text`,
`io.Print` or `json.Text`. When the heap seems past it, Cesia runs a full collection first, and stops the program only
if the memory still in use is past the limit: garbage alone never reaches it.

The large allocations are counted as they are reserved, since OCaml's count of its heap sees them only at its next
cycle, and the heap is looked at once each time their count since the last full checkpoint or full collection crosses
a quarter of the limit. Until 2026-11-25 it was looked at at every reservation past the first quarter, and a server,
whose request fibers never reach a full checkpoint, paid OCaml's count, `Gc.quick_stat`, at each one: after a few
minutes of serving, a third to a half of its time, its plaintext route down from 29,300 to 14,900 requests a second
(stacks of the process sampled with `eu-stack`, 12 rounds of 19 minutes alternated with a Go server as the control).

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

**What an entry holds.** One file per package, named by a digest of the build of Cesia that wrote it and of where the
package is (its folder, or the name of a file of `std/` inside the binary), and replaced when the package changes: the tree of each of its files after the
resolver, the names each file reads from each package it uses, and the questions the resolver asked about other modules,
with their answers. A name that the resolver tied to a module of another package keeps that module by its place: the
j-th module, counted from the end, of the package of the file's u-th use. In another run, the modules get other numbers,
and the places find them. A package of `std/` with natives keeps them last, and its Cesia code, which loads only for a
file that names something of it, goes before them: counted from the end, a place stays the same whether or not another
package of the run loaded that code. Nothing is kept for what the debugger adds (`--debugger`), what `cesia check` and
the verdicts of `cesia test` read with their own rules, and packages of less than 512 bytes, which parse faster than
their entry is found and checked. Since the name holds the build, two versions of Cesia used in turn, as an old binary
kept beside a new one, keep each their own entries; until 2026-11-24 they had the same names, and each run wrote over the
other's, so every run read its packages from their sources.

**What a run checks before it uses an entry**, in this order:

- the file is the person's own, and no one else's: a plain file, not a link, that no one else may read or write, in a
  folder that is theirs alone, which Cesia makes so (permissions 0700 for the folder, 0600 for each file); the file
  opened is the one looked at, the same device and inode, so a link put in its place in between isn't followed;
- the *checksum* of its head is the one written at its start, and its length the one its head says. A checksum is a
  number made from all the bytes it is made of, which changes when any of them does; Cesia's is XXH64, by Yann Collet,
  of 8 bytes, the one zstd and lz4 check their frames with. A damaged head, or an entry cut or grown, is never decoded;
  the record of each function in its tail has a checksum of its own, checked when the record is read (below). Until 2026-11-19 it was BLAKE2b, of 16 bytes, a cryptographic digest:
  XXH64 finds a damage as well, with a chance of $2^{-64}$ to miss one, and is 7 times faster here, 4.1 GB/s against
  0.57, 32 µs instead of 232 for the 133 KB of the entry of [std/plot]. Neither keeps out someone who can write the
  folder, who can write an entry and its sum as well: the folder is the person's own, as above. The digests of the
  sources, below, stay BLAKE2b's, whose collisions no one can make: they say that the code that runs is the code on
  the disk;
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

**A body read at its first call.** Most functions of a large program don't run as it starts: Cemacs, up to its first
frame, calls 262 of the 1,118 functions of its packages. Reading every tree of an entry made the young collections copy
them all to the major heap: 723,000 words promoted at Cemacs's start, 318,000 now. So the load reads the tree of each function but
for its body, which it skips: the body is read from the entry the first time something needs it, its first call most
often, or the JIT when it looks at a function it may inline. The body of a file, whose statements run at once, and the
one of a struct, which the load reads to know its fields, are read with the rest. The places of a body and the numbers
of its nodes are counted from those of its function's header, each most often in a byte, so that it reads alone.

**Records, mapped.** Since 2026-11-24, an entry is in two parts. Its *head* is what the load needs: the texts the head
names, the build, the digests, the uses, the questions, and the tree of each file, each function with its name, its
parameters, its sizes and what its callers read of it. Its *tail* holds a *record* for each function whose body waits for
its first need: the body, the names of its variables and those that can be read before they are set, which only the
function's own code reads, and the texts that only the record names, once each at its start. The header of the function,
in the head, says where its record is, its length and its checksum. A function inside another has a record of its own,
written before the one around it. The load doesn't read the file: it *maps* it, through OCaml's `Unix.map_file`, the
system's `mmap`, which makes the file's bytes part of the program's memory and reads from the disk, or takes from the
system's cache of files, only the pages the program touches; its descriptor is closed at once. Of the 236 KB of the entry
of [std/plot], the load reads its head, 25 KB, and checks it; a run of `use std/plot` then reads none of its 260 records,
and a first [plot.Svg] of a line 105 of them, 91 KB, each the first time its function runs. An entry is 3 % larger than
before, as a short name that several records use is written in each. A record is copied out of the
mapping, then checked, then read: the copy, in `src/sys/entries.ml`, goes 8 bytes at a time by the compiler's own loads,
9 GB/s for a record of 800 bytes, after one check that the range is inside the file; the checksum and the reader then work
on that copy as on any text. What is checked is what is read, whatever another process writes into the file meanwhile.
Reading in place, from the mapping, would have checked the bytes 4 times slower, as the core of Cesia may not use those
loads, and would have left a moment between the check and the read.

On POSIX, a file mapped stays as it was for the run that maps it when another run removes it or renames a new entry over
it: "The mmap() function shall add an extra reference to the file associated with the file descriptor fildes which is
not removed by a subsequent close() on that file descriptor" (POSIX.1-2024, `mmap`), and Cesia never writes an entry in
place. A process that changes an entry in place changes it under the mapping too, which POSIX leaves open for a private
mapping and Linux shows: the record changed fails its checksum when it is read. One that cuts an entry in place while a
run maps it ends that run with the signal SIGBUS if the run then reads a record past the new end, as POSIX says:
"References within the address range starting at pa and continuing for len bytes to whole pages following the end of an
object shall result in delivery of a SIGBUS signal". Only a process of the person, who can already write a valid entry
in the folder, can do either. On Windows, a file mapped can't be removed or replaced until the run ends; no entry is
written there today (below), so none is mapped.

**A record that doesn't read**, its checksum wrong, its range past the file, or its reading not ending where its length
says, no longer stops the program, as it did until 2026-11-24 with "The cache of loaded packages kept this function
damaged". The files of the package are parsed and resolved again from the very sources the load read, which the run keeps:
the texts of `std/` inside the binary, a project's files as they were read and checked against their digests, never the
disk as it is now. They are resolved with the same lookups, the function is found there by its place, its name and its
sizes, its body and the names of its variables are taken from it, and the run goes on with the same output; the entry is
removed at once, and written again from those trees when the run ends. Only if that failed too, which can't happen as the
load asked the same questions, would the message above stop the program. A record is read only on the main domain, where
Cesia code runs; another domain never needs a body, and one that did would take the function from its source. The
functions that read the names of a function's variables first read its body: `Cache.ready`, in the compiler, the
inference, the JIT and the debugger. Cesia is not the first to wait for a function's first call: V8 parses the body of a
function of JavaScript only then, "When a preparsed function is later called, it is fully parsed and compiled on-demand"
(Verwaest and Hölttä, *Blazingly fast parsing, part 2: lazy parsing*, 2019); here the parse was already done once, and
what waits is reading it back.

A body that the load doesn't read hides no error: an entry is written only for a package that loaded from
its sources without one, and every error that a load finds, it finds then; the same functions run, with the same
results, the same errors on the same lines and the same stack traces.

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
one, the new one or none, never a half, and two runs that write it at once both write a whole one. The folder keeps the
count of its bytes in its file `total`, which each write adds to under a lock: only when the count would pass 256 MB, or
is unknown, is the folder looked over, by one run while the others wait, and the entries used least lately go, down to
128 MB. Before, the first write of each run looked over every entry, 40,000 files on a machine in use: hundreds of runs
that ended at once, as a suite of tests, each read them all and stalled the disk. Reading an entry keeps its date
fresh, once a day. The folder can be deleted at any time, as any cache.

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
three times faster than lexing and parsing its source, and the resolver doesn't run at all; what was left of a load was
mostly that reading, and the young collections that copied the new trees to the major heap, as for trees just parsed.

Since the bodies are read at their first call, measured on 2026-11-13, 21 runs of each, the two binaries taking turns,
the median and its 95 % interval, from the start of the process to its end, Cemacs from `bin/cemacs` to its first frame:

| Program | Every body read at the load | Each body at its first call |
|---|---:|---:|
| `use std/io` and `io.Print(1)` | 3.16 ms [3.07, 3.21] | 3.13 ms [3.07, 3.18] |
| `use std/plot` | 5.74 ms [5.59, 5.86] | 4.03 ms [3.98, 4.11] |
| `use std/cells` | 4.43 ms [4.35, 4.62] | 3.80 ms [3.70, 3.84] |
| Ceti's `src/browser` | 6.53 ms [6.36, 7.05] | 4.83 ms [4.73, 5.04] |
| Cemacs of 2026-11-12, before its cells | 52.39 ms [52.07, 53.85] | 45.94 ms [45.36, 46.38] |
| Cemacs with its cells and its IDE | 61.12 ms [60.17, 63.51] | 50.62 ms [50.07, 51.83] |

The first runs, with an empty cache, take the same time with either binary, within what the runs spread.

**The first graph.** Since 2026-11-19, a function that gives no number is inferred only when it runs
([Types](#types-inference-and-versions)), a growing array no longer empties the minor heap
([Memory](#memory-and-the-garbage-collector)), an entry is checked by XXH64 instead of BLAKE2b, and the number of each of
its nodes takes a byte most often: the entry of [std/plot] is 126.6 KB instead of 132.8. In the process, the first
[plot.Svg] of a line loses the four minor collections and the major cycle, 2.2 ms, 30 versions inferred, 0.3 ms, 21
bodies read, 0.2 ms, and 0.15 ms in reading the entries. From the start of the process to its end, on 2026-11-19, 21
runs of each, the three binaries taking turns, the median and the fastest: Cesia of 2026-11-18 before the 3D graphs and
the animations, which grew [std/plot] from 2,277 lines to 2,983; Cesia with them, before this change; and Cesia now:

| Program | Before 3D and animations | Before | Now |
|---|---:|---:|---:|
| `use std/io` and `io.Print(1)` | 3.20 ms (2.97) | 3.29 ms (3.06) | 3.11 ms (2.94) |
| `use std/plot` | 4.08 ms (3.89) | 4.38 ms (4.05) | 4.08 ms (3.86) |
| a first [plot.Svg] of a line of 3 points | 8.74 ms (8.28) | 10.29 ms (9.88) | 6.99 ms (6.59) |
| a first [plot.Svg] of a surface of 3 by 3 | | 14.20 ms (13.78) | 9.59 ms (8.89) |
| a session of cells, as Cemacs starts one, that runs `use std/plot` and a line | 9.72 ms (9.42) | 11.54 ms (11.10) | 7.74 ms (7.19) |
| `cesia test tests/lang/plot.ce`, its 49 tests | | 514 ms (501) | 507 ms (495) |
| the same, the 27 tests it had before 3D and animations | 228 ms (219) | | 230 ms (219) |

The programs that compute run as before: `bench/fib.ce` 60.0 ms before and 60.9 now, `bench/structs.ce` 43.6 and
42.8, `bench/real/csv.ce` 434.8 and 439.6, the medians of 11 runs taking turns, within what the runs spread.

**Records.** Measured on 2026-11-24, the binary before the records, at 8cf2caf, and the one with them taking turns, from
the start of the process to its end, the cache full, the median of 101 runs of each and its 95 % interval; Cemacs is its
packages loaded, those that `src/cemacs.ce` uses, without opening its window:

| Program | Before | With records |
|---|---:|---:|
| `use std/io` and `io.Print(1)` | 2.83 ms [2.78, 2.91] | 2.89 ms [2.84, 2.97] |
| `use std/plot` | 4.22 ms [4.14, 4.30] | 3.85 ms [3.82, 3.96] |
| a first [plot.Svg] of a line of 3 points | 7.63 ms [7.49, 7.84] | 7.61 ms [7.50, 7.76] |
| `use std/cells`, naming [cells.Parse] | 3.86 ms [3.81, 3.90] | 3.78 ms [3.73, 3.90] |
| Cemacs's `src/notebook` and `src/sdl` | 8.75 ms [8.70, 8.80] | 8.22 ms [8.14, 8.29] |
| every package of Cemacs | 11.80 ms [11.70, 11.91] | 11.33 ms [11.25, 11.44] |
| `use std/plot`, two versions of Cesia taking turns, 21 runs | 33.76 ms [32.46, 34.87] | 3.75 ms [3.65, 3.98] |
| `tools/test.sh`, the change loop, 21 runs | 5.61 s [5.26, 5.71] | 5.60 s [5.13, 5.82] |

`use std/plot` takes back the 0.33 ms that the 3D graphs had added to it; a package that a program loads and little
calls, as Cemacs's, gains what reading and checking its bodies cost. A first graph gains nothing that the runs can tell
apart, 0.02 to 0.23 ms in four series of 101: it reads 43 % of the bytes of the bodies of [std/plot], and what it does
with them, inferring and compiling the functions it runs, no cache removes. `io.Print(1)` reads no entry, and its two
times are within what the runs spread. Two versions taking turns used to read every package from its sources at each
run, as each found the other's entry under its name. The change loop is the same: its time is that of the tests.

**Tested** by `tests/cache_test.ml`, which damages each entry at 60 places, cuts it at 8 lengths, grows it, swaps it
with another and reads it with another build, each time with the same output and the entry written again as it was, or
left as it was when the byte is in a record that no run reads; reads the entries of two builds in turn, each keeping its
own; changes a file and a dependency, runs in turn two programs that load the Cesia code of `std/list` before and after a
package that reads only its natives, with nothing resolved again, checks that the bodies of the functions a run never
calls stay unread, in a package with recursion, closures and a function inside a function, that a function that only
a function never called calls stays unread too, and that one that gives back the number of a call keeps its type, an
Int, checks the checksum against the values of `xxhsum`, damages every record of the entries, cuts their tails or removes
them once they were read, each time with the same output and the entries written again, reads a body on another domain,
and checks, for each package of `std/`, that every function read from its entry, and every function taken from its
source when all its records are damaged, is the tree its sources give; by `tests/cache/entries.cmd`, the same with the
binary, and with a link, an entry that others may read, a folder that others may read and one that can't be written,
four runs at once, and an entry changed on the disk while a run that read it runs; by `tests/cache/midrun.cmd`, where
the entry of [std/plot] is removed, replaced or changed in every record under a run that read its head, also with the
JIT on every function and under `--limit memory=2M`, and the run draws the same graph; by `tests/cache/versions.cmd`,
two versions of Cesia in turn, ten runs, none writing an entry again; by the fuzzer, which gives the reader random
entries, real ones changed, and real ones changed in their records with their checksums made again; and by the golden
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
