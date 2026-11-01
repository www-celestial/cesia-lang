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

## What made dyn and fib faster

- The version cache lives on the function, not on the site: a site alternating between two functions missed on every call.
- A single check per call: depth costs nothing on the call path. A call adds one frame and counts one step, so the limit
  can't fall before `max_depth - d` steps: `fuel` is bounded by that margin, and frames are counted at the checkpoint,
  each one once.
- `mod(i, 2^k)` as a mask: `idiv` costs about twenty nanoseconds on this processor.
- No jump table to read an argument's type: an indirect jump predicts badly when types alternate.
- Cold paths out of the closure: `Runtime.grow` was inlined in every call site.
- `float op int` and `array[i] op array[j]` without a closure: a closure returning a float allocates it.
