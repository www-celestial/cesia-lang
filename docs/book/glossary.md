# Words

The words that programmers use for the ideas of this book, in alphabetical order. Each one says what it means in general,
then how Cesia does it, and leads to the chapter that shows it.

## ABI

An application binary interface: how compiled code passes arguments and lays out its data, so that code compiled apart can
call it. C has a stable one on each system and C++ has none, so Cesia reaches C++ through a small C layer: see
[C and C++](c.md).

## Amortized cost

The average cost of an operation over a long run of them, when most are cheap and a few are dear. [list.Append] on a list
that nothing else holds writes into free cells kept behind the last one, and doubles them when they run out: a copy now
and then, a constant time per element on average. See [How Cesia works](internals.md#value-semantics-and-copy-on-write).

## Anonymous function

A function without a name, written where it is used; also called a lambda. In Cesia, `x -> x + 1` on one line, or
`defn (x)` up to `end` for several: see [Functions](functions.md#functions-as-values).

## Atomic operation

An operation that happens all at once or not at all: no other program can see it half done. A rename within one file
system is atomic on Linux and macOS, so writing a new file then renaming it over the old one replaces a file safely, where
[sys.Write] alone can leave it cut short: see [Files](files.md#replacing-a-file-safely).

## Authenticated encryption

Encryption that also proves the message wasn't changed: a tag that only the holder of the key can make goes with it, and
a message whose tag doesn't match is refused rather than decrypted into garbage. [crypto.Seal] and [crypto.BoxSeal] do it
with XSalsa20 and Poly1305: see [Cryptography](crypto.md#encrypting-with-a-key).

## Backpressure

A slow receiver slowing down its sender, so that the values waiting between them stay few and the memory bounded. In Cesia
a channel made with a size, `fiber.Channel(size = 100)`, makes [fiber.Send] wait while it is full: see
[Fibers](fibers.md#a-channel-of-a-size).

## Backtracking

Trying the ways a regular expression can match one after the other, and going back to try the next when one fails. A
pattern such as `(a+)+$` then takes a time that doubles with each letter of the text. [std/regex] never backtracks: see
[Texts](texts.md#why-no-pattern-can-hang-a-program).

## Bail and deoptimization

Leaving machine code for the interpreter when a bet of the JIT turns out wrong, with every variable put back where the
interpreter keeps it, so the program goes on from the same statement. Other JITs call it deoptimization. Cesia's JIT
bails before the statement whose guard failed: see [How Cesia works](internals.md#bets-guards-and-bails).

## Baseline

The first measure of a problem, taken before anything is changed: the number that every change is compared with. Without
it, "faster" has no meaning. The baseline of [Solving a real problem](duplicates.md#the-baseline) is the time of the
first way that comes to mind, each file against every other one.

## Big O notation

A way to say how the cost of a program grows with the size $n$ of its input, without its constant: $O(n)$ grows as $n$, $O(n^2)$
as its square, so twice the input takes four times the work. Comparing every file with every other one is $O(n^2)$; grouping
them by size first reads each file at most once: see [Solving a real problem](duplicates.md#2-measure-before-changing-anything).

## Binding

The link between a name and a value. In Cesia `=` binds a name, and binding it again gives it another value: see
[Values and names](values.md#names).

## Birthday bound

The bound on the chance that two of $k$ values drawn at random among $N$ are equal: at most $k(k - 1)/(2N)$, one chance in $N$ for
each of the $k(k - 1)/2$ pairs. It is named after the surprise that 23 people suffice for two to share a birthday more often
than not. For a million files and a digest of 256 bits it is $4.3 \times 10^{-66}$: see
[Solving a real problem](duplicates.md#the-bound-worked-out).

## BLAS and LAPACK

Two standard interfaces of linear algebra: BLAS for the basic operations, as the product of matrices, and LAPACK, written on
it, for solving, factoring and eigenvalues. OpenBLAS and Apple's Accelerate are fast versions, tuned for each processor.
[std/num] uses one for large matrices, and [std/lapack] calls it directly: see
[Numbers and algorithms](numbers.md#large-matrices-blas-and-lapack).

## Boxed and unboxed

A boxed number sits in a block of memory of its own, behind a pointer, with a tag that says its kind; an unboxed one is the
bare machine number, in a register or a slot. Cesia's floats are boxed in values of any kind, and unboxed in a version of
a function that inference typed, in an array of floats, in a map or struct whose values are all floats, and in machine
code, where a variable that holds a float stays one in a register for the whole loop, so a loop of floats allocates
nothing: see [How Cesia works](internals.md#what-it-makes).

## Breakpoint

A place in the code where a debugger stops the program, to look at its variables before it goes on. In Cesia, `break FILE
LINE` in the debugger, with `if` and a condition to stop only when it holds: see
[The prompt and the debugger](debug.md#the-debugger).

## Call stack and frame

The calls in progress, each waiting for the one it made: the call stack. Each call has a frame, the slots of its
variables. The debugger shows them with `where`, and the `depth` limit, 10,000 by default, bounds how many there can be:
see [The prompt and the debugger](debug.md#the-debugger) and [Functions](functions.md#a-function-that-calls-itself).

## Capture by value

A closure that keeps the values of the names it uses as they were when it was made, so that a name given another value
later doesn't change it. Cesia's closures capture by value; those of JavaScript and Python capture the variable itself,
and see its later values: see [Functions](functions.md#closures).

## CHAMP

The compressed hash-array mapped prefix tree of Steindorfer and Vinju, 2015: a [hash array mapped
trie](#hash-array-mapped-trie) whose nodes hold inline each key that no other key under them shares 5 bits of hash with,
and a node of the next level for the bits that several share, with two bitmaps to tell which. It takes less memory than
a trie with buckets and no node holds a lone key below it. A Cesia map past 32 keys becomes one at its first write that
must keep the old map; until then, while one name alone holds it, it is a hash table: see
[How Cesia works](internals.md#maps-a-hash-table-then-a-hash-trie).

## Checkpoint

A moment where the interpreter stops counting to look at the program: at least every 10,000 steps it checks the limits of
steps and depth, and every million steps, a full checkpoint, it flushes the output, checks the memory, reloads a changed
file and lets the other fibers run: see [How Cesia works](internals.md#steps-and-checkpoints).

## Closure

A function together with the names it saw where it was made, which it can still use after that place has ended. A Cesia
closure keeps the values those names had when it was made: see [Functions](functions.md#functions-as-values).

## Closure compilation

Running a syntax tree by first turning each of its nodes into a function of the host language, a closure, which calls the
closures of its children: the work of looking at a node is done once, not at each step. Cesia's interpreter is written
this way, in OCaml: see [How Cesia works](internals.md#running-closures-as-code).

## Collision resistance

The property of a hash function that nobody can find two texts with the same digest, a collision, faster than by trying.
For a digest of $b$ bits, trying takes about $2^{b/2}$ hashes, by the birthday bound, so BLAKE2b-256 has a collision security
of $2^{128}$. MD5 lost it in 2005. See [Solving a real problem](duplicates.md#4-research).

## Column-major order

The order of the elements of a matrix in memory, column after column, so that the first position moves fastest, as in
Fortran, MATLAB, R and Julia; C and numpy's default are row-major. Cesia's arrays are column-major, and one position alone
counts in that order: see [Lists and arrays](lists.md#arrays-of-more-dimensions).

## Columnar data

A table kept as one array per column rather than one record per row, so that a sum or a filter runs down a whole column. A
data frame, as in pandas, is such a table; Cesia's is [std/frame]: see [Data](data.md#a-table-from-a-csv-file).

## Comprehension

A list built from another inside brackets: a value, a `for`, and a condition if needed, as in Python. In Cesia,
`[x * x for x in xs if x > 0]` is short for [list.Map] and [list.Filter]: see [Data](data.md#comprehensions).

## Concurrency and parallelism

Concurrency is several tasks in progress at once, taking turns; parallelism is several tasks running at the same instant,
on several cores. Cesia's fibers are concurrent, and its work on whole arrays and columns is parallel: see
[Fibers](fibers.md) and `CESIA_CORES` in [Environment variables](env.md).

## Confidence interval

A range that holds the true value of a measure with a given probability, as 95%: the wider it is, the noisier the measure.
The times of [Speed](speed.md#beside-the-giants) give the median of their runs and the 95% interval of that median, found
from the ranks of the sorted runs, with no guess about how they are spread.

## Continuation

The rest of a computation, held as a value that can be resumed: what is left for a fiber to do when it parks. OCaml 5's
effect handlers give it, once, and Cesia's scheduler resumes it when what the fiber waits for is ready: see
[How Cesia works](internals.md#how-a-fiber-stops-and-starts).

## Copy-on-write

Sharing a value until one of its holders writes to it, and copying it only then. A Cesia list, struct or map carries one
bit that says whether one place alone holds it: a write to it changes it in place, and a write to a shared one copies it
first. This gives value semantics at the cost of a copy only where a copy is needed: see
[How Cesia works](internals.md#value-semantics-and-copy-on-write).

## CSP

Communicating sequential processes: C. A. R. Hoare's model of 1978, in which processes share no memory and only exchange
messages over channels, a send and a receive meeting. Go's channels follow it, and so do Cesia's: see
[Fibers](fibers.md#channels) and [How Cesia works](internals.md#channels).

## Data frame

A table of named columns of one length each, as pandas has in Python and R has built in, on which a filter, a group or a
sum runs a whole column at a time. Cesia's is [std/frame]: see [Data](data.md#a-table-from-a-csv-file).

## Data race

Two threads that touch the same memory at the same time, one of them writing, with a result that depends on which went
first. Cesia's fibers run one at a time and share no value that can change, so they can't race, and need no lock: see
[Fibers](fibers.md#shared-values).

## Deadlock

Tasks that each wait for another, so that none can ever go on. When every fiber waits and nothing outside can wake one,
Cesia stops the program with the line of the wait, `All fibers are waiting and nothing can wake them.`: see
[Fibers](fibers.md#when-every-fiber-waits).

## Definite assignment

The rule that a name is given a value before it is read, on every path through the code. Cesia checks it when the file
loads, so a name read too early is an error before anything runs: see [How Cesia works](internals.md#names-the-resolver).

## Delta debugging

Making a failing input smaller step by step, keeping each smaller one that still fails, until what is left shows the cause
of the failure: Zeller and Hildebrandt's method, of 2002. The [shrinking](#shrinking) of [test.ForAll] does it on the
draws that made a case: see [Solving a real problem](duplicates.md#a-shortcut-proved-wrong).

## Dependency

Code from another project that yours uses. In Cesia a `[deps]` table of `cesia.toml` names its repository and its tag, and
`cesia pkg` fetches it into `deps/`: see [Packages](packages.md#code-from-other-projects).

## Deque

A double-ended queue: a sequence that takes and gives elements at both ends. [std/queue] is a persistent one, each
operation in $O(\log_{32} n)$: see [Numbers and algorithms](numbers.md#sets-queues-and-heaps).

## Destructuring

Taking a value apart into named pieces in one step. In Cesia a pattern of [match] does it: `[a, b]` for a list of two,
`{Name: n}` for a dictionary, `Point(x, y)` for a struct: see [Choices and loops](choices.md#match).

## Doctest

A test written as an example in the documentation of a function, so that the example can't go stale. In Cesia an indented
`call --> value` in a `(**` comment is one, and `cesia test` runs it: see [Tests](tests.md#examples-in-the-documentation).

## Dynamic typing

Types that belong to values, checked when an operation runs, rather than to variables, checked before the program runs.
Cesia is dynamically typed, with types you may write, checked when a value comes in, and types that inference proves to
make code faster: see [Types](types.md#checked-when-a-value-comes-in) and
[How Cesia works](internals.md#types-inference-and-versions).

## Edit distance

The fewest insertions, deletions and replacements of a character that turn one text into another, also called the
Levenshtein distance: 3 from `kitten` to `sitting`. [algo.Levenshtein] gives it: see
[Numbers and algorithms](numbers.md#algorithms-stdalgo).

## Effect handler

A part of a program that catches an *effect*, a request that the code inside it performs, as an exception, but which can
resume the code that performed it. OCaml 5 has them, and each Cesia fiber parks by performing an effect: see
[How Cesia works](internals.md#how-a-fiber-stops-and-starts).

## Epoll

The interface of Linux that tells which of many sockets are ready to read or write, at a cost that grows with the ready ones
only. Cesia's scheduler waits on it when no fiber is ready, and on `select` on macOS and Windows; `EPOLLEXCLUSIVE` makes a
new connection wake one worker of `--workers`: see [How Cesia works](internals.md#waiting-on-the-system).

## Equivalence relation

A relation that holds between a thing and itself, both ways between two things, and from a first to a third through a
second, as "holds the same bytes as" between files. It splits the things into classes, the sets whose members are related
to each other: the groups of copies of a folder are the classes of two files or more. See
[Solving a real problem](duplicates.md#1-the-problem-stated-precisely).

## Error propagation

Passing an error from the function that met it up to a caller that can handle it. In Cesia `?` after a result does it: it
gives the value of an `Ok`, or returns the `Err` at once: see [Errors](errors.md#passing-an-error-on).

## Error value

An error that a function gives back as its result, so that the code shows where it goes. Cesia's errors are values: an
[result.Err] around what went wrong, beside the [result.Ok] of a success: see [Errors](errors.md).

## Exception

An error that jumps out of the code that raised it, up to a `try` that catches it. Cesia has neither: a failure that can
happen is an [error value](#error-value), and a bug stops the program with a panic: see
[Errors](errors.md#errors-and-bugs).

## Exit code

The number a program gives back to the one that started it: 0 when all went well, another when something failed. In Cesia
[sys.Exit] ends with a code, and a program stopped by a bug ends with 1: see [Files](files.md#standard-input-and-the-exit-code).

## Expression and statement

An expression is code that gives a value, as `2 + 3`; a statement is code that only does something. In Cesia, `if` and
`match` are expressions: `kind = if n > 0 "positive" else "other" end`. See
[Choices and loops](choices.md#if-gives-a-value).

## Falsifiable

Said of a hypothesis that an experiment could prove wrong, since it predicts something that can be measured: Karl
Popper's criterion of a scientific claim. "The time goes into reading the same files again" is falsifiable, as it
predicts that reading each file once makes nearly all of the time go: see
[Solving a real problem](duplicates.md#3-a-hypothesis-that-can-be-proved-wrong).

## Fiber

A function that runs beside the others in the same program, with its own stack, run by the language rather than by the
system: also called a green thread, or a coroutine with a scheduler. Thousands of them cost little, about 2.1 KB each.
They run one at a time on one core. In Cesia [fiber.Spawn] starts one and [fiber.Wait] waits for its end: see
[Fibers](fibers.md) and [How Cesia works](internals.md#fibers-and-the-scheduler).

## Fix and continue

Changing the code of a program stopped in a debugger, then going on without restarting it: the next call of a changed
function runs its new code. Smalltalk and Lisp had it first. Cesia's debugger reloads the files changed when it resumes:
see [The prompt and the debugger](debug.md#fix-and-continue).

## Flat closure

A closure that copies the values it captures into a small array of its own, rather than keeping a link to the frame where
it was made. Cesia's closures are flat, which is why they capture by value: see
[How Cesia works](internals.md#closures).

## Floored division

A division of integers that rounds toward minus infinity, so that the remainder has the sign of the divisor:
`math.Div(-7, 3)` is `-3` and `math.Mod(-7, 3)` is `2`, as in Python. C and Java truncate toward zero instead, giving
`-2` and `-1`: see [Numbers and algorithms](numbers.md#one-number-stdmath).

## Foreign function interface

The way a language calls functions written in another one, most often C; FFI for short. Cesia's is [std/c]: [c.Open] loads
a library and [c.Fn] binds a function by its types, with the `ffi` permission: see [C and C++](c.md).

## Frame descriptor

What a compiler of a language with a garbage collector writes for each place in the code where a call returns: the size
of the frame and which of its slots hold values, so that the collector can find them on the stack. OCaml builds a hash
table of all of them at start: 19,723 for Cesia's binary, part of its start-up time, see
[How Cesia works](internals.md#start-up).

## Fsync

The system call that returns only once the disk holds a file's data, not only the system's memory, which writes it out
later: after it, a power cut loses nothing of the file. The folder that holds a new file's name needs its own fsync.
[sys.Write] with `sync = true` does both: see [Files](files.md#surviving-a-power-cut).

## Future

A value that a computation will give later, which a program can wait for: also called a promise. A task of [fiber.Spawn] is
one, and [fiber.Wait] waits for its value: see [Fibers](fibers.md#spawn-and-wait).

## Garbage collector

The part of a runtime that frees the memory nothing points to any more, so a program never frees it by hand. Cesia uses
OCaml's, which is *generational*: new blocks go to a small heap emptied often, since most die young, and the others to a
large one collected in slices: see [How Cesia works](internals.md#memory-and-the-garbage-collector).

## Golden test

A test that runs a program and compares all it printed with a saved output, the golden one. Cesia's own sources test the
language this way. A project tests values instead, with doctests and test functions: see [Tests](tests.md).

## Guard

A test that machine code makes before it uses a bet of the JIT, as "this value is a float": when it fails, the code bails
to the interpreter. See [How Cesia works](internals.md#bets-guards-and-bails).

## Handler

The function that answers one kind of request. In [std/http] it takes the request, a dictionary, and gives the response: see
[HTTP](http.md#an-application).

## Hard and symbolic links

A hard link is one more name of the same file: the bytes are on the disk once, and deleting one name frees nothing while
another is left. A symbolic link is a small file that holds a path, which the system follows. [sys.Walk] lists a symbolic
link and never follows it; [sys.Stat] says that a path is a symbolic link, but not that two names are hard links to one
file: see [Solving a real problem](duplicates.md#7-what-is-left).

## Hash array mapped trie

A HAMT: a tree where each level is chosen by 5 bits of a key's hash, so a node has up to 32 children, kept compact by a
bitmap of those that exist. Phil Bagwell described it in 2001, and Clojure made its persistent maps of it. A Cesia map of
more than 32 keys becomes one, of the kind called [CHAMP](#champ), at its first write that must keep the old map: a read
follows about $\log_{32} n$ levels, and a write copies only its path. See
[How Cesia works](internals.md#maps-a-hash-table-then-a-hash-trie).

## Hash flooding

An attack that sends a program many keys of the same hash, so that each read of its hash table walks them all and the
program slows to a halt: a denial of service. Cesia's hash takes a seed drawn at each run, and keys of one hash go to a
balanced tree: see [How Cesia works](internals.md#maps-a-hash-table-then-a-hash-trie).

## Hash table

An array of *slots* where a key's hash names the slot to look in first, so a read or a write takes a constant time on
average, whatever the number of keys. With *open addressing* and *linear probing*, a key whose slot is taken goes to the
next free one, and a read walks the slots from the first until the key or a free slot; kept at most half full, that is
1.5 slots for a key there and 2.5 for one that isn't. Python's `dict`, since 3.6, keeps its entries in a second array in
the order they came, and its slots hold their numbers: an *insertion-ordered* table. A Cesia map of more than 32 keys that
one name alone holds is one: see [How Cesia works](internals.md#maps-a-hash-table-then-a-hash-trie).

## Hash function

A function that turns a text of any length into a short number or text, its digest, the same for the same text. In a hash
table it picks the place of a key; in cryptography it must also be impossible to reverse or to make two texts collide, as
SHA-256 and BLAKE2b: see [Cryptography](crypto.md#hashes).

## Hash join

A join of two tables that puts the keys of one into a hash table, then looks up each row of the other in it: a time of
about the sum of their sizes, not their product. [frame.JoinOn] joins this way: see [Data](data.md#joining-two-tables).

## Heilmeier catechism

The questions that George Heilmeier, director of DARPA from 1975 to 1977, asked of every research project: what are you
trying to do, in plain words; how is it done today, and what are its limits; what is new in your approach; who cares; what
are the risks; what does it cost; how long does it take; what are the exams that check success. See
[Solving a real problem](duplicates.md#1-the-problem-stated-precisely).

## Hidden class

The layout of an object, the names of its fields and their places, shared by every object of the same shape, so that a
field read can be one comparison and one load. Self called them maps, V8 hidden classes. A Cesia struct has its shape, and
the maps made at one place of the code share their keys: see [How Cesia works](internals.md#maps-a-hash-table-then-a-hash-trie).

## Higher-order function

A function that takes a function, or gives one back. [list.Map], [list.Filter] and [list.Reduce] take one, and `adder(n) = x -> x + n`
gives one: see [Functions](functions.md#map-filter-and-reduce).

## HMAC

A hash under a secret key: only who has the key can make it, so it proves that a message comes from them and wasn't
changed. [crypto.HmacSha256] gives one: see [Cryptography](crypto.md#hashes).

## Hot reload

New code loaded into a program while it runs, so that it keeps its state. `cesia run --watch` does it at each save: see
[Install and first run](install.md#run-it-again-at-each-save).

## Immutability

A value that never changes once it is made: each operation gives a new value. Every value of Cesia acts this way;
`xs[1] = 5` gives the name `xs` a new list, which Cesia makes by changing the old one in place when nothing else holds it,
by [copy-on-write](#copy-on-write): see [Values and names](values.md#names).

## Inline cache

A small memory kept at one place of the code, as a field read, of the last kind of value met there and of where the field
was in it, so that the next read of the same kind is fast. Cesia keeps one shape at each site, a monomorphic inline cache:
see [How Cesia works](internals.md#caches-at-each-site). One that keeps several kinds is *polymorphic*: Cesia's JIT makes
one for each call through a value, of the functions it reached, up to four; past them a call is *megamorphic*, and stays
in the interpreter: see [How Cesia works](internals.md#calls-through-a-value).

## Intermediate representation

An IR: the form a compiler gives a program between its source and machine code, simpler to analyse than either. Cesia's
JIT turns a hot unit into an IR of basic blocks of typed instructions, which MIR then makes into machine code: see
[How Cesia works](internals.md#what-it-makes).

## Interpreter and JIT

An interpreter runs a program from a form held in memory, step by step; a just-in-time compiler, a JIT, turns the parts
that run often into machine code as the program runs. Cesia's JIT is a method JIT with loop regions: it compiles the hot
versions of functions that give numbers and the hot loops, numbers, arrays, maps and structs, and gives back to the
interpreter when a bet fails. See [Speed](speed.md) and [How Cesia works](internals.md#the-jit).

## Keep-alive

An HTTP connection kept open after a response, for the next request of the same client, which saves opening a connection
each time. [http.Serve] keeps connections, and closes one that waits past its deadline: see
[How Cesia works](internals.md#the-server).

## Language server

A program that an editor starts and talks to in JSON, by the Language Server Protocol, LSP, so that one server gives every
editor the errors, the documentation and the definitions of a language. `cesia lsp` is Cesia's: see
[Editors](editors.md).

## Lexer and parser

The lexer cuts the text of a program into tokens, its words; the parser turns the tokens into a syntax tree, following the
grammar. Cesia's parser is written by hand, by recursive descent, one function per rule: see
[How Cesia works](internals.md#reading-the-lexer-and-the-parser).

## Lexical scope

The names a piece of code sees are those written around it, not those of its caller. In Cesia a function sees its
parameters, its own names and those of its file; a name given a value inside it is its own, and `if` and `for` make no
scope: see [Functions](functions.md).

## Little's law

In a system that takes requests at a steady rate, the number waiting inside, $L$, is the rate, $\lambda$, times the time each
spends there, $W$: $L = \lambda W$ (Little, 1961). A server that holds 1,000 connections, each with a request waiting, and answers
36,000 requests a second, answers each in $1{,}000 / 36{,}000$ s, 28 ms, on average, however it schedules them. See
[How Cesia works](internals.md#what-it-serves).

## Live screen

A page whose data changes by itself, pushed to it by the server as others change it, instead of the page asking again
every few seconds, which is *polling*. In Cesia, [live.Route] serves such pages over a WebSocket, each with its shows and
its actions: see [HTTP](http.md#live-screens-stdlive).

## Lock file

A file that keeps the exact version and fingerprint of each dependency, so that every machine installs the same code.
Cesia's is `cesia.lock`, which `cesia new` and `cesia pkg` write: see [Packages](packages.md#code-from-other-projects).

## Median

The middle value of numbers put in order: half are below it and half above. It moves less than the mean when a few runs
are slow because the machine was busy, so [Speed](speed.md#beside-the-giants) gives medians.

## Message passing

Tasks that share data by sending it to each other, instead of changing the same memory. In Cesia a [fiber.Channel] carries values
from one fiber to another, with [fiber.Send] and [fiber.Receive]: see [Fibers](fibers.md#channels).

## Method and receiver

A method is a function attached to a type, and its receiver is the value it is called on. `defn (r Rect) Area()` names its
receiver `r` in parentheses before the name, and `r.Area()` calls it: see [Structs](structs.md#methods).

## Method JIT and tracing JIT

A method JIT compiles whole functions, or whole loops; a tracing JIT, as LuaJIT's, records the path that a hot loop takes
and compiles that path alone, with exits for the others. Cesia's JIT is a method JIT with loop regions, which keeps its
speed steady on code full of branches: see [How Cesia works](internals.md#the-jit).

## Middleware

Code between a server and its handlers, which sees each request and each response: a log, a header, a check. [http.Wrap]
puts one in front of an application: see [HTTP](http.md#middleware).

## Minor heap

The young part of memory in a garbage collector that sorts values by age: a new value is made there by moving a pointer,
and the collector empties it often, copying out the few values still in use. Most values die young, so they cost almost
nothing to free. OCaml's is 256k words by default; Cesia runs with 2M words (16 MB): see
[Native packages](native.md#what-a-call-costs).

## Native package

A package whose heart is compiled code that the language loads as a program runs: an extension module in Python, an
addon in Node, a NIF in Erlang. Cesia's is a package whose engine is OCaml, compiled once against `Cesia_v1`, which a
program runs with the `native` permission: see [Native packages](native.md).

## Nominal typing

A value has a type because of what made it, not because of what it has: a value is a `Point` because `Point` made it, and a
dictionary with the same keys is not one. Cesia's structs are nominal, its interfaces [structural](#structural-typing):
see [Structs](structs.md#struct-or-dictionary).

## Non-blocking I/O

A read or a write that gives back at once when it can't go on, instead of making the thread wait, so that one thread can
serve many connections. Every socket of Cesia is non-blocking: a fiber that would wait parks, and the scheduler wakes it
when the system says the socket is ready. See [How Cesia works](internals.md#waiting-on-the-system).

## Nonce

A number used once: a value that goes with each message encrypted under a key and must never be used twice with that key.
[crypto.Seal] draws a random one and keeps it in front of the message: see
[Cryptography](crypto.md#encrypting-with-a-key).

## Null

A value that means "no value": `null`, `nil` or `None` in other languages. Cesia's is `missing`, and a type takes it only
with a `?`, as `Text?`: see [Values and names](values.md#missing) and [Types](types.md#maybe-missing).

## On-stack replacement

Switching a loop that is already running from the interpreter to machine code, in the middle of its turns, with its
variables carried over. Cesia's JIT does it at a checkpoint inside a hot loop: see
[How Cesia works](internals.md#bets-guards-and-bails).

## Optimistic update

Showing the effect of one's own action at once, before the server has answered, then keeping the server's answer: its
change confirms the effect, its error undoes it. Games call it *client-side prediction* and *reconciliation*: each new
state of the server is drawn with the actions it hasn't answered yet replayed over it, a *rebase*. In Cesia, a page of
[std/live] gives `live.act` the effect of an action on each show: see [HTTP](http.md#actions).

## Optional typing

Types that a program may write or leave out. In Cesia types are a plus: code without them runs as fast, and a type that is
written is checked each time a value comes in: see [Types](types.md).

## Order statistic

The k-th smallest of a set of measures, once they are put in order: the first is the minimum, the middle one the median.
Two of them bound a confidence interval of the median without any guess about how the measures are spread: of 11 runs,
the 2nd and the 10th hold the true median with a probability of 98.8%. See
[Solving a real problem](duplicates.md#how-it-was-measured).

## Overlong form

A character of UTF-8 written with more bytes than it needs, as `0xC0 0x80` for the character 0, which takes one byte.
RFC 3629 forbids it, since a check byte by byte could let a forbidden character through in disguise: [text.IsUtf8]
refuses it. See [Texts](texts.md#valid-utf-8).

## Package

Code grouped under a name, also called a module, whose names you reach through it: its namespace. In Cesia a package is a
folder of `.ce` files: `use std/sql` brings one in, and `sql.Open` names a public function of it: see
[Packages](packages.md).

## Page cache

The copies of the files that the system keeps in free memory after reading them, so that the next read of the same bytes
costs no disk. A *warm* cache holds them, a *cold* one doesn't: a program that reads a folder twice is faster the second
time. [Solving a real problem](duplicates.md#threats-to-validity) measures both.

## Page fault

The trap a program takes the first time it touches a page of memory, 4 KB, that the kernel hasn't mapped for it yet:
the kernel maps the page, zeroes it, or copies it when the program writes a page it shares, as the data of a binary
that the loader fixes up. About 2 µs each on the machine of [Speed](speed.md#beside-the-giants); a start of Cesia takes
about 590, see [How Cesia works](internals.md#start-up).

## Parameterized query

A query whose values travel apart from its SQL text, so that no input typed by a user can change the query: a SQL
injection. In [std/sql] each `?` takes a value of the list: see
[SQLite](sqlite.md#values-never-go-into-the-text).

## Partial inlining

Copying only part of a function into the places that call it, usually the test that returns early, while the rest stays
a call (Zhao and Amaral, 2005). Cesia's JIT does it when a callee starts with a test of its parameters that gives one of
them or a constant, as `fib`'s `if n < 2 then n`: the leaves of a recursion then cost no call. See
[How Cesia works](internals.md#what-it-makes).

## Partition refinement

Splitting a set into groups by a key, then splitting each group again by a finer key, and so on, so that no step joins
what a step before had parted. Duplicate files are found this way: by size, then by digest among the files of one size:
see [Solving a real problem](duplicates.md#4-research).

## Pattern matching

Comparing a value with shapes, in order, and running the code of the first that fits, with names for its pieces. [match]
does it on values, lists, dictionaries, structs and results: see [Choices and loops](choices.md#match).

## Percent-encoding

Writing a byte that a URL can't hold as `%` and its two hexadecimal digits: a space is `%20`. [encode.UrlEncode] and
[encode.UrlDecode] do it: see [JSON and CSV](json.md#bytes-as-text-hexadecimal-base64-and-urls).

## Persistent data structure

A structure that keeps its old version when it changes, and shares most of its memory with the new one, by
[structural sharing](#structural-sharing). A big dictionary of Cesia that is shared is a hash trie, as in Clojure:
[dict.Put] gives a new one that shares the rest with the old; while one name alone holds it, it is a hash table changed in
place, which nobody else can see. See [Maps](maps.md) and [How Cesia works](internals.md#maps-a-hash-table-then-a-hash-trie).

## Pike machine

A way to run a regular expression that follows every way the pattern can go at once, step by step along the text, as
Ken Thompson's method of 1968 does, and keeps the positions of its groups: its time is linear in the text. Rob Pike wrote
it for his editor sam, and Russ Cox described it. [std/regex] is one: see
[Texts](texts.md#why-no-pattern-can-hang-a-program).

## Pipeline operator

An operator that passes a value to the next function, so that steps read from left to right: `|>` in F#, Elixir and OCaml.
Cesia's is [then]: see [Functions](functions.md#then).

## Position-independent executable

A program that can be loaded at any address of memory, chosen at random by the system at each start, which makes a bug in
C harder to exploit. Cesia's binary is one, so the system fixes up the addresses in its data at each start: part of its
start-up time, see [How Cesia works](internals.md#start-up).

## Pre-fork server

A server whose first process opens the listening socket, then starts several processes, the workers, which all take
their connections from it, as nginx does. `cesia run --workers` serves this way, under a supervisor: see
[HTTP](http.md#every-core) and [How Cesia works](internals.md#on-every-core).

## Preemptive scheduling

The scheduler moves from one task to another by itself, without waiting for the task to give way. Cesia's fibers give way
at their waits, and a fiber that computes gives way every million steps, as Erlang counts its reductions; no timer
interrupts a fiber, and a function of `std/` written in OCaml runs to its end. See
[Fibers](fibers.md#a-long-computation) and [How Cesia works](internals.md#how-a-fiber-stops-and-starts).

## Principle of least privilege

A program gets the rights it needs, and no more. In Cesia, `--allow read=./data` rather than `read`, and `net=:8080` rather
than `net`: see [Permissions](permissions.md#--allow).

## Priority queue

A collection that always gives back its smallest key first. [std/heap] is one, a leftist heap, each insert and pop in
$O(\log n)$: see [Numbers and algorithms](numbers.md#sets-queues-and-heaps).

## Property-based testing

Testing a rule on many cases that a generator makes, rather than on a few written by hand, then shrinking a failing case to
the smallest. QuickCheck began it in Haskell; [test.ForAll] does it: see [Tests](tests.md#properties).

## Public-key cryptography

Cryptography with a pair of keys: a public one, given to everyone, and a secret one, kept. What the public key encrypts,
only the secret key opens; what the secret key signs, the public key checks. [crypto.BoxSeal] and [crypto.Sign] use it:
see [Cryptography](crypto.md#encrypting-for-someone).

## Pure function

A function whose result depends on its arguments only, and that does nothing else: no print, no file, no clock. A Cesia
function can't change the values it is given: it is pure when it leaves the outside world alone. See
[Functions](functions.md).

## Range analysis

What a compiler proves of the values an integer can take, to drop the checks they make useless. In Cesia's JIT,
`math.Mod(i, 4)` is between 0 and 3, so `math.Mod(i, 4) + 1` needs no check of overflow; and in the `else` of
`if n < 2`, `n` is at least 2, so `n - 1` needs none either, the bounds that a branch's test proves, as in ABCD (Bodík,
Gupta and Sarkar, 2000): see [How Cesia works](internals.md#what-it-makes).

## Radix sort

A sort of numbers by their digits, one digit at a time from the lowest, each pass putting the numbers into buckets by
that digit and keeping the order of the pass before inside each bucket: no comparison, a time proportional to the count
of numbers times the count of digits. A Cesia map that turns from a hash table into a trie sorts its hashes so, by 10 bits
at a time: see [How Cesia works](internals.md#maps-a-hash-table-then-a-hash-trie).

## Recursion

A function that calls itself, directly or through others. Each call waits for the one it made, up to the `depth` limit,
except a call in [tail position](#tail-call): see [Functions](functions.md#a-function-that-calls-itself).

## Recursive descent

A way to write a parser by hand: one function per rule of the grammar, each calling the others, so that the nesting of
the calls follows the nesting of the code. Cesia's parser is one: see
[How Cesia works](internals.md#reading-the-lexer-and-the-parser).

## Regular expression

A small text that describes a set of texts, as `\d+`, one digit or more, to search, cut or replace in a text. [std/regex]
runs them in a time linear in the text: see [Texts](texts.md#regular-expressions).

## Rendezvous

A send that waits for a receiver to take its value, so that the two tasks meet: the synchronous channel of CSP, and Go's
unbuffered channel. A [fiber.Channel] of size 0 is one: see [Fibers](fibers.md#a-channel-of-a-size).

## REPL

Read, eval, print loop: a prompt that runs each expression typed and shows its value. Cesia's runs beside the running
program, `cesia run --repl app.ce`, inside the package of its main file: see
[The prompt and the debugger](debug.md#the-prompt).

## Route

A rule that sends the requests of one method and one path to a handler. [http.Get] and [http.Post] add one, and
`:name` in a path takes any word: see [HTTP](http.md#an-application).

## Salt

Random bytes stored with the hash of a password, so that two equal passwords give two different hashes and a table of
hashes computed in advance is useless. [crypto.HashPassword] adds one: see [Cryptography](crypto.md#passwords).

## Same-origin check

A server's check that a request comes from a page of its own site, by the `Origin` header the browser sends: a page
from elsewhere could otherwise use the cookies of the visitor. A browser holds `fetch` to this rule by itself, but not a
WebSocket, so the server checks it (RFC 6455 §10.2). [live.Route] gives a page of another origin a `403`: see
[HTTP](http.md#the-pages-side).

## Sandbox

A place where a program runs with only the rights it was given. A Cesia program starts in one, and each `--allow` gives it
the right to one kind of thing, within a scope, as Deno does for JavaScript. See [Permissions](permissions.md).

## Scalar replacement and allocation sinking

Two ways a compiler avoids making a value it can see through. *Scalar replacement* keeps an object that never leaves a
piece of code as its fields alone, in registers, as Graal does for Java (Stadler, Würthinger and Mössenböck, 2014);
*allocation sinking* makes the object only on the rare path that needs it whole, as LuaJIT does on the exits of its traces
(Pall, 2012). In Cesia's JIT, `p = ps[i]` read only for `p.X` and the like is four doubles in registers, and the map is
made only when the run gives back to the interpreter: see [How Cesia works](internals.md#what-it-makes).

## Scheduler

The part of a runtime that decides which task runs next. Cesia's keeps a queue, first in, first out, of the fibers ready
to run, and waits on the system when none is: see [How Cesia works](internals.md#how-a-fiber-stops-and-starts).

## Seed

The number a generator of random numbers starts from: the same seed gives the same numbers, so a run can be replayed. A Cesia
run takes one from the system, [random.Seed] tells it, and `cesia run --seed N` gives it: see
[Data](data.md#the-same-numbers-again).

## Serializable and snapshot isolation

Two guarantees of a database about transactions that run at the same time. Under *snapshot isolation*, each transaction
reads the database as it was when it began; under *serializable* isolation, the result is as if the transactions had run
one after the other. SQLite gives both: each read sees a snapshot, and writes run one at a time: see
[SQLite](sqlite.md#what-a-transaction-guarantees).

## Shared library

A file of machine code that a running program loads and links to itself, as a `.so` on Linux, a `.dylib` on macOS and a
`.dll` on Windows. OCaml's are plugins, `.cmxs` files: Cesia loads its JIT, its SQLite and the engines of native packages
this way, at their first use: see [Native packages](native.md#using-one).

## Shell injection

A command that nobody wrote, run because a text given to a shell holds a `;` or a backtick: a file named `x; touch owned`
would run `touch`. [sys.Run] passes its arguments as a list, to no shell, so it can't happen: see
[Files](files.md#other-programs).

## Short-circuit evaluation

`and` and `or` stop as soon as the answer is known, so their right side may never run: `false and f()` never calls `f`. See
[Values and names](values.md#true-and-false).

## Shrinking

Making a failing case smaller as long as it still fails, so that the failure shown is the simplest. [test.ForAll] shrinks
the draws that made a case, its tape, as Hypothesis does: see [Tests](tests.md#properties).

## Side effect

What a function does besides giving its result: printing, writing a file, sending a request. In Cesia each one that
touches the machine needs a permission, so the command line says which a program may have: see [Files](files.md).

## Signature

A short text made from a message with a secret key, which anyone with the public key can check: it proves who wrote the
message and that it wasn't changed. [crypto.Sign] makes an Ed25519 one: see [Cryptography](crypto.md#signatures).

## Snapshot testing

A test that keeps the text of a value in a file beside it, and compares the value with it at each run, so that a long
output needs no writing by hand. [test.Snapshot] does it: see [Tests](tests.md#snapshots).

## Specialization

Making a separate version of a function for each combination of the types of its arguments, so that each version knows its
types: called customization in the language Self, where it began. A Cesia function has up to 8 versions, then a generic
one: see [How Cesia works](internals.md#types-inference-and-versions).

## SSA form

Static single assignment: a form of code where each variable is assigned in one place only, so a compiler sees at once
where each value comes from. Where two paths meet, as at the start of a loop, a *phi* picks the version of the path that
came; leaving SSA for the machine puts a copy on each path into it. MIR, which makes Cesia's machine code, works so, and a
loop of Cesia is entered only before it, so that its only meeting point holds only what the loop changes: see
[How Cesia works](internals.md#what-it-makes).

## Standard input and output

The text a program reads, and the text it writes, in a terminal or a pipe of the shell; the standard error is a second
output, for what went wrong. In Cesia [io.Print] writes to the standard output, [io.PrintError] to the standard error, and
[sys.ReadInput] reads the whole standard input: see [Files](files.md#standard-input-and-the-exit-code).

## Static typing

Types checked before the program runs, for every variable and expression, as in Java, Go and OCaml: a program that can't
be proven right is refused. Cesia's types are checked when the program runs, and `cesia check` reports what it can prove
wrong before: see [Types](types.md#checked-when-a-value-comes-in).

## Storage strategy

A collection that stores its elements by their kind, as bare machine numbers while all of them are numbers of one kind,
and switches once, for good, to general storage when another kind arrives (Bolz, Diekmann and Tratt, 2013, from PyPy).
Cesia's lists keep integers, floats or values so, the hash table of a big map keeps its integer values bare, and a small
map or a struct keeps its values as doubles while all are floats: the program sees the same values either way. See
[How Cesia works](internals.md#maps-a-hash-table-then-a-hash-trie).

## String interpolation

Values written inside a text, where they go. In Cesia `"Hello, $name"` and `"$(2 + 2)"`, which are short for [text.Str]: see
[Values and names](values.md#texts).

## Struct

A value with a fixed set of named fields, also called a record. [struct] declares one, with defaults and types, and a field
written wrong is an error: see [Structs](structs.md).

## Structural sharing

Two versions of a persistent structure that share the parts they have in common, so that a change copies only what it
touches. A write to a Cesia map copies the path of nodes to its key, at most 6 small arrays, and shares the rest: see
[How Cesia works](internals.md#maps-a-hash-table-then-a-hash-trie).

## Structural typing

A value meets a type by what it has, not by a declaration that names the type. A Cesia [interface] is met by every value
that has its methods, as in Go: see [Types](types.md#interfaces).

## Sum type

A type whose values are one of a few cases, each with its own data. Cesia's is the result: either [result.Ok] of a value or [result.Err]
of an error, and [match] takes it apart case by case: see [Errors](errors.md#looking-at-a-result).

## Supervisor

A process that starts others and starts again one that ends, as Erlang's supervisors do. Under `cesia run --workers`, the
first process is the supervisor of the workers, and waits a little longer each time one ends too soon: see
[How Cesia works](internals.md#on-every-core).

## Surrogate

A code point from U+D800 to U+DFFF, which UTF-16 keeps to write the characters past U+FFFF in two halves. It is no
character by itself, so valid UTF-8 never holds one: [text.IsUtf8] refuses it. See [Texts](texts.md#valid-utf-8).

## SWAR

SIMD within a register: the same operation on several small values packed in one machine word, as eight bytes in 64
bits, with the ordinary instructions of the processor. [text.Count] finds the bytes equal to the one it counts eight at a
time so, and [text.ByteFind] the rarest byte of the part it looks for: see [Texts](texts.md#searching) and
[Bytes](texts.md#bytes).

## Syntax sugar

A shorter way to write what the language can already say. This book shows each one beside its plain form, checked:
`a..b` is [list.Range]`(a, b)`, and `d.Name` is `d["Name"]`: see [Lists and arrays](lists.md#ranges).

## Syntax tree

The program as a tree, one node per expression or statement, with the line and column of each: what the parser makes from
the text, and what Cesia compiles. See [How Cesia works](internals.md#reading-the-lexer-and-the-parser).

## Tail call

A call whose result is the result of the function that makes it, with nothing left to do after it. A Cesia function that
calls itself in tail position runs as a loop, in one frame, so it has no depth limit: see
[Functions](functions.md#a-function-that-calls-itself).

## Threat to validity

A cause that could make the conclusion of an experiment wrong although nothing in it looks wrong: a warm cache, a folder
of an unusual shape, another program on the machine. Each one is named, then ruled out or measured: see
[Solving a real problem](duplicates.md#threats-to-validity).

## Thundering herd

Many processes woken at once for one event that only one of them can take, which then race for it in vain. On Linux, the
workers of `--workers` watch the listener with `EPOLLEXCLUSIVE`, so a new connection wakes one: see
[How Cesia works](internals.md#on-every-core).

## Timing attack

Finding a secret by measuring how long a program takes to compare a guess with it, since a comparison that stops at the
first wrong byte takes longer for a better guess. [crypto.IsSame] compares in a time that depends only on the length: see
[Cryptography](crypto.md#comparing-secrets).

## Transaction

Changes to a database that happen all together or not at all. SQLite's are ACID: atomic, consistent, isolated and durable.
[sql.Transaction] keeps them all on an `Ok`, and undoes them all on an `Err` or a panic: see [SQLite](sqlite.md#transactions).

## Trie

A tree where each level is chosen by one piece of the key, as a dictionary of words is ordered by their first letter, then
the second. In a hash trie the pieces come from the key's hash: see [hash array mapped trie](#hash-array-mapped-trie).

## Type coercion

A value turned into another type by the language itself. Cesia does it in one case: an `Int` becomes a `Float` where a
`Float` is wanted, or beside one in arithmetic. A text never becomes a number by itself: see
[Types](types.md#an-int-becomes-a-float).

## Type feedback

The types that a program really met while it ran, which a JIT reads to bet on them. Cesia's JIT reads them in the frame
of a loop when it compiles it: see [How Cesia works](internals.md#bets-guards-and-bails).

## Union bound

The rule that the chance that at least one of several events happens is at most the sum of their chances. It needs no
assumption about how the events depend on each other, which is why it gives the birthday bound so simply: see
[Solving a real problem](duplicates.md#4-research).

## UTF-8

The usual way to write a text in bytes: `a` takes one, `é` two, an emoji four. A text of Cesia is UTF-8: [value.Len] and [text.Slice]
count characters, [text.ByteLength] and [text.ByteSlice] bytes: see [Texts](texts.md#bytes).

## Value semantics

Giving a value a second name, or passing it to a function, acts as a copy: a change through one name never shows through
the other. Every value of Cesia works this way, lists and dictionaries too: see [Values and names](values.md#names).

## Vectorized operation

One operation on a whole array, run element by element by the machine instead of a loop of the program. In Cesia,
`prices * 2` and `Sqrt(xs)` work on whole arrays, and on the columns of a frame: see
[Lists and arrays](lists.md#whole-arrays-at-once).

## Vendoring

Copying the code a project depends on into the project itself, so that it runs on exactly that code. A Cesia project keeps
`std/` and `deps/` this way, made again from `cesia.lock` by `cesia pkg install`: see
[Packages](packages.md#cesia-pkg).

## Wall clock

The time of day as the system keeps it, which the system may set forward or back, as when it corrects itself over the
network. [sys.Now] reads it: see [Files](files.md#the-clock).

## WebSocket

A connection that stays open after an HTTP request and carries messages both ways, for a chat or a live page, as RFC 6455
defines it. [http.Websocket] serves one, and [websocket.Dial] opens one as a client: see [HTTP](http.md#websocket).

## Write-ahead log

A file where every change is written before it is applied to the database, so that after a crash the database replays it
and loses nothing that was confirmed; it also lets readers go on while a writer works. Cesia opens every SQLite file in
this mode, WAL: see [SQLite](sqlite.md#what-a-transaction-guarantees).

## XSS

Cross-site scripting: a text from a visitor that a page shows without escaping, so that a `<script>` in it runs in the
pages of the other visitors. [http.Escape] and [http.Template] escape what they put in a page: see
[HTTP](http.md#escaping).

## Zero-downtime reload

Putting a new version of a server in place without refusing or losing a single request: the new processes start and
accept before the old ones stop. HUP does it under `cesia run --workers`: see
[HTTP](http.md#a-new-version-without-a-pause).
