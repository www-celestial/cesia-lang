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
  keys, in [How Cesia works](internals.md#maps-a-hash-trie).
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
- IEEE. "IEEE Standard for Floating-Point Arithmetic", IEEE Std 754-2019, 2019.
  <https://doi.org/10.1109/IEEESTD.2019.8766229>. The 64-bit floats of Cesia, their rounding, their infinities and NaN.

## The interpreter

- Peter J. Landin. "The Mechanical Evaluation of Expressions". *The Computer Journal* 6(4):308–320, 1964.
  <https://doi.org/10.1093/comjnl/6.4.308>. The closure, a function with the environment it was made in.
- Marc Feeley, Guy Lapalme. "Using Closures for Code Generation". *Computer Languages* 12(1):47–66, 1987.
  <https://doi.org/10.1016/0096-0551(87)90012-9>. A syntax tree compiled into closures that run it, faster than walking the
  tree: Cesia's interpreter, `src/lib/compile.ml`.

## The JIT

- Craig Chambers, David Ungar. "Customization: Optimizing Compiler Technology for SELF, a Dynamically-Typed
  Object-Oriented Programming Language". *PLDI 1989*, 146–160. <https://doi.org/10.1145/73141.74831>. A function compiled
  once per kind of its arguments: Cesia's versions, one per tuple of argument types.
- Craig Chambers, David Ungar, Elgin Lee. "An Efficient Implementation of SELF, a Dynamically-Typed Object-Oriented
  Language Based on Prototypes". *OOPSLA 1989*, 49–70. <https://doi.org/10.1145/74877.74884>. *Maps*, which V8 later called
  hidden classes: the layout of an object shared by all objects of its shape. Cesia's shapes of structs and shared keys of
  small maps.
- Urs Hölzle, Craig Chambers, David Ungar. "Optimizing Dynamically-Typed Object-Oriented Languages With Polymorphic Inline
  Caches". *ECOOP 1991*, LNCS 512, 21–38. <https://doi.org/10.1007/BFb0057013>. Inline caches at each site of the code;
  Cesia's keep the last shape met, the monomorphic kind this paper starts from.
- Urs Hölzle, Craig Chambers, David Ungar. "Debugging Optimized Code with Dynamic Deoptimization". *PLDI 1992*, 32–43.
  <https://doi.org/10.1145/143095.143114>. Leaving optimized code for the interpreter, with the state rebuilt: Cesia's
  bails.
- Urs Hölzle, David Ungar. "Optimizing Dynamically-Dispatched Calls with Run-Time Type Feedback". *PLDI 1994*, 326–336.
  <https://doi.org/10.1145/178243.178478>. Compiling for the types really met while the program ran: the guesses that
  Cesia's JIT takes from the frame.
- Andreas Gal and others. "Trace-based Just-in-Time Type Specialization for Dynamic Languages". *PLDI 2009*, 465–478.
  <https://doi.org/10.1145/1542476.1542528>. The tracing JIT, which compiles one hot path through the program. Cesia
  compiles whole functions and loops instead, with guards, which keeps its speed steady on code full of branches.
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
- Joe Armstrong. "A History of Erlang". *HOPL III*, ACM, 2007. <https://doi.org/10.1145/1238844.1238850>. Processes switched
  after a count of reductions, supervisors that start a failed process again, and code replaced while it runs: Cesia's
  checkpoints every million steps, the supervisor of `--workers`, and `--watch`.

## Memory

- KC Sivaramakrishnan, Stephen Dolan, Leo White, Sadiq Jaffer, Tom Kelly, Anmol Sahoo, Sudha Parimala, Atul Dhiman, Anil
  Madhavapeddy. "Retrofitting Parallelism onto OCaml". *Proceedings of the ACM on Programming Languages* 4(ICFP), article
  113, 2020. <https://doi.org/10.1145/3408995>. The garbage collector of OCaml 5, and its domains: what frees Cesia's
  memory, and what runs the work on whole columns on several cores.

## The server and the network

- R. Fielding, M. Nottingham, J. Reschke (editors). "HTTP Semantics", RFC 9110, 2022.
  <https://www.rfc-editor.org/rfc/rfc9110>, and "HTTP/1.1", RFC 9112, 2022. <https://www.rfc-editor.org/rfc/rfc9112>.
  Methods, statuses, headers, persistent connections: [std/http].
- I. Fette, A. Melnikov. "The WebSocket Protocol", RFC 6455, 2011. <https://www.rfc-editor.org/rfc/rfc6455>. The server
  side of [std/websocket].
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
