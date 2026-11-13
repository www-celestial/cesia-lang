# References

The papers, standards and books that Cesia's design follows, or that it was measured against. Each entry gives its
authors, its title, where and when it appeared, a link, and in one line what Cesia took from it. Every entry was checked
against its publisher, its DOI or its authors' page; a work that couldn't be checked is not here. A *DOI*, a digital object
identifier, is a permanent link to a published work: `https://doi.org/` followed by it leads to the work, wherever its
publisher moves it.

## Values and maps

- James R. Driscoll, Neil Sarnak, Daniel D. Sleator, Robert E. Tarjan. "Making data structures persistent". *Journal of
  Computer and System Sciences* 38(1):86–124, 1989. <https://doi.org/10.1016/0022-0000(89)90034-2>. The word and the
  idea of a *persistent* structure, which keeps its old versions: every list and map of Cesia, as [Maps](maps.md) shows.
- Chris Okasaki. *Purely Functional Data Structures*. Cambridge University Press, 1998.
  <https://doi.org/10.1017/CBO9780511530104>. Persistent structures and their costs; [std/heap] is its leftist heap.
- Phil Bagwell. "Ideal Hash Trees". Technical report, EPFL, 2001. <https://infoscience.epfl.ch/record/64398>. The hash array
  mapped trie, a node of 32 children chosen by 5 bits of hash and kept compact by a bitmap: the storage of a map past 32
  keys once a write must keep the old map, in [How Cesia works](internals.md#maps-a-hash-table-then-a-hash-trie).
- Michael J. Steindorfer, Jurgen J. Vinju. "Optimizing Hash-Array Mapped Tries for Fast and Lean Immutable JVM
  Collections". *OOPSLA 2015*, ACM, 783–800. <https://doi.org/10.1145/2814270.2814312>. CHAMP: a node with two bitmaps,
  its own keys inline and its kids apart, no lone key below a node, a drop that brings a key back up: the nodes of a
  Cesia map past 32 keys once it is a trie.
- Python Software Foundation. "What's New In Python 3.6", the dict "reimplemented to use a more compact representation
  based on a proposal by Raymond Hettinger", its entries in the order of insertion.
  <https://docs.python.org/3/whatsnew/3.6.html>. The layout of the hash table of a Cesia map past 32 keys that one name
  holds: an index of slots over the entries in their order.
- Donald E. Knuth. *The Art of Computer Programming*, vol. 3, *Sorting and Searching*, 2nd edition, Addison-Wesley, 1998,
  section 6.4. Linear probing and its cost, $(1 + 1/(1 - a))/2$ slots for a key there and $(1 + 1/(1 - a)^2)/2$ for one that
  isn't at load $a$: 1.5 and 2.5 at half load, the most a Cesia table holds.
- Carl Friedrich Bolz, Lukas Diekmann, Laurence Tratt. "Storage Strategies for Collections in Dynamically Typed
  Languages". *OOPSLA 2013*, ACM, 167–182. <https://doi.org/10.1145/2509136.2509531>. A collection of integers kept as
  bare integers, switched once to general storage when another kind arrives: Cesia's lists, and the values of its tables.
- Rich Hickey. "A History of Clojure". *Proceedings of the ACM on Programming Languages* 4(HOPL), article 71, 2020.
  <https://doi.org/10.1145/3386321>. Clojure's persistent maps, built on Bagwell's trie, as a language's everyday
  dictionary: the model of Cesia's.
- Scott A. Crosby, Dan S. Wallach. "Denial of Service via Algorithmic Complexity Attacks". *12th USENIX Security
  Symposium*, 29–44, 2003.
  <https://www.usenix.org/conference/12th-usenix-security-symposium/denial-service-algorithmic-complexity-attacks>. Hash
  flooding: why the hash of a map takes a seed drawn at each run, and why keys of one hash go to a balanced tree.
- David S. Wise, Daniel P. Friedman. "The one-bit reference count". *BIT* 17(3):351–359, 1977.
  <https://doi.org/10.1007/BF01932156>. One bit that tells whether a value is shared: Cesia's *owned* bit, which lets a
  write change a value in place when nothing else holds it.
- Sebastian Ullrich, Leonardo de Moura. "Counting Immutable Beans: Reference Counting Optimized for Purely Functional
  Programming". *IFL 2019*, ACM, 2019. <https://doi.org/10.1145/3412932.3412935>. Immutable values updated in place when
  they are unique, as Lean 4 does with full counts: the same idea as Cesia's copy-on-write, with one bit.
- Xavier Leroy. "Unboxed Objects and Polymorphic Typing". *POPL 1992*, ACM, 177–188.
  <https://doi.org/10.1145/143165.143205>. Why OCaml keeps a float in a block of its own, except in an array or a record
  of floats only: a float value of Cesia is two blocks, and the store of a map or struct of floats an array of doubles.
- IEEE. "IEEE Standard for Floating-Point Arithmetic", IEEE Std 754-2019, 2019.
  <https://doi.org/10.1109/IEEESTD.2019.8766229>. The 64-bit floats of Cesia, their rounding, their infinities and NaN.

## The interpreter

- Peter J. Landin. "The Mechanical Evaluation of Expressions". *The Computer Journal* 6(4):308–320, 1964.
  <https://doi.org/10.1093/comjnl/6.4.308>. The closure, a function with the environment it was made in.
- Marc Feeley, Guy Lapalme. "Using Closures for Code Generation". *Computer Languages* 12(1):47–66, 1987.
  <https://doi.org/10.1016/0096-0551(87)90012-9>. A syntax tree compiled into closures that run it, faster than walking the
  tree: Cesia's interpreter, `src/lib/compile.ml`.

## The JIT

- Philip S. Abrams. *An APL Machine*. PhD thesis, Stanford University, report SLAC-114, 1970.
  <https://www.softwarepreservation.org/projects/apl/Papers/197002_An%20APL%20Machine-Abrams.pdf>. *Drag-along*: the
  operations of an expression on arrays deferred, then made cell by cell in one pass, with no array between them: the
  fusion of the operations on small arrays of floats in Cesia's JIT.
- L. Peter Deutsch, Allan M. Schiffman. "Efficient Implementation of the Smalltalk-80 System". *POPL 1984*, ACM, 297–302.
  <https://doi.org/10.1145/800017.800542>. The inline cache: the class met last at a call kept beside it, so the next
  call of the same class goes straight to its method. Cesia's caches of shapes and keys.
- Craig Chambers, David Ungar. "Customization: Optimizing Compiler Technology for SELF, a Dynamically-Typed
  Object-Oriented Programming Language". *PLDI 1989*, 146–160. <https://doi.org/10.1145/73141.74831>. A function compiled
  once per kind of its arguments: Cesia's versions, one per tuple of argument types.
- Craig Chambers, David Ungar, Elgin Lee. "An Efficient Implementation of SELF, a Dynamically-Typed Object-Oriented
  Language Based on Prototypes". *OOPSLA 1989*, 49–70. <https://doi.org/10.1145/74877.74884>. *Maps*, which V8 later called
  hidden classes: the layout of an object shared by all objects of its shape. Cesia's shapes of structs and shared keys of
  small maps.
- Urs Hölzle, Craig Chambers, David Ungar. "Optimizing Dynamically-Typed Object-Oriented Languages With Polymorphic Inline
  Caches". *ECOOP 1991*, LNCS 512, 21–38. <https://doi.org/10.1007/BFb0057013>. Inline caches at each site of the code;
  Cesia's of fields keep the last shape met, the monomorphic kind this paper starts from, and its JIT makes the
  polymorphic kind of this paper for a call through a value: a test of each function met, up to four.
- Urs Hölzle, Craig Chambers, David Ungar. "Debugging Optimized Code with Dynamic Deoptimization". *PLDI 1992*, 32–43.
  <https://doi.org/10.1145/143095.143114>. Leaving optimized code for the interpreter, with the state rebuilt: Cesia's
  bails.
- Urs Hölzle, David Ungar. "Optimizing Dynamically-Dispatched Calls with Run-Time Type Feedback". *PLDI 1994*, 326–336.
  <https://doi.org/10.1145/178243.178478>. Compiling for the types really met while the program ran: the guesses that
  Cesia's JIT takes from the frame.
- Andreas Gal and others. "Trace-based Just-in-Time Type Specialization for Dynamic Languages". *PLDI 2009*, 465–478.
  <https://doi.org/10.1145/1542476.1542528>. The tracing JIT, which compiles one hot path through the program. Cesia
  compiles whole functions and loops instead, with guards, which keeps its speed steady on code full of branches.
- Stephen J. Fink, Feng Qian. "Design, Implementation and Evaluation of Adaptive Recompilation with On-Stack
  Replacement". *CGO 2003*, IEEE, 241–252. <https://researchr.org/publication/FinkQ03>. Entering optimized code in the
  middle of a running loop through an entry that rebuilds its state and goes to the loop's head: Cesia's machine code is
  entered before a loop, whatever brought the run back, never in its body.
- Benoit Boissinot, Alain Darte, Fabrice Rastello, Benoît Dupont de Dinechin, Christophe Guillon. "Revisiting Out-of-SSA
  Translation for Correctness, Code Quality and Efficiency". *CGO 2009*, IEEE, 114–125.
  <https://dblp.org/rec/conf/cgo/BoissinotDRDG09>. Leaving SSA form puts a copy on each path into a block where versions of
  a variable meet, which only coalescing takes away: why a loop entered in its middle copied every variable at each turn.
- Rastislav Bodík, Rajiv Gupta, Vivek Sarkar. "ABCD: Eliminating Array Bounds Checks on Demand". *PLDI 2000*, ACM,
  321–333. <https://doi.org/10.1145/349299.349342>. Bounds proved from the tests that guard each branch, and the checks
  they make useless dropped: Cesia's JIT drops the overflow check of `n - 1` in the `else` of `if n < 2`.
- Peng Zhao, José Nelson Amaral. "Function Outlining and Partial Inlining". *SBAC-PAD 2005*, IEEE, 101–108.
  <https://doi.org/10.1109/CAHPC.2005.26>. Inlining only the hot part of a function into its callers: Cesia's JIT copies
  the test of a callee that returns at once, as `fib`'s `if n < 2 then n`, into each call.
- Lukas Stadler, Thomas Würthinger, Hanspeter Mössenböck. "Partial Escape Analysis and Scalar Replacement for Java".
  *CGO 2014*, ACM. <https://doi.org/10.1145/2544137.2544157>. An object kept as its fields where it doesn't
  escape and made only on the paths where it does: the map that Cesia's machine code reads from a list for its fields
  is four registers, made only at a bail or at the end of the run.
- Mike Pall. "Allocation Sinking Optimization". LuaJIT wiki, 2012, shipped in LuaJIT 2.0; the text is kept at
  <https://ujit.readthedocs.io/en/latest/public/tut-allocation-sinking.html>. An allocation moved off the fast path to the
  exit that needs it: the same for Cesia's maps and structs of floats in a loop.
- Andreas Wöß, Christian Wirth, Daniele Bonetta, Chris Seaton, Christian Humer, Hanspeter Mössenböck. "An Object Storage
  Model for the Truffle Language Implementation Framework". *PPPJ 2014*, ACM, 133–144.
  <https://doi.org/10.1145/2647508.2647517>. An object's fields kept by their kind, a double unboxed, a field written with
  another kind generalized: the F store of a Cesia map or struct of floats, with one kind for the whole store.
- Anton Lorenzen, Daan Leijen, Wouter Swierstra. "FP²: Fully in-Place Functional Programming". *Proceedings of the ACM on
  Programming Languages* 7(ICFP), article 198, 275–304, 2023. <https://doi.org/10.1145/3607840>. A value nothing else
  holds may be rebuilt in place without changing what the program means: why Cesia's machine code writes the doubles of
  a new map into the owned one it replaces.
- Vladimir Makarov. MIR, a lightweight JIT compiler. <https://github.com/vnmakarov/mir>, and "MIR: A lightweight JIT
  compiler project", Red Hat Developer, 2020.
  <https://developers.redhat.com/blog/2020/01/20/mir-a-lightweight-jit-compiler-project>. The backend that makes Cesia's
  machine code from the text of its IR, copied into `src/sys/mir/`.

## Fibers and channels

- C. A. R. Hoare. "Communicating Sequential Processes". *Communications of the ACM* 21(8):666–677, 1978.
  <https://doi.org/10.1145/359576.359585>. Processes that share no memory and talk through channels, a send and a receive
  meeting: [fiber.Channel], and its size 0.
- The Go Programming Language Specification. <https://go.dev/ref/spec>, sections "Channel types", "Close" and "Select
  statements". Buffered channels, close, and select: the model of [std/fiber], with one difference, `Select` tries its
  channels in order where Go picks at random.
- KC Sivaramakrishnan, Stephen Dolan, Leo White, Tom Kelly, Sadiq Jaffer, Anil Madhavapeddy. "Retrofitting Effect
  Handlers onto OCaml". *PLDI 2021*, 206–221. <https://doi.org/10.1145/3453483.3454039>. Effect handlers and the small
  growing stacks behind them, in OCaml 5: what each fiber of Cesia is.
- Henry G. Baker Jr., Carl Hewitt. "The Incremental Garbage Collection of Processes". *Symposium on Artificial
  Intelligence and Programming Languages*, ACM, 55–59, 1977. <https://doi.org/10.1145/800228.806932>. The *future*, a value
  that a computation gives later: a task of [fiber.Spawn], which [fiber.Wait] reads.
- The Go Authors. Go 1.3 and Go 1.4 Release Notes, 2014. <https://go.dev/doc/go1.3>, <https://go.dev/doc/go1.4>, and the
  design document "Contiguous stacks", 2013. <https://go.dev/s/contigstacks>. A goroutine's stack starts at 2,048 bytes
  and is copied into a larger one when it fills: what Cesia's fibers are measured against, and why their stacks
  start at 8 slots and double.
- Joe Armstrong. "A History of Erlang". *HOPL III*, ACM, 2007. <https://doi.org/10.1145/1238844.1238850>. Processes switched
  after a count of reductions, supervisors that start a failed process again, and code replaced while it runs: Cesia's
  checkpoints every million steps, the supervisor of `--workers`, and `--watch`.

## Memory

- KC Sivaramakrishnan, Stephen Dolan, Leo White, Sadiq Jaffer, Tom Kelly, Anmol Sahoo, Sudha Parimala, Atul Dhiman, Anil
  Madhavapeddy. "Retrofitting Parallelism onto OCaml". *Proceedings of the ACM on Programming Languages* 4(ICFP), article
  113, 2020. <https://doi.org/10.1145/3408995>. The garbage collector of OCaml 5, and its domains: what frees Cesia's
  memory, and what runs the work on whole columns on several cores.

## The server and the network

- John D. C. Little. "A Proof for the Queuing Formula: L = λW". *Operations Research* 9(3), 1961, 383–387.
  <https://doi.org/10.1287/opre.9.3.383>. The requests waiting are the rate times the time each waits: the floor of a
  server's latency at 1,000 connections, whatever its scheduler.
- R. Fielding, M. Nottingham, J. Reschke (editors). "HTTP Semantics", RFC 9110, 2022.
  <https://www.rfc-editor.org/rfc/rfc9110>, and "HTTP/1.1", RFC 9112, 2022. <https://www.rfc-editor.org/rfc/rfc9112>.
  Methods, statuses, headers, persistent connections: [std/http].
- I. Fette, A. Melnikov. "The WebSocket Protocol", RFC 6455, 2011. <https://www.rfc-editor.org/rfc/rfc6455>. The server
  and the client of [std/websocket].
- Y. Bernier. "Latency Compensating Methods in Client/Server In-game Protocol Design and Optimization". Valve, GDC 2001.
  <https://www.gamedevs.org/uploads/latency-compensation-in-client-server-protocols.pdf>; G. Gambetta. "Fast-Paced
  Multiplayer (Part II): Client-Side Prediction and Server Reconciliation".
  <https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html>; Replicache, "How it works".
  <https://doc.replicache.dev/concepts/how-it-works>. A player's own moves drawn at once, then the server's state with
  the moves it hasn't answered replayed over it: the effects of the actions of a page of [std/live].
- D. L. Mills. "Internet Time Synchronization: The Network Time Protocol". *IEEE Transactions on Communications* 39(10),
  1991, 1482–1493. <https://doi.org/10.1109/26.103043>. The difference of two clocks from a round trip, its error at
  most half the trip: how `live.js` reads the app's times of its changes.
- crossbar.io. Autobahn|Testsuite 25.10.1, the reference suite of RFC 6455. <https://github.com/crossbario/autobahn-testsuite>.
  Its fuzzing server plays its cases against the client of [std/websocket] in the CI.
- E. Rescorla. "The Transport Layer Security (TLS) Protocol Version 1.3", RFC 9846, 2026, which replaced RFC 8446.
  <https://www.rfc-editor.org/rfc/rfc9846>. The encryption of `https`, which [std/tls] gets from OpenSSL.
- The Linux man-pages project. epoll(7) <https://man7.org/linux/man-pages/man7/epoll.7.html>, and epoll_ctl(2), whose
  `EPOLLEXCLUSIVE` came in Linux 4.5 <https://man7.org/linux/man-pages/man2/epoll_ctl.2.html>. How the scheduler waits on
  sockets on Linux, and how one connection wakes one worker.
- Prometheus. "Exposition formats". <https://prometheus.io/docs/instrumenting/exposition_formats/>. The text that
  [metrics.Text] gives.
- Deno. "Security and permissions". <https://docs.deno.com/runtime/fundamentals/security/>. A runtime with no access by
  default, and `--allow` flags scoped to a path, a host or a name: Cesia's [permissions](permissions.md) work the same way,
and, as there, a C library is outside the sandbox.

## Texts and formats

- Ken Thompson. "Programming Techniques: Regular expression search algorithm". *Communications of the ACM* 11(6):419–422,
  1968. <https://doi.org/10.1145/363347.363387>. Matching a regular expression by running all its states at once, in time
  linear in the text.
- Russ Cox. "Regular Expression Matching Can Be Simple And Fast", 2007. <https://swtch.com/~rsc/regexp/regexp1.html>, and
  "Regular Expression Matching: the Virtual Machine Approach", 2009. <https://swtch.com/~rsc/regexp/regexp2.html>. The Pike
  machine, Thompson's method with the positions of groups, from the code of Rob Pike's editor sam: [std/regex], whose time
  stays linear whatever the pattern.
- F. Yergeau. "UTF-8, a transformation format of ISO 10646", RFC 3629, STD 63, 2003.
  <https://www.rfc-editor.org/info/rfc3629>. Valid UTF-8, without overlong forms, surrogates or code points past
  U+10FFFF: what [text.IsUtf8] checks, and what Cesia's lexer asks of a source.
- Randall J. Fisher, Henry G. Dietz. "Compiling for SIMD Within a Register". *Languages and Compilers for Parallel
  Computing, LCPC'98*, LNCS 1656, Springer, 1999, 290–305. <https://doi.org/10.1007/3-540-48319-5_19>. SWAR, the work on
  several bytes held in one machine word, a name its authors coined in 1996: how [text.Count] counts a byte and
  [text.IsUtf8] skips ASCII, eight bytes at a time.
- Henry S. Warren, Jr. *Hacker's Delight*, 2nd edition, Addison-Wesley, 2013, section 6–1, "Find First 0-Byte". ISBN
  978-0-321-84268-8. The test that sets the high bit of exactly the zero bytes of a word, which [text.Count] adds up and
  [text.ByteFind] uses to find the rarest byte of a part.
- Donald E. Knuth, James H. Morris Jr., Vaughan R. Pratt. "Fast Pattern Matching in Strings". *SIAM Journal on
  Computing* 6(2):323–350, 1977. <https://doi.org/10.1137/0206024>. A search in time linear in the text and the part,
  which never reads a byte of the text twice: [text.ByteFind] and the other searches of [std/text] for a part of 32 bytes
  or more.
- T. Bray (editor). "The JavaScript Object Notation (JSON) Data Interchange Format", RFC 8259, 2017.
  <https://www.rfc-editor.org/rfc/rfc8259>. [std/json].
- Y. Shafranovich. "Common Format and MIME Type for Comma-Separated Values (CSV) Files", RFC 4180, 2005.
  <https://www.rfc-editor.org/rfc/rfc4180>. [std/csv] and the CSV of [std/frame].
- S. Josefsson. "The Base16, Base32, and Base64 Data Encodings", RFC 4648, 2006. <https://www.rfc-editor.org/rfc/rfc4648>.
  Hexadecimal and Base64 in [std/encode].
- T. Berners-Lee, R. Fielding, L. Masinter. "Uniform Resource Identifier (URI): Generic Syntax", RFC 3986, 2005.
  <https://www.rfc-editor.org/rfc/rfc3986>. The escapes of [encode.UrlEncode].
- John MacFarlane. CommonMark Spec, version 0.31.2, 2024. <https://spec.commonmark.org/0.31.2/>, and the GitHub Flavored
  Markdown Spec, version 0.29-gfm, 2019, for tables. <https://github.github.com/gfm/#tables-extension->. [std/markdown].
- Tom Preston-Werner, Pradyun Gedam and others. TOML v1.0.0, 2021. <https://toml.io/en/v1.0.0>. `cesia.toml` is read as a strict subset of
  it: a file Cesia accepts means the same in any TOML reader.
- Howard Hinnant. "chrono-Compatible Low-Level Date Algorithms". <https://howardhinnant.github.io/date_algorithms.html>. The
  days from a date and back, by eras of 400 years, in [std/date].

## Tests

- Koen Claessen, John Hughes. "QuickCheck: A Lightweight Tool for Random Testing of Haskell Programs". *ICFP 2000*,
  268–279. <https://doi.org/10.1145/351240.351266>. Properties tried on random cases: [test.ForAll].
- David R. MacIver, Alastair F. Donaldson. "Test-Case Reduction via Test-Case Generation: Insights from the Hypothesis
  Reducer (Tool Insights Paper)". *ECOOP 2020*, LIPIcs 166, 13:1–13:27. <https://doi.org/10.4230/LIPIcs.ECOOP.2020.13>.
  Shrinking a failure by shrinking the draws that made it, its tape: how [test.ForAll] finds the smallest failing case.
- Guy L. Steele Jr., Doug Lea, Christine H. Flood. "Fast Splittable Pseudorandom Number Generators". *OOPSLA 2014*,
  453–472. <https://doi.org/10.1145/2660193.2660195>. SplitMix64, the generator of [std/random]: the same seed gives the same
  numbers on every system.

## Solving a problem

The methods of [Solving a real problem](duplicates.md), step by step, and the documents of the tools it is compared with.
BLAKE2 is under [Cryptography](#cryptography), QuickCheck and the shrinking of Hypothesis under [Tests](#tests).

- George Pólya. *How to Solve It: A New Aspect of Mathematical Method*. Princeton University Press, 1945. The questions
  that start a problem: the unknown, the data, the condition; and looking back at the end.
- DARPA. "The Heilmeier Catechism". <https://www.darpa.mil/about/heilmeier-catechism>. The questions of George Heilmeier,
  director of DARPA from 1975 to 1977: above all, the exam that tells success, which the chapter writes as a property.
- Karl R. Popper. *Logik der Forschung*. Julius Springer, Vienna, 1934; in English, *The Logic of Scientific Discovery*,
  Hutchinson, London, 1959. A claim is scientific when an experiment could refute it: the falsifiable hypothesis of step 3.
- Raj Jain. *The Art of Computer Systems Performance Analysis: Techniques for Experimental Design, Measurement,
  Simulation, and Modeling*. Wiley, 1991. ISBN 978-0-471-50336-1. Measuring before changing, the same task for every
  system, and the errors of a measure.
- Andy Georges, Dries Buytaert, Lieven Eeckhout. "Statistically Rigorous Java Performance Evaluation". *OOPSLA 2007*, ACM,
  57–76. <https://doi.org/10.1145/1297027.1297033>. One run, or the best of a few, can rank two systems wrongly: report a
  confidence interval.
- Tomas Kalibera, Richard Jones. "Rigorous Benchmarking in Reasonable Time". *ISMM 2013*, ACM, 63–74.
  <https://doi.org/10.1145/2464157.2464160>. Repeat the runs at the level where the noise is: here the whole process.
- Jean-Yves Le Boudec. *Performance Evaluation of Computer and Communication Systems*. EPFL Press, 2010.
  <https://leboudec.github.io/perfeval/>. Its theorem 2.1: the confidence interval of a median between two order
  statistics, whatever the distribution, as every time of the chapter gives it.
- Andreas Zeller, Ralf Hildebrandt. "Simplifying and Isolating Failure-Inducing Input". *IEEE Transactions on Software
  Engineering* 28(2):183–200, 2002. <https://doi.org/10.1109/32.988498>. Delta debugging: a failing input made smaller
  until it shows the cause, here two files of one size.
- Alfred J. Menezes, Paul C. van Oorschot, Scott A. Vanstone. *Handbook of Applied Cryptography*. CRC Press, 1996, §2.1.5,
  Fact 2.27. <https://cacr.uwaterloo.ca/hac/>. The birthday problem, its exact probability and its approximation
  $1 - \exp(-n(n - 1)/(2m))$, from which the bound of the chapter follows.
- M-J. Saarinen (editor), J-P. Aumasson. "The BLAKE2 Cryptographic Hash and Message Authentication Code (MAC)", RFC 7693,
  2015. <https://www.rfc-editor.org/rfc/rfc7693>. BLAKE2b of 1 to 64 bytes, and the collision security of $2^{128}$ of its
  32-byte form, the digest of [cesia.Fingerprint].
- Xiaoyun Wang, Hongbo Yu. "How to Break MD5 and Other Hash Functions". *EUROCRYPT 2005*, LNCS 3494, Springer, 19–35.
  <https://doi.org/10.1007/11426639_2>. Collisions of MD5 within an hour: why a tool that hashes with MD5 must compare
  the bytes after.
- Jean-Karim Zinzindohoué, Karthikeyan Bhargavan, Jonathan Protzenko, Benjamin Beurdouche. "HACL*: A Verified Modern
  Cryptographic Library". *CCS 2017*, ACM, 1789–1806. <https://doi.org/10.1145/3133956.3134043>. The library whose
  BLAKE2b Python uses since the change gh-119316 of CPython, 2024, <https://github.com/python/cpython/pull/119316>, with
  a version for the AVX2 instructions: why Python hashes faster than Cesia on the machine of the chapter.
- Todd Mytkowicz, Amer Diwan, Matthias Hauswirth, Peter F. Sweeney. "Producing Wrong Data Without Doing Anything Obviously
  Wrong!". *ASPLOS 2009*, ACM, 265–276. <https://doi.org/10.1145/1508244.1508275>. Measurement bias from the setup, as the
  size of the environment or the order of linking: the threats to validity of the chapter.
- Adrian Lopez. fdupes, its manual page `fdupes.1`. <https://github.com/adrianlopezroche/fdupes>. Sizes, MD5, then the
  bytes compared; zero-length files kept unless `-n`, hard links not duplicates unless `-H`.
- Jody Bruchon. jdupes, its README and `filehash.c`. <https://codeberg.org/jbruchon/jdupes>. Sizes, the first 4 KiB, the
  whole file with XXH64, then the bytes compared unless `-Q`; zero-length files only with `-z`, hard links not duplicates
  unless `-H`.

## Data and numbers

- Wes McKinney. "Data Structures for Statistical Computing in Python". *Proceedings of the 9th Python in Science
  Conference*, 56–61, 2010. <https://doi.org/10.25080/Majora-92bf1922-00a>. The data frame of pandas: [std/frame].
- Charles R. Harris and others. "Array programming with NumPy". *Nature* 585:357–362, 2020.
  <https://doi.org/10.1038/s41586-020-2649-2>. Operations on whole arrays: [std/num] and the arithmetic of arrays.
- E. Anderson and others. *LAPACK Users' Guide*, third edition. SIAM, 1999. <https://doi.org/10.1137/1.9780898719604>.
  Solving, QR and eigenvalues: [std/lapack], when the machine has it.
- James W. Cooley, John W. Tukey. "An Algorithm for the Machine Calculation of Complex Fourier Series". *Mathematics of
  Computation* 19(90):297–301, 1965. <https://doi.org/10.1090/S0025-5718-1965-0178586-1>. The radix-2 fast Fourier
  transform of [num.Fft].
- E. W. Dijkstra. "A note on two problems in connexion with graphs". *Numerische Mathematik* 1:269–271, 1959.
  <https://doi.org/10.1007/BF01386390>. [algo.Dijkstra].
- V. I. Levenshtein. "Binary codes capable of correcting deletions, insertions, and reversals". *Soviet Physics Doklady*
  10(8):707–710, 1966; the Russian original, 1965: <https://www.mathnet.ru/eng/dan31411>. The edit distance of
  [algo.Levenshtein].

## Databases

- Kevin P. Gaffney, Martin Prammer, Larry Brasfield, D. Richard Hipp, Dan Kennedy, Jignesh M. Patel. "SQLite: Past,
  Present, and Future". *Proceedings of the VLDB Endowment* 15(12):3535–3547, 2022.
  <https://doi.org/10.14778/3554821.3554842>. The engine behind [std/sql], and how it is built.
- SQLite. "Write-Ahead Logging". <https://www.sqlite.org/wal.html>. The mode Cesia opens every database file in: readers
  don't block the writer, and each read sees the database as it was when it began.
- SQLite. "Isolation In SQLite". <https://www.sqlite.org/isolation.html>. Serializable transactions, by writes run one at
  a time, and snapshot isolation for the readers of a database in WAL mode.
- SQLite. "Pragma statements", `synchronous`. <https://www.sqlite.org/pragma.html#pragma_synchronous>. `FULL` is ACID in
  WAL mode, `NORMAL` may lose the last commits to a loss of power: why a commit of Cesia is durable.
- Hal Berenson, Phil Bernstein, Jim Gray, Jim Melton, Elizabeth O'Neil, Patrick O'Neil. "A Critique of ANSI SQL Isolation
  Levels". *SIGMOD 1995*, 1–10. <https://doi.org/10.1145/223784.223785>. The exact meaning of isolation, snapshot and
  serializable, used in [SQLite](sqlite.md).

## Cryptography

[std/crypto] calls libsodium, <https://doc.libsodium.org/>, and writes no primitive itself. The algorithms behind its
functions:

- Daniel J. Bernstein. "The Salsa20 Family of Stream Ciphers". In *New Stream Cipher Designs*, LNCS 4986, 84–97, 2008.
  <https://doi.org/10.1007/978-3-540-68351-3_8>, and "The Poly1305-AES Message-Authentication Code". *FSE 2005*, LNCS 3557,
  32–49. <https://doi.org/10.1007/11502760_3>. XSalsa20 and Poly1305, the encryption and the check of [crypto.Seal] and
  [crypto.BoxSeal].
- Daniel J. Bernstein, Niels Duif, Tanja Lange, Peter Schwabe, Bo-Yin Yang. "High-speed high-security signatures".
  *Journal of Cryptographic Engineering* 2(2):77–89, 2012. <https://doi.org/10.1007/s13389-012-0027-1>. Ed25519:
  [crypto.Sign] and [crypto.Verify].
- Jean-Philippe Aumasson, Samuel Neves, Zooko Wilcox-O'Hearn, Christian Winnerlein. "BLAKE2: Simpler, Smaller, Fast as
  MD5". *ACNS 2013*, LNCS 7954, 119–135. <https://doi.org/10.1007/978-3-642-38980-1_8>. [crypto.Blake2b], and the
  fingerprints of `cesia.lock` and `cesia upgrade`.
- Alex Biryukov, Daniel Dinu, Dmitry Khovratovich. "Argon2: New Generation of Memory-Hard Functions for Password Hashing
  and Other Applications". *IEEE EuroS&P 2016*, 292–302. <https://doi.org/10.1109/EuroSP.2016.31>. Argon2id, the hash of
  [crypto.HashPassword].
- NIST. "Secure Hash Standard (SHS)", FIPS PUB 180-4, 2015. <https://doi.org/10.6028/NIST.FIPS.180-4>. SHA-256 and SHA-512:
  [crypto.Sha256], [crypto.Sha512].
- H. Krawczyk, M. Bellare, R. Canetti. "HMAC: Keyed-Hashing for Message Authentication", RFC 2104, 1997.
  <https://www.rfc-editor.org/rfc/rfc2104>. [crypto.HmacSha256].

## Editors

- Microsoft. Language Server Protocol Specification 3.17.
  <https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/>. What `cesia lsp` speaks,
  positions counted in UTF-16 code units as it says: see [Editors](editors.md).
