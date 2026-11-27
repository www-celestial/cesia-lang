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
- Mark Shannon. "PEP 659 – Specializing Adaptive Interpreter". 2021. <https://peps.python.org/pep-0659/>; and "What's
  New In Python 3.11", <https://docs.python.org/3/whatsnew/3.11.html>. An instruction of CPython rewritten, once it has
  run, for the kinds it met there: a call of a builtin written in C, as `len()`, then calls it straight, up to 20%
  faster. Beside the interpreter's call of a native in Cesia, which [How Cesia works](internals.md#calls-of-natives)
  measures.
- K. C. Sivaramakrishnan, Stephen Dolan, Leo White, Tom Kelly, Sadiq Jaffer, Anil Madhavapeddy. "Retrofitting Effect
  Handlers onto OCaml". *PLDI 2021*, ACM. <https://doi.org/10.1145/3453483.3454039>. How OCaml 5 lays out its stacks: a
  handler of exceptions is installed by pushing the address of its code and the previous handler on the stack, a linked
  list of frames, and a raise jumps to the last one. Cesia installs none at the call of a native, where it cost a
  twentieth of `sys.Now`: an error of the system that a native lets out is caught where panics are.

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
- John Lu, Keith D. Cooper. "Register Promotion in C Programs". *PLDI 1997*, ACM, 308–319.
  <https://doi.org/10.1145/258915.258943>. A scalar kept in memory, as a global, held in a register through a loop that
  no other reference in it can reach: loaded before the loop, stored after it. Cesia's JIT does so for the variables of
  a module that a loop of a file's top assigns, stored at each way out of its machine code.
- Raymond Lo, Fred Chow, Robert Kennedy, Shin-Ming Liu, Peng Tu. "Register Promotion by Sparse Partial Redundancy
  Elimination of Loads and Stores". *PLDI 1998*, ACM, 26–37. <https://doi.org/10.1145/277650.277659>. The loads and
  stores of a promoted variable placed only where a path needs them: Cesia's engine loads such a variable when a run
  of machine code starts and stores it when the run leaves, never at a turn.
- Andreas Gal and others. "Trace-based Just-in-Time Type Specialization for Dynamic Languages". *PLDI 2009*, 465–478.
  <https://doi.org/10.1145/1542476.1542528>. The tracing JIT, which compiles one hot path through the program. Cesia
  compiles whole functions and loops instead, with guards, which keeps its speed steady on code full of branches.
- Victor Gomes. "Faster JavaScript calls". The blog of V8, 15 February 2021. <https://v8.dev/blog/adaptor-frame>. A call
  of JavaScript with fewer or more arguments than parameters went through an *arguments adaptor frame*, which filled the
  missing ones with `undefined`; V8 removed it, the callee padding them itself, up to 40% faster on such calls. Cesia's
  machine code calls a function that has defaults the same way: the callee's own entry makes the defaults left out.
- Stephen J. Fink, Feng Qian. "Design, Implementation and Evaluation of Adaptive Recompilation with On-Stack
  Replacement". *CGO 2003*, IEEE, 241–252. <https://researchr.org/publication/FinkQ03>. Entering optimized code in the
  middle of a running loop through an entry that rebuilds its state and goes to the loop's head: Cesia's machine code is
  entered before a loop, whatever brought the run back, never in its body.
- Benoit Boissinot, Alain Darte, Fabrice Rastello, Benoît Dupont de Dinechin, Christophe Guillon. "Revisiting Out-of-SSA
  Translation for Correctness, Code Quality and Efficiency". *CGO 2009*, IEEE, 114–125.
  <https://dblp.org/rec/conf/cgo/BoissinotDRDG09>. Leaving SSA form puts a copy on each path into a block where versions of
  a variable meet, which only coalescing takes away: why a loop entered in its middle copied every variable at each turn.
- Matthew Arnold, Stephen Fink, David Grove, Michael Hind, Peter F. Sweeney. "Adaptive Optimization in the Jalapeño
  JVM". *OOPSLA 2000*, ACM, 47–65. <https://doi.org/10.1145/353171.353175>. Recompiling a method at a higher level when
  the time it is expected to save, as it is expected to run as long again as it ran, beats the time to compile it:
  Cesia's level 2, made once a unit ran about as long as its level 1 took to make.
- Rastislav Bodík, Rajiv Gupta, Vivek Sarkar. "ABCD: Eliminating Array Bounds Checks on Demand". *PLDI 2000*, ACM,
  321–333. <https://doi.org/10.1145/349299.349342>. Bounds proved from the tests that guard each branch, and the checks
  they make useless dropped: Cesia's JIT drops the overflow check of `n - 1` in the `else` of `if n < 2`.
- Samuel P. Midkiff, José E. Moreira, Marc Snir. "Optimizing Array Reference Checking in Java Programs". *IBM Systems
  Journal* 37(3), 409–453, 1998. <https://doi.org/10.1147/sj.373.0409>. Loop versioning: a copy of a loop with no check
  of its arrays, chosen by tests made once before it, and the checked copy otherwise. Cesia's fast copies of a loop.
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
- The OCaml manual, version 5.5, chapter *Interfacing C with OCaml*, sections *Living in harmony with the garbage
  collector* and *Advanced topic: callbacks from C to OCaml*. <https://ocaml.org/manual/5.5/intfc.html>. A value held
  across an allocation or a call of OCaml is declared to the collector, `CAMLparam`, `CAMLlocal`, `CAMLlocalN`, as the
  collector moves young values; an exception skips the C code between it and the OCaml that called it. Cesia's machine
  code holds its values in a block of local roots of that layout around each call into OCaml, and catches every
  exception before it reaches the C.
- The OCaml manual, version 5.5, chapter *Effect handlers*, section *Semantics*. <https://ocaml.org/manual/5.5/effects.html>.
  "It is not possible for an effect to cross a call to caml_callback": why a native that parks a fiber is never called
  from machine code.
- Alfred V. Aho, Monica S. Lam, Ravi Sethi, Jeffrey D. Ullman. *Compilers: Principles, Techniques, and Tools*, 2nd
  edition, Addison-Wesley, 2006, section 9.2.5, *Live-Variable Analysis*. The backward analysis that says which values a
  program reads after a point: those Cesia's machine code keeps as roots around a call into OCaml.

## WebAssembly

- Andreas Haas, Andreas Rossberg, Derek L. Schuff, Ben L. Titzer, Michael Holman, Dan Gohman, Luke Wagner, Alon Zakai,
  JF Bastien. "Bringing the Web up to Speed with WebAssembly". *PLDI 2017*, ACM, 185–200.
  <https://doi.org/10.1145/3062341.3062363>. The design of WebAssembly: a typed code, validated before it runs, compiled
  by the browser. The format that `cesia build --target wasm` writes.
- WebAssembly Community Group. "Wasm 3.0 Completed", 2025. <https://webassembly.org/news/2025-09-17-wasm-3.0/>, and the
  proposal it took in, <https://github.com/WebAssembly/gc>. Garbage collection in WebAssembly: structs, arrays and
  `i31ref` whose memory the engine manages. Cesia's values in a page.
- WebAssembly Community Group. "JavaScript Promise Integration", a proposal of phase 4.
  <https://github.com/WebAssembly/js-promise-integration>, and V8, "Introducing the WebAssembly JavaScript Promise
  Integration API", 2024, <https://v8.dev/blog/jspi>. A call of a module that waits for a promise, its stack set aside:
  the fibers of a page. In Chrome since 137 (<https://developer.chrome.com/release-notes/137>), in Firefox since 153
  (<https://developer.mozilla.org/en-US/docs/Mozilla/Firefox/Releases/153>), in Safari since 27
  (<https://webkit.org/?p=17967>).
- Luna Phipps-Costin, Andreas Rossberg, Arjun Guha, Daan Leijen, Daniel Hillerström, KC Sivaramakrishnan, Matija Pretnar,
  Sam Lindley. "Continuing WebAssembly with Effect Handlers". *Proceedings of the ACM on Programming Languages* 7
  (OOPSLA2), 460–485, 2023. <https://doi.org/10.1145/3622814>. Stack switching, WasmFX: continuations that would be the
  fibers themselves, in no browser without a flag yet.
- WebAssembly Community Group. "WebAssembly JavaScript Interface" and "WebAssembly Web API".
  <https://webassembly.github.io/spec/js-api/> and <https://webassembly.github.io/spec/web-api/>. `WebAssembly.compile`,
  `instantiate`, and `compileStreaming`, which compiles a module while its bytes arrive and takes only a response typed
  `application/wasm`: how a page's loader starts its module.
- Binaryen. <https://github.com/WebAssembly/binaryen>. The optimizer `wasm-opt`, and its pass GUFA, which follows each
  value through a module taken as closed: measured on the page of Ceres, not run by `cesia build`.
- Stefan Krause. js-framework-benchmark. <https://github.com/krausest/js-framework-benchmark>. The same table built by
  each framework of JavaScript, and by Rust's compiled to WebAssembly: the sizes beside the page of Ceres.

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
- ITU-T. Recommendation I.371, "Traffic control and congestion control in B-ISDN", 2004, annex A.
  <https://www.itu.int/rec/T-REC-I.371>. The generic cell rate algorithm, GCRA: one due time a key, a request passing
  no earlier than that time minus its tolerance: [fiber.Admit].
- Scott A. Crosby, Dan S. Wallach. "Denial of Service via Algorithmic Complexity Attacks". *12th USENIX Security
  Symposium*, 29–44, 2003. <https://www.usenix.org/legacy/event/sec03/tech/full_papers/crosby/crosby.pdf>. Keys chosen to
  fall in one bucket of a hash table make each lookup walk them all: why [fiber.Table] hashes its keys with a random seed.

## Memory

- KC Sivaramakrishnan, Stephen Dolan, Leo White, Sadiq Jaffer, Tom Kelly, Anmol Sahoo, Sudha Parimala, Atul Dhiman, Anil
  Madhavapeddy. "Retrofitting Parallelism onto OCaml". *Proceedings of the ACM on Programming Languages* 4(ICFP), article
  113, 2020. <https://doi.org/10.1145/3408995>. The garbage collector of OCaml 5, and its domains: what frees Cesia's
  memory, and what runs the work on whole columns on several cores, and the slow calls of C. A domain that waits still
  takes part in each stop of the world: why the pool of slow calls keeps one only within a burst.
- The OCaml Manual, chapter "Parallel programming". <https://ocaml.org/manual/5.4/parallelism.html>. Domains, their cost
  ("Domains are heavy-weight entities", no more than the cores), and the stop-the-world minor collections they share.

## The server and the network

- John D. C. Little. "A Proof for the Queuing Formula: L = λW". *Operations Research* 9(3), 1961, 383–387.
  <https://doi.org/10.1287/opre.9.3.383>. The requests waiting are the rate times the time each waits: the floor of a
  server's latency at 1,000 connections, whatever its scheduler.
- R. Fielding, M. Nottingham, J. Reschke (editors). "HTTP Semantics", RFC 9110, 2022.
  <https://www.rfc-editor.org/rfc/rfc9110>, and "HTTP/1.1", RFC 9112, 2022. <https://www.rfc-editor.org/rfc/rfc9112>.
  Methods, statuses, headers, persistent connections: [std/http].
- A. Barth. "The Web Origin Concept", RFC 6454, 2011. <https://www.rfc-editor.org/rfc/rfc6454>. The `Origin` header,
  scheme, host and port, its host in ASCII: what [http.SameOrigin] compares with the `Host`.
- W3C. "Fetch Metadata Request Headers", Working Draft. <https://www.w3.org/TR/fetch-metadata/>. The `Sec-Fetch-Site`
  header, which no page can set; F. Valsorda. "Cross-Site Request Forgery", 13 August 2025.
  <https://words.filippo.io/csrf/>, and Go's `net/http.CrossOriginProtection`, Go 1.25.
  <https://pkg.go.dev/net/http#CrossOriginProtection>. The steps of [http.SameOrigin], and their limit with the scheme.
- J. Iyengar, M. Thomson (editors). "QUIC: A UDP-Based Multiplexed and Secure Transport", RFC 9000, 2021.
  <https://www.rfc-editor.org/rfc/rfc9000>; M. Thomson, S. Turner. "Using TLS to Secure QUIC", RFC 9001, 2021.
  <https://www.rfc-editor.org/rfc/rfc9001>. Streams, Retry, NEW_TOKEN and the limit of 3 times before an address is
  proved (section 8), migration (section 9), 0-RTT (RFC 9001, section 4.6): [std/quic], on ngtcp2 (T. Tsujikawa and
  others, <https://github.com/ngtcp2/ngtcp2>, MIT licence), its TLS by OpenSSL's QUIC TLS API (OpenSSL 3.5).
- E. Rescorla. "The Transport Layer Security (TLS) Protocol Version 1.3", RFC 8446, 2018.
  <https://www.rfc-editor.org/rfc/rfc8446>, section 8 (0-RTT and anti-replay: single-use tickets). Why each ticket of
  [std/quic] serves once.
- J. Iyengar, I. Swett (editors). "QUIC Loss Detection and Congestion Control", RFC 9002, 2021.
  <https://www.rfc-editor.org/rfc/rfc9002>; L. Xu, S. Ha, I. Rhee, V. Goel, L. Eggert. "CUBIC for Fast and
  Long-Distance Networks", RFC 9438, 2023. <https://www.rfc-editor.org/rfc/rfc9438>; N. Cardwell, Y. Cheng, C. S. Gunn,
  S. H. Yeganeh, V. Jacobson. "BBR: Congestion-Based Congestion Control", ACM Queue 14(5), 2016; N. Cardwell, I.
  Swett, J. Beshay (editors). "BBR Congestion Control", draft-ietf-ccwg-bbr. <https://datatracker.ietf.org/doc/draft-ietf-ccwg-bbr/>
  (BBR version 3, ngtcp2's). The congestion controls that [What it costs](http.md#what-it-costs-1) compares: OpenSSL
  4.1's NewReno (`ssl/quic/cc_newreno.c`, <https://github.com/openssl/openssl>) and ngtcp2 1.26's Reno, CUBIC and BBR
  (`lib/ngtcp2_cc.c`, `lib/ngtcp2_bbr.c`, <https://github.com/ngtcp2/ngtcp2>); BBR is the default of [std/http3].
- M. Bishop (editor). "HTTP/3", RFC 9114, 2022. <https://www.rfc-editor.org/rfc/rfc9114>; C. Krasic, M. Bishop,
  A. Frindell. "QPACK: Field Compression for HTTP/3", RFC 9204, 2022. <https://www.rfc-editor.org/rfc/rfc9204>, whose
  Huffman code is HPACK's, R. Peon, H. Ruellan, RFC 7541, 2015, appendix B. <https://www.rfc-editor.org/rfc/rfc7541>:
  [std/http3].
- M. Nottingham, P. McManus, J. Reschke. "HTTP Alternative Services", RFC 7838, 2016.
  <https://www.rfc-editor.org/rfc/rfc7838>; B. Schwartz, M. Bishop, E. Nygren. "Service Binding and Parameter
  Specification via the DNS (SVCB and HTTPS Resource Records)", RFC 9460, 2023. <https://www.rfc-editor.org/rfc/rfc9460>.
  How a browser finds HTTP/3.
- M. Thomson, M. Nottingham, W. Tarreau. "Using Early Data in HTTP", RFC 8470, 2018.
  <https://www.rfc-editor.org/rfc/rfc8470>. The 425 of [http.Serve].
- A. Frindell, E. Kinnear, V. Vasiliev. "WebTransport over HTTP/3", draft-ietf-webtrans-http3.
  <https://datatracker.ietf.org/doc/draft-ietf-webtrans-http3/>; R. Hamilton. "Bootstrapping WebSockets with HTTP/3",
  RFC 9220, 2022 (extended CONNECT); D. Schinazi, L. Pardue. "HTTP Datagrams and the Capsule Protocol", RFC 9297,
  2022; T. Pauly, E. Kinnear, D. Schinazi. "An Unreliable Datagram Extension to QUIC", RFC 9221, 2022. The sessions of
  [std/live] over HTTP/3.
- D. Schinazi, T. Pauly. "Happy Eyeballs Version 2: Better Connectivity Using Concurrency", RFC 8305, 2017.
  <https://www.rfc-editor.org/rfc/rfc8305>. The race of WebTransport and WebSocket in `live.js`.
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
- Maxime Crochemore, Dominique Perrin. "Two-way string-matching". *Journal of the ACM* 38(3):650–674, 1991.
  <https://doi.org/10.1145/116825.116845>. A search in time linear in the text, with a few words of memory whatever the
  part: the part is cut at its *critical factorization*, a place found from its two maximal suffixes, and each window is
  compared right piece first, then left piece, shifting by the part's period, the smallest shift at which
  it lies on itself. [text.ByteFind] and the other searches of
  [std/text] for a part of 32 bytes or more, as glibc's `memmem` and Rust's `str::find`.
- Ulf Adams. "Ryū: fast float-to-string conversion". *PLDI 2018*, ACM, 270–282.
  <https://doi.org/10.1145/3192366.3192369>. A float and the bounds of the decimals that read back to it, scaled to a
  power of 10 at once by products with 126-bit powers of 5 from a table: the text of every float Cesia writes, in the bytes
  C's `printf` gave it before, 15 to 35 times faster.
- William D. Clinger. "How to Read Floating Point Numbers Accurately". *PLDI 1990*, ACM, 92–101.
  <https://doi.org/10.1145/93542.93557>. A decimal of at most 15 digits times or divided by a power of ten that a double
  holds exactly, $10^{22}$ at most, is one correctly rounded operation of IEEE 754, and so the nearest double: how
  [json.Parse] reads most numbers without the general conversion.
- T. Bray (editor). "The JavaScript Object Notation (JSON) Data Interchange Format", RFC 8259, 2017.
  <https://www.rfc-editor.org/rfc/rfc8259>. [std/json].
- Y. Shafranovich. "Common Format and MIME Type for Comma-Separated Values (CSV) Files", RFC 4180, 2005.
  <https://www.rfc-editor.org/rfc/rfc4180>. [std/csv] and the CSV of [std/frame].
- C. Bormann, P. Hoffman. "Concise Binary Object Representation (CBOR)", RFC 8949, STD 94, 2020.
  <https://www.rfc-editor.org/rfc/rfc8949>. [std/cbor]: its examples of appendix A are checked both ways in
  `tests/lang/cbor.ce`, and its floats of 16 bits are read as appendix D does. FIDO Alliance. "Client to Authenticator
  Protocol (CTAP)", 2.1, 2021, section 8, "Message Encoding".
  <https://fidoalliance.org/specs/fido-v2.1-ps-20210615/fido-client-to-authenticator-protocol-v2.1-ps-20210615.html>.
  CTAP2's canonical CBOR, the order of the keys of a map that [cbor.Encode] writes, and no indefinite lengths.
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
- Jonathan Richard Shewchuk. "Adaptive Precision Floating-Point Arithmetic and Fast Robust Geometric Predicates".
  *Discrete & Computational Geometry* 18(3):305–363, 1997. <https://doi.org/10.1007/PL00009321>. The exact sum of
  floats whose sign decides the few cases of [math.Cbrt] near the middle of two floats.
- Pierre Blanchard, Desmond J. Higham, Nicholas J. Higham. "Accurately computing the log-sum-exp and softmax functions".
  *IMA Journal of Numerical Analysis* 41(4), 2021. The largest term first, then `log1p` of the others: [math.LogSumExp].
- Charles F. F. Karney. "Algorithms for geodesics". *Journal of Geodesy* 87(1):43–55, 2013.
  <https://doi.org/10.1007/s00190-012-0578-z>. The exact reduction of an angle in degrees of [math.SinDegrees],
  [math.CosDegrees] and [math.TanDegrees].
- Peter J. Mohr, David B. Newell, Barry N. Taylor, Eite Tiesinga. *CODATA Recommended Values of the Fundamental Physical
  Constants: 2022*. NIST, 2024. <https://physics.nist.gov/cuu/Constants/>. The 355 constants of [std/constants].

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

[std/crypto] calls libsodium, <https://doc.libsodium.org/>, and OpenSSL's libcrypto, <https://docs.openssl.org/3.0/>,
and writes no primitive itself. The algorithms behind its functions, and the formats of their keys:

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
  <https://www.rfc-editor.org/rfc/rfc2104>. [crypto.HmacSha256] and [crypto.HmacSha1].
- Mihir Bellare. "New Proofs for NMAC and HMAC: Security without Collision-Resistance". *CRYPTO 2006*, LNCS 4117,
  602–619. <https://doi.org/10.1007/11818175_36>. HMAC is a pseudorandom function as soon as the compression function of
  its hash is one, collisions or not: why the HMAC-SHA-1 of TOTP stands while SHA-1 is broken for signatures.
- P. Cheng, R. Glenn. "Test Cases for HMAC-MD5 and HMAC-SHA-1", RFC 2202, 1997. <https://www.rfc-editor.org/rfc/rfc2202>.
  The seven cases that `tests/crypto/openssl.ce` checks [crypto.HmacSha1] with.
- D. M'Raihi, S. Machani, M. Pei, J. Rydell. "TOTP: Time-Based One-Time Password Algorithm", RFC 6238, 2011.
  <https://www.rfc-editor.org/rfc/rfc6238>. The codes of authenticator apps, HMAC-SHA-1 of the count of 30 seconds: its
  appendix B, the SHA-1 column, is checked in `tests/crypto/openssl.ce`.
- K. Moriarty, B. Kaliski, J. Jonsson, A. Rusch. "PKCS #1: RSA Cryptography Specifications Version 2.2", RFC 8017, 2016.
  <https://www.rfc-editor.org/rfc/rfc8017>. RSASSA-PKCS1-v1_5 and RSASSA-PSS with MGF1, the RS256 and PS256 of
  [crypto.VerifyWith], and the RSAPublicKey that [crypto.RsaKey] writes.
- NIST. "Digital Signature Standard (DSS)", FIPS 186-5, 2023. <https://doi.org/10.6028/NIST.FIPS.186-5>, and
  "Recommendations for Discrete Logarithm-based Cryptography: Elliptic Curve Domain Parameters", SP 800-186, 2023.
  <https://doi.org/10.6028/NIST.SP.800-186>. ECDSA, and the curve P-256 of ES256.
- M. Jones, J. Bradley, N. Sakimura. "JSON Web Signature (JWS)", RFC 7515, 2015. <https://www.rfc-editor.org/rfc/rfc7515>,
  and M. Jones. "JSON Web Algorithms (JWA)", RFC 7518, 2015. <https://www.rfc-editor.org/rfc/rfc7518>. The names RS256,
  PS256 and ES256, the salt of PS256, the 64 bytes r and s of [crypto.EcdsaDer] and [crypto.EcdsaRaw]; the JWS of
  appendices A.2 and A.3, checked byte for byte in `tests/crypto/openssl.ce`.
- M. Jones. "Using RSA Algorithms with CBOR Object Signing and Encryption (COSE) Messages", RFC 8230, 2017.
  <https://www.rfc-editor.org/rfc/rfc8230>, and J. Schaad. "CBOR Object Signing and Encryption (COSE): Initial
  Algorithms", RFC 9053, 2022. <https://www.rfc-editor.org/rfc/rfc9053>. The keys of passkeys: the n and e, the x and
  y that [crypto.RsaKey] and [crypto.EcKey] take.
- S. Turner, D. Brown, K. Yiu, R. Housley, T. Polk. "Elliptic Curve Cryptography Subject Public Key Information", RFC
  5480, 2009. <https://www.rfc-editor.org/rfc/rfc5480>, and B. Kaliski. "Public-Key Cryptography Standards (PKCS) #8:
  Private-Key Information Syntax Specification Version 1.2", RFC 5208, 2008. <https://www.rfc-editor.org/rfc/rfc5208>.
  The DER of the keys of [crypto.KeyPair].

## Editors

- Microsoft. Language Server Protocol Specification 3.17.
  <https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/>. What `cesia lsp` speaks,
  positions counted in UTF-16 code units as it says: see [Editors](editors.md).
