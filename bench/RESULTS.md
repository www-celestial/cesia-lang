# Measurements

i7-4720HQ, OCaml 5.5.0 without flambda, `release` profile, best of 3, one process at a time.
Python 3.14.7, Lua 5.5.1. Outputs checked to 6 decimals by `tools/bench.sh`.

## Benchmarks, 2026-11-01

| Benchmark | Kepler | Python | Times Python | Lua | Times Lua | Target | Met |
|---|---:|---:|---:|---:|---:|---|---|
| fib | 445 ms | 1468 ms | 3.30 | 692 ms | 0.64 | at least 3 times Python, at most 1.3 times Lua | yes |
| mandel | 463 ms | 2613 ms | 5.64 | 434 ms | 1.07 | same | yes |
| structs | 582 ms | 1764 ms | 3.03 | 1483 ms | 0.39 | same | yes, 1% margin |
| matmul | 977 ms | 4901 ms | 5.02 | 852 ms | 1.15 | same | yes |
| dyn | 639 ms | 1416 ms | 2.22 | 715 ms | 0.89 | at least 2 times Python | yes |

| Criterion | Target | Measured | Met |
|---|---|---|---|
| `print(1)`, measurement included | under 5 ms | 3.9 ms, of which 1.2 ms of measurement | yes |
| Loading, resolution included | at least 500,000 lines/s | 505,530 lines/s | yes, 1% margin |
| A `.ml` in `src/` rebuilt and tested, `dev` profile | under 5 s | 3.5 s (`tools/check.sh`) | yes |
| A Kepler function active in a running program | under 100 ms | 12 ms (`tools/reload_test.sh`) | yes |
| Tests on both paths | all | 137 + 3 + 8 tests, golden 102/102, on each path | yes |
| `tools/check.sh` | passes | yes, 7,325 lines of 15,000 | yes |
| 10-minute fuzz, seed 2026 | no internal error | 391,884 trials, 42,319 ran to the end, 0 failures | yes |

Two margins of 1%: `structs` and loading pass, but code placement moves timings by 5% from one build to the next. Another
build can put them below the target.

Not verified: `wasm_of_ocaml` is not installed on this PC, so `src/` has not been compiled to wasm. Windows and macOS are
unverified until there is a repository with GitHub Actions.

Close to the depth limit, the cost stays low: a loop of 3 million calls takes 96 ms at depth 10, 103 ms at 9,900 and
132 ms at 9,990, for a limit of 10,000.

## Async runtime and `sys`, 2026-11-01

Same PC and build, best of 7. `Core` is the commit before this work, rebuilt and run in turn with the current tree, best
of 9, so that both met the same machine. That machine was slower than for the table above: the same Python and Lua
programs took up to 9% longer.

| Benchmark | Kepler | Python | Times Python | Lua | Times Lua | Core, in turn | Current, in turn | Drift |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fib | 453 ms | 1473 ms | 3.25 | 695 ms | 0.65 | 441 ms | 453 ms | +2.6% |
| mandel | 460 ms | 2652 ms | 5.77 | 435 ms | 1.06 | 455 ms | 463 ms | +1.7% |
| structs | 584 ms | 1771 ms | 3.03 | 1506 ms | 0.39 | 590 ms | 578 ms | -1.9% |
| matmul | 1030 ms | 5364 ms | 5.21 | 909 ms | 1.13 | 961 ms | 1020 ms | +6.2% |
| dyn | 716 ms | 1509 ms | 2.11 | 714 ms | 1.00 | 649 ms | 698 ms | +7.5% |

| Criterion | Target | Measured | Met |
|---|---|---|---|
| `http.serve`, 10 connections | at least Node | 56,688 req/s, Node 28,969 | yes |
| `http.serve`, 100 connections | at least Node | 52,156 req/s, Node 30,041 | yes |
| `http.serve`, 1,000 connections | at least Node | 31,592 req/s, Node 26,918 | yes |
| `http.serve`, 10 active and 900 idle | at least Node | 57,883 req/s, Node 30,758 | yes |
| 20,000 open connections | held | held, 33,775 req/s (`tools/http_bench.sh`) | yes |
| Memory per parked fiber | under 8 KB | 3.49 KB (`tools/fiber_size.sh`) | yes |
| The five benchmarks against Python and Lua | the targets above | all met, `structs` with a 1% margin | yes |
| The five benchmarks against the core | within 2% | `mandel` and `structs` yes, `fib` +2.6%, `matmul` +6.2%, `dyn` +7.5% | no |
| Loading, resolution included | at least 500,000 lines/s | 451,341 to 470,589 lines/s; core commit in turn 463,769 | no |
| `print(1)`, measurement included | under 5 ms | 3.6 ms, of which 0.5 ms of measurement | yes |
| A Kepler function active in a running program | under 100 ms | 12 to 19 ms (`tools/reload_test.sh`) | yes |
| Tests on both paths | all | 199 + 3 + 22 tests, golden 162/162, on each path | yes |
| No `try` | none | none in `std/` or the programs; `tests/errors/try_gone` checks it is rejected | yes |
| Each function under a permission | denied, granted, out of scope | 11 functions, `tests/sys/permissions_*` | yes |
| `tools/check.sh` | passes | yes, 8,506 lines of 15,000, change loop in 4.1 s | yes |
| 10-minute fuzz, seed 2026 | no internal error | 171,518 trials, 10,008 ran to the end, 0 failures | yes |

### Why three benchmarks drift

No operation got slower, and none of these benchmarks runs a line of `sys/`. What moved is the code.

- `matmul` has two states, near 950 ms and near 1015 ms, chosen by where the closures land. Unused functions inserted
  between closures give 941 to 1014 ms on the core commit, and 948 to 1026 ms now: the same range.
- `dyn` and `fib` keep their gap under that padding: 642 to 672 ms against 690 to 713 ms, and 442 to 446 ms against 451
  to 457 ms. The current tree built without `sys/` in the binary falls to +2.6% for `dyn` and +1.2% for `fib`. Most of the
  gap therefore comes from the C runtime, 345 KB further away: padding that moves only the runtime takes `dyn` from 683
  to 712 ms.
- The value type's new `Handle` constructor costs nothing: the core commit with it alone gives 646 ms on `dyn`, for 643 ms.
- The noise reaches the size of the target: an addition on mixed types gave 662 ms, then 739 ms, on one binary of the core
  commit. A single build can't answer a 2% question; comparing two trees under padding can.

Padding until a good layout appears would only hold until the next change, so none was kept.

### Loading and HTTP

Loading is not a regression: the core commit itself gives 463,769 lines/s in turn with the current tree, where it gave
505,530 on an earlier day. The 1% margin noted above did not survive a slower machine.

The first measure of `http.serve` gave 66,191, 60,363, 33,924 and 65,167 req/s for the four loads above. The last fixes
added header checks and the closing rule, on a slower machine, and the two causes were not separated.

Not verified: `kqueue` and IOCP are not written. The `select` backend passed the 22 tests of its suite on Linux, in a copy.

## C interop and window, 2026-11-01

Same PC and build, best of 7. `Previous` is the commit before this work, rebuilt outside the repository from `git archive
HEAD` and run in turn with the current tree, best of 9. Everything here is Linux on x86-64.

| Benchmark | Kepler | Python | Times Python | Lua | Times Lua | Previous, in turn | Current, in turn | Drift |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| fib | 442 ms | 1449 ms | 3.28 | 682 ms | 0.65 | 448 ms | 441 ms | -1.6% |
| mandel | 453 ms | 2579 ms | 5.69 | 427 ms | 1.06 | 454 ms | 454 ms | 0.0% |
| structs | 543 ms | 1724 ms | 3.17 | 1452 ms | 0.37 | 547 ms | 544 ms | -0.5% |
| matmul | 946 ms | 4576 ms | 4.84 | 820 ms | 1.15 | 944 ms | 940 ms | -0.4% |
| dyn | 674 ms | 1401 ms | 2.08 | 706 ms | 0.95 | 691 ms | 673 ms | -2.6% |

| Criterion | Target | Measured | Met |
|---|---|---|---|
| The speed gate, `bench/frame.kp`, real window | at least 60 frames/s | 148, 144, 151; 146 with `--no-spec` | yes |
| A call to a trivial C function, `bench/ccall.kp` | at least 5 million/s | 12.9 million/s; 11.9 with `--no-spec` | yes |
| The five benchmarks against Python and Lua | the targets above | all met, `dyn` with a 4% margin | yes |
| The five benchmarks against the previous commit | reported | -2.6% to 0.0% | reported |
| Loading, resolution included | at least 500,000 lines/s | 505,530 lines/s; in turn, previous 509,555, current 507,133 | yes, 1% margin |
| `print(1)`, measurement included | under 5 ms | 3.6 to 3.7 ms, of which 0.7 ms of measurement | yes |
| A `.ml` in `src/` rebuilt and tested, `dev` profile | under 5 s | 3.9 s (`tools/check.sh`) | yes |
| A Kepler function active in a running program | under 100 ms | 17 ms (`tools/reload_test.sh`) | yes |
| Tests on both paths | all | 199 + 3 + 22 tests, golden 197/197, on each path | yes |
| Every call shape | 254 | 254 (`tests/c/shapes`) | yes |
| The demo in a real window | typing shows text, closing exits with 0 | opened under Wayland, and a quit event from SIGTERM exits with 0 | typing and the close button unverified |
| `tools/check.sh` | passes, hand-written C under 100 lines | yes, 8,890 lines of 15,000, 80 lines of C | yes |
| 10-minute fuzz, seed 2026 | no internal error | 189,304 trials, 9,251 ran to the end, 0 failures | yes |

### What the fuzzer found

The first 10-minute run gave 158,532 trials and 11 failures, all one program: a mutant of `tests/c/block_cycle` that ran
past the 10 s alarm. It wasn't a crash. `c.alloc` paid no steps, so the steps limit took 21.5 s to stop a loop that `zeros`
of the same size stops in 0.02 s. Two other natives of `c` had the same fault, without any permission: a long name reached
the zero-byte scan unpaid, 250 times the cost of a normal turn, and `c.fn` read every type before counting them, over 2,600
times. All three are fixed, each with a test seen failing first. The result in the table is the run after these fixes.

### The frame and the binary layout

The gate gave 164, 151 and 160 frames/s when first measured, and 148, 144 and 151 at closing. Text objects moved into a
shared block in between, and the two causes, that change and the machine, were not separated. A frame takes 6.6 ms of the
16.7 ms it has.

The 254 generated C functions did not cost what the last sub-project's runtime did: all five benchmarks stay within the 5%
that code placement moves from one build to the next.

Not verified: macOS, Windows and arm64, so five of the six targets of the calling conventions. Only this PC's GPU and
Wayland session ran the gate. Real typing and the close button need a person at the window.

## Project file, 2026-11-01

| Criterion | Target | Measured | Met |
|---|---|---|---|
| This repository's `kepler.toml` | `build`, `test`, `check`, `demo` work | all exit 0; `demo` in a real window, stopped through `kepler do` | yes |
| Tests on both paths | all | golden 217/217, `toml_test` ok | yes |
| `tools/check.sh` | passes | yes, 9,451 lines of 15,000 | yes |
| A `.ml` in `src/` rebuilt and tested | under 5 s | 4.2 to 4.7 s | yes, thin margin |
| `print(1)`, measurement included | under 5 ms | 3.9 to 4.6 ms, of which 0.6 to 0.9 ms of measurement | yes |
| `kepler do` listing this repository | under 10 ms | 3.9 to 4.2 ms | yes |
| The reader against Python's `tomllib` | the same values | 20,032 inputs, 2,651 accepted, 0 differences | yes |
| 10-minute fuzz, seed 2026 | no failure | 184,345 trials, 7,465 toml accepted, 0 failures | yes |

Not verified: `kepler do` on macOS and Windows.

## Standard library, interop, web and crypto, 2026-11-01

Same PC, best of 7, on the final tree. A system upgrade on that day kept OCaml 5.5.0 and dune 3.24.2, and moved glibc,
OpenSSL 3.6.5, SDL3 3.4.18, Python 3.14.9 and Node 26.13.0, so the references are not those of the tables above. Node
above all: 28,969 req/s at 10 connections before the upgrade, 45,590 after. `Previous` is the last commit, rebuilt outside
the repository from `git archive HEAD` and run in turn with the current tree.

| Benchmark | Kepler | Python | Times Python | Lua | Times Lua | Target | Met |
|---|---:|---:|---:|---:|---:|---|---|
| fib | 462 ms | 1493 ms | 3.23 | 700 ms | 0.66 | at least 3 times Python, at most 1.3 times Lua | yes |
| mandel | 465 ms | 2653 ms | 5.71 | 436 ms | 1.07 | same | yes |
| structs | 576 ms | 1816 ms | 3.15 | 1517 ms | 0.38 | same | yes |
| matmul | 957 ms | 5299 ms | 5.54 | 872 ms | 1.10 | same | yes |
| dyn | 694 ms | 1435 ms | 2.07 | 724 ms | 0.96 | at least 2 times Python | yes, 3% margin |

An earlier build of the same day gave 714 ms on `dyn`, 2.00 times Python: the 5% of code placement can take it to the
target.

| Criterion | Target | Measured | Met |
|---|---|---|---|
| `http.serve`, 10 connections | at least Node | 61,178 req/s, Node 43,547 | yes |
| `http.serve`, 100 connections | at least Node | 52,998 req/s, Node 45,295 | yes |
| `http.serve`, 1,000 connections | at least Node | 31,869 req/s, Node 38,025 | no |
| `http.serve`, 10 active and 900 idle | at least Node | 58,962 req/s, Node 42,985 | yes |
| 20,000 open connections | held | held, 33,725 req/s | yes |
| Memory per parked fiber | under 8 KB | 3.43 KB | yes |
| The speed gate, `bench/frame.kp`, real window | at least 60 frames/s | 154, 154, 159; 167 with `--no-spec` | yes |
| A call to a trivial C function, `bench/ccall.kp` | at least 5 million/s | 12.7 million/s; 11.3 with `--no-spec` | yes |
| Loading, resolution included | at least 500,000 lines/s | 471,282 to 499,221 lines/s; previous commit in turn 483,623 | no |
| `print(1)`, measurement included | under 5 ms | 4.36 ms on average, of which 0.49 ms of measurement | yes |
| `kepler do` listing this repository | under 10 ms | 3.48 ms | yes |
| A `.ml` in `src/` rebuilt and tested, `dev` profile | under 5 s | 4.3 to 4.4 s (`tools/check.sh`) | yes, thin margin |
| A Kepler function active in a running program | under 100 ms | 14 ms (`tools/reload_test.sh`) | yes |
| Tests on both paths | all | 499 + 3 + 22 tests, golden 245/245, and 219/219 with `--no-spec` | yes |
| `tools/check.sh` | passes | yes, 11,187 lines of 15,000, 235 lines of C of 300 | yes |
| 10-minute fuzz, seed 20261103 | no internal error | 190,695 trials, 11,649 ran to the end, 7,719 toml accepted, 0 failures | yes |

`--no-spec` leaves out `tests/project`, `tests/cpp`, `tests/crypto` and `tests/tls`, where it changes nothing.

### HTTP

`http.serve` had lost 20% when this work ended: 51,377 req/s against 64,490 for the previous commit at 10 connections, in
turn on one machine, and 28,624 against 34,846 at 1,000. The old `std/http.kp` on the current binary gave 66,578, so the
loss was all in that file, not in the engine.

| Taken out of the module, one at a time | µs per request |
|---|---:|
| Nothing | 18.9 |
| The strict header check | 17.0 |
| The checks on the body | 18.5 |
| The `io` closures that let TLS sit under HTTP | 18.6 |
| `net.arm` at each request, the reaper, named arguments | no change |

The strict check called a Kepler closure per byte and built two arrays per header. `net.is_header` now does it in one pass,
with the same rules, and header lookups are loops without a closure. `parse_request` went from 4.4 to 2.9 µs, under the 3.4
of the previous commit, and `tests/net/header_bytes` checks all 256 bytes against RFC 9110.

With the cleanup below, the result in turn is 60,728 against 64,048 req/s, and 33,104 against 33,874: 5% and 2% remain. They
sit in what requests now pay for: the `io` closures, HEAD and upgrades.

The miss at 1,000 connections is new because Node moved: the previous commit gives 33,874 req/s against Node's 38,025. Why
`http.serve` falls from 53,000 to 31,900 req/s between 100 and 1,000 connections has not been investigated.

### Loading

Loading is not a regression of this work: the previous commit gives 483,623 lines/s in turn. The 1% margin noted earlier
did not survive this machine. `bench/load.sh` had failed since `defn` replaced `function`, and now writes `defn`.

### The change loop

`tools/check.sh` had gone to 5.8 s with the review's tests, unseen because it stopped earlier on a forbidden word. A costly
model in the rope test and fixed waits in the others account for it. Each of the four tests that changed their numbers was
seen failing again with its defect put back: no pause after a failed `accept`, no `io.arm(idle)`, no `Runtime.reserve`, a
leaf merge that loses lines. `sleep_huge`, `flush_idle` and `stop` only wait less, and were not run with a defect.

### The fuzz

Three runs came to 0 failures: seed 20261101 gave 186,126 trials and seed 20261102 gave 194,927, before the cleanup, and
seed 20261103 gave the line in the table, on the final tree. A first run with seed 2026 was lost at about 498 s: the PC went off with its GPU at 95 °C
while Steam was looping, and went off the same way 10 minutes later without the fuzzer. No failure had been saved.

### The cleanup

Four reviews read the whole work for copies, needless complexity, waste and fixes at the wrong depth. The old and new library
print the same 101 lines on awkward inputs. Old and new binaries need the same 200,120 steps on a mix of natives, and 30 more
turns of a loop give 200,150, so the comparison sees small differences.

| Work, on the old and the new tree | Before | After |
|---|---:|---:|
| `csv.parse`, 20,000 rows | 3,827 ms | 182 ms |
| `rope.text`, 6 MB | 545 ms | 12 ms |
| `http.get`, 8 MB | 397 ms | 48 ms |
| `http.get`, 2 MB in chunks | 293 ms | 39 ms |
| `algo.permutations` of 7 | 253 ms | 12 ms |
| `heap.items`, 5,000 items | 231 ms | 29 ms |
| 4,000 `push` | 124 ms | 86 ms |

Two results moved. A chunked response cut right after a chunk's data made the client panic, and is now an `Err`:
`tests/net/http_chunk_cut` was seen failing on the old library. `join_on` on a key column of `missing` or booleans still
panics, with the message of `order` instead of the dictionary's.

Not verified: macOS, Windows and arm64. `.github/workflows/ci.yml` is written and has never run, as there is no remote.

## Heavy computing, 2026-11-01

Same PC, `release` profile, on the final tree, one run of each. It has 4 cores and 8 threads, and Kepler uses 4 by default.
NumPy, pandas, Julia, R and OpenBLAS are not installed here, so nothing below is compared with them.

| Work | Before | After |
|---|---:|---:|
| `frame.group_by`, 1 million rows, 1,000 groups | 1,117 ms | 79 ms, with two aggregations |
| `frame.sort_by`, 1 million floats | 985 ms | 242 ms |
| `frame.sort_by`, 1 million integers | not measured | 234 ms |
| `frame.where_column`, 1 million rows | 62 ms | 62 ms |
| `frame.where_mask`, 1 million rows | new | 16 ms |
| `frame.join_on`, 1 million rows with 1,000 | not measured | 96 ms |
| `frame.from_csv`, 200,000 rows | not measured | 114 ms |
| `frame.to_csv`, 200,000 rows | not measured | 525 ms |
| `matmul`, 1,000 by 1,000, OCaml on 4 cores | 2,003 ms | 566 ms |
| `num.solve`, 1,000 by 1,000, reference LAPACK | not measured | 207 ms |
| `num.qr`, 1,000 by 1,000, reference LAPACK | not measured | 1,047 ms |
| `num.eigen`, 1,000 by 1,000, reference LAPACK | not measured | 2,170 ms |
| `sum`, 5 million floats | 13 ms | 4 ms |
| `sin`, 5 million floats | 88 ms | 29 ms |

The reference BLAS gives `matmul` in 738 ms on one core, which is why only a fast BLAS gets it: OpenBLAS, Accelerate, or a
library named in `KEPLER_BLAS`. Elementwise `+` and `*` gain nothing from more cores here: 5 million cells take 25 to 34 ms
with 1, 4 or 8 cores, as the limit is the memory. 8 threads gain nothing over 4 on floats.

| Benchmark | Kepler | Python | Times Python | Lua | Times Lua | Target | Met |
|---|---:|---:|---:|---:|---:|---|---|
| fib | 469 ms | 1490 ms | 3.18 | 698 ms | 0.67 | at least 3 times Python, at most 1.3 times Lua | yes |
| mandel | 481 ms | 2659 ms | 5.53 | 437 ms | 1.10 | same | yes |
| structs | 580 ms | 1808 ms | 3.12 | 1520 ms | 0.38 | same | yes |
| matmul | 961 ms | 5196 ms | 5.41 | 864 ms | 1.11 | same | yes |
| dyn | 674 ms | 1429 ms | 2.12 | 722 ms | 0.93 | at least 2 times Python | yes |

The third storage cost nothing visible: from the table of the section above, the five move by -2.9% to +3.4%, within the 5%
of code placement.

| Criterion | Target | Measured | Met |
|---|---|---|---|
| `http.serve`, 10 connections | at least Node | 61,778 req/s, Node 46,824 | yes |
| `http.serve`, 100 connections | at least Node | 59,655 req/s, Node 50,284 | yes |
| `http.serve`, 1,000 connections | at least Node | 31,927 req/s, Node 42,147 | no |
| `http.serve`, 10 active and 900 idle | at least Node | 58,432 req/s, Node 50,564 | yes |
| 20,000 open connections | held | held, 33,767 req/s | yes |
| Memory per parked fiber | under 8 KB | 3.42 KB | yes |
| The speed gate, real window | at least 60 frames/s | 160, 165, 171; 157 with `--no-spec` | yes |
| A call to a trivial C function | at least 5 million/s | 13.2 million/s; 12.0 with `--no-spec` | yes |
| Loading, resolution included | at least 500,000 lines/s | 475,484 to 487,806 lines/s | no |
| `print(1)`, measurement included | under 5 ms | 4.88 ms, of which 0.49 ms of measurement | yes, 2% margin |
| `kepler do` listing this repository | under 10 ms | 3.53 ms | yes |
| A `.ml` in `src/` rebuilt and tested, `dev` profile | under 5 s | 4.9 s, and 5.006 s once on a hot machine | yes, at the limit |
| A Kepler function active in a running program | under 100 ms | 13 ms (`tools/reload_test.sh`) | yes |
| Tests on both paths | all | 614 + 3 + 74 tests, golden 247/247, and 219/219 with `--no-spec` | yes |
| Results don't depend on the cores | the same bits | `tests/columns/cores`, 1 and 3 cores | yes |
| `tools/check.sh` | passes | yes, 11,913 lines of 15,000, 306 lines of C of 350 | yes |
| 10-minute fuzz, seed 20261105 | no internal error | 136,783 trials, 8,438 ran to the end, 5,516 toml accepted, 0 failures | yes |

The run with seed 20261104, before the functions of the prelude, gave 188,347 trials and 0 failures. The last change of
`sys/linalg.ml`, which keeps `matmul` from the reference BLAS, came after the fuzz. The fuzzer doesn't reach BLAS, as its
programs are small.

The doubled prelude costs each program about 0.44 ms at start, and `print(1)` has little left of its 5 ms.

Not verified: OpenBLAS, MKL and Accelerate, as only the reference libraries are here. Sizes beyond a few million rows have not
been run: the data must fit in RAM, like with pandas, at 8 bytes per cell of a typed column.

### With OpenBLAS

The owner installed OpenBLAS 0.3.34 after the table above. In 1,000 by 1,000, on 4 cores and 8 threads:

| Work | Reference libraries, or OCaml | OpenBLAS |
|---|---:|---:|
| `matmul` | 566 ms | 19 ms |
| `num.solve` | 207 ms | 22 ms |
| `num.qr` | 1,047 ms | 83 ms |
| `num.eigen` | 2,170 ms | 1,477 ms |

## Documentation, 2026-11-02

| Criterion | Target | Measured | Met |
|---|---|---|---|
| Every public name has a comment | all | 539 names, `is_everything_public_has_a_comment` | yes |
| Examples that `kepler test` runs | pass | 330 in `std/`, 0 failed | yes |
| `doc` on all 539 names | fast enough for an editor | 2 ms in all | yes |
| `print(1)`, measurement included | under 5 ms | 3.87 ms in this run, 4.84 ms in the previous one | yes |
| A `.ml` in `src/` rebuilt and tested, `dev` profile | under 5 s | 4.6 to 4.7 s (`tools/check.sh`) | yes |
| A Kepler function active in a running program | under 100 ms | 12 ms (`tools/reload_test.sh`) | yes |
| Tests on both paths | all | 633 + 3 + 330 tests, golden 248/248, and 220/220 with `--no-spec` | yes |
| `tools/check.sh` | passes | yes, 12,168 lines of 15,000 | yes |
| 10-minute fuzz, seed 20261106 | no internal error | 136,389 trials, 9,751 ran to the end, 5,546 toml accepted, 0 failures | yes |

| Benchmark | Kepler | Python | Times Python | Lua | Times Lua | Met |
|---|---:|---:|---:|---:|---:|---|
| fib | 474 ms | 1501 ms | 3.17 | 696 ms | 0.68 | yes |
| mandel | 471 ms | 2658 ms | 5.64 | 440 ms | 1.07 | yes |
| structs | 579 ms | 1819 ms | 3.14 | 1545 ms | 0.37 | yes |
| matmul | 976 ms | 5307 ms | 5.44 | 878 ms | 1.11 | yes |
| dyn | 656 ms | 1438 ms | 2.19 | 723 ms | 0.91 | yes |

The comments of `std/` cost a program nothing at start, except those of the prelude. `doc` reads the sources only when asked.
Loading stays under its target, at 479,761 to 487,806 lines/s.

## Ownership through calls, 2026-11-02

A toy spreadsheet showed the defect: an array passed to any function lost `owned`, so `cells[i] = f(cells, i)` copied the whole
array at each cell. The toy is a flat array of 3 columns, with the formula `=A*B+1` on each row.

| Work, on the old and the new tree | Before | After |
|---|---:|---:|
| 32,000 cells, written to the array the formula reads | 6,198 ms | 21 ms |
| 1 million cells, the same loop | not run: about 1 h 40 by the square | 496 ms |
| 200 edits of a 24 MB array, `a = f(a)` | 681 ms | 4.2 ms |
| 200,000 edits in chunks of 1,024 | 1,622 ms | 301 ms |

| Benchmark | Kepler | Python | Times Python | Lua | Times Lua | Met |
|---|---:|---:|---:|---:|---:|---|
| fib | 457 ms | 1477 ms | 3.23 | 703 ms | 0.65 | yes |
| mandel | 463 ms | 2656 ms | 5.74 | 444 ms | 1.04 | yes |
| structs | 558 ms | 1820 ms | 3.26 | 1524 ms | 0.37 | yes |
| matmul | 921 ms | 5272 ms | 5.72 | 855 ms | 1.08 | yes |
| dyn | 665 ms | 1419 ms | 2.13 | 721 ms | 0.92 | yes |

| Criterion | Target | Measured | Met |
|---|---|---|---|
| `http.serve`, 10 connections | at least Node | 62,975 req/s, Node 48,809 | yes |
| `http.serve`, 100 connections | at least Node | 63,494 req/s, Node 47,918 | yes |
| `http.serve`, 1,000 connections | at least Node | 35,138 req/s, Node 42,037 | no |
| `http.serve`, 10 active and 900 idle | at least Node | 61,263 req/s, Node 48,383 | yes |
| The speed gate, real window | at least 60 frames/s | 172, 176, 190 | yes |
| Loading, resolution included | at least 500,000 lines/s | 499,221 lines/s | no, by 0.2% |
| A `.ml` in `src/` rebuilt and tested, `dev` profile | under 5 s | 4.6 s, as the commit before on the same machine | yes |
| A Kepler function active in a running program | under 100 ms | 12 to 13 ms | yes |
| Tests on both paths | all | 670 + 3 + 330 tests, golden 261/261, and 233/233 with `--no-spec` | yes |
| `tools/check.sh` | passes | yes, 12,276 lines of 15,000 | yes |
| Fuzz of 590 s, seed 20261107 | no internal error | 124,610 trials, 9,244 ran to the end, 5,122 toml accepted, 0 failures | yes |
| Random programs against the commit before, on both paths | the same output | 6,000 programs, 0 differences | yes |

The commit before always copies, which makes it the reference for value semantics. The random programs are full of aliases,
dynamic calls, tail calls and fibers. On deliberately broken engines they found 6 of 10 faults in 150 programs: they are a net,
and each guard has its own test instead. All 24 guards were removed one at a time, and a test noticed each one.

### What the checks found

- A module variable can't be lent: another fiber can write it while the function sleeps. No existing test saw this, and the
  random programs didn't either. `tests/lang/t_lend_fiber` covers it.
- Looking for writes in the arguments cost a square on calls nested in calls: a pipeline of 20,000 steps compiled in 23 s, for
  0.1 s before. The look is now bounded, and `tests/limits/long_pipeline` watches it.
- The first version of the new tests took the change loop to 5.2 s. They now run 100,000 turns, which still shows a square.

Not verified: why one formula costs 40 to 50 times C++ cell by cell. It wasn't profiled, as `perf` isn't on this PC. `ev` returns
boxed floats and writes two pointers per call, which may be all of it.

## Known defects, 2026-11-02

The reviews had listed these without running them. Each one was tried first, and all but the last were real.

| Defect | Seen failing | Fix | Test |
|---|---|---|---|
| `net.find` paid no steps | a loop on 2 MB ran to its end under 20,000 steps | pays on the text | `tests/limits/find_net_pays` |
| `byte_find` paid on what it looks for | the same | pays on the text too | `tests/limits/find_byte_pays` |
| `upper`, `lower` and `trim` copied without reserving | a copy of 3 MB passed a limit of 4 MB | reserve first; `trim` only if it copies | `tests/limits/text_*` |
| A variable named `_dict` took the place of dictionary literals | `{"a": 1}` called the number 5 | the native has a name the lexer can't produce | `tests/lang/t_dict_name` |
| The panics of `sys.start` said `run` | yes | the name is passed along | `tests/sys/start_panic_name` |
| Name resolution stopped every fiber | a fiber ran only after the lookup | a domain resolves, the fiber waits on a pipe | `tests/net_test` |
| `std/tls`, `std/crypto` and `std/cpp` don't run with `--no-spec` | no: they pass | they are now tested on that path | `crypto` in `tools/test.sh`, the two slow ones in `tools/check.sh` |

A lookup that never answers doesn't hold a program back at its end: a domain left asleep for 30 s, and the test took 0.6 s.

| Criterion | Target | Measured | Met |
|---|---|---|---|
| The five benchmarks, Kepler alone | no loss | fib 458, mandel 469, structs 572, matmul 945, dyn 668 ms | yes |
| The speed gate, real window | at least 60 frames/s | 186 | yes |
| Loading, resolution included | at least 500,000 lines/s | 501,568 lines/s | yes, by 0.3% |
| A `.ml` in `src/` rebuilt and tested, `dev` profile | under 5 s | 4.6 to 4.8 s | yes |
| Tests on both paths | all | 670 + 3 + 330 tests, golden 269/269, and 242/242 with `--no-spec` | yes |
| `tools/check.sh` | passes | yes, 12,324 lines of 15,000 | yes |
| Fuzz of 590 s, seed 20261108 | no internal error | 127,985 trials, 9,529 ran to the end, 5,200 toml accepted, 0 failures, 80 C at most | yes |

The new tests first took the change loop past 5 s, and so did the two slow folders on `--no-spec`: the tests now use smaller
texts and shorter waits, and those two folders run in `tools/check.sh`, past the budget.

## Generic path only (`--no-spec`)

| Benchmark | Kepler | Times Python |
|---|---:|---:|
| fib | 758 ms | 1.94 |
| mandel | 1206 ms | 2.17 |
| structs | 645 ms | 2.73 |
| matmul | 2651 ms | 1.85 |
| dyn | 1541 ms | 0.92 |

After the async work, on the slower machine: 800, 1267, 667, 2935 and 1719 ms, in the same order.

After the C interop work: 754, 1172, 602, 2570 and 1584 ms, in the same order.

At the end of the roadmap: 773, 1236, 625, 2839 and 1610 ms, in the same order.

After the typed columns: 774, 1225, 624, 2762 and 1543 ms, in the same order.

After ownership through calls: 774, 1200, 616, 2743 and 1611 ms, in the same order.

## What made dyn and fib faster

- The version cache lives on the function, not on the site: a site alternating between two functions missed on every call.
- A single check per call: depth costs nothing on the call path. A call adds one frame and counts one step, so the limit
  can't fall before `max_depth - d` steps: `fuel` is bounded by that margin, and frames are counted at the checkpoint,
  each one once.
- `mod(i, 2^k)` as a mask: `idiv` costs about twenty nanoseconds on this processor.
- No jump table to read an argument's type: an indirect jump predicts badly when types alternate.
- Cold paths out of the closure: `Runtime.grow` was inlined in every call site.
- `float op int` and `array[i] op array[j]` without a closure: a closure returning a float allocates it.
