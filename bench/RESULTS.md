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
| fib | 453 ms | 1486 ms | 3.28 | 694 ms | 0.65 | at least 3 times Python, at most 1.3 times Lua | yes |
| mandel | 467 ms | 2655 ms | 5.69 | 435 ms | 1.07 | same | yes |
| structs | 576 ms | 1821 ms | 3.16 | 1512 ms | 0.38 | same | yes |
| matmul | 960 ms | 5202 ms | 5.42 | 870 ms | 1.10 | same | yes |
| dyn | 690 ms | 1424 ms | 2.06 | 720 ms | 0.96 | at least 2 times Python | yes, 3% margin |

An earlier build of the same day gave 714 ms on `dyn`, 2.00 times Python: the 5% of code placement can take it to the
target.

| Criterion | Target | Measured | Met |
|---|---|---|---|
| `http.serve`, 10 connections | at least Node | 56,948 req/s, Node 45,590 | yes |
| `http.serve`, 100 connections | at least Node | 56,874 req/s, Node 42,949 | yes |
| `http.serve`, 1,000 connections | at least Node | 31,518 req/s, Node 40,062 | no |
| `http.serve`, 10 active and 900 idle | at least Node | 55,682 req/s, Node 48,789 | yes |
| 20,000 open connections | held | held, 33,728 req/s | yes |
| Memory per parked fiber | under 8 KB | 3.43 KB | yes |
| The speed gate, `bench/frame.kp`, real window | at least 60 frames/s | 156, 173, 161; 168 with `--no-spec` | yes |
| A call to a trivial C function, `bench/ccall.kp` | at least 5 million/s | 12.4 million/s; 11.8 with `--no-spec` | yes |
| Loading, resolution included | at least 500,000 lines/s | 468,589 to 484,116 lines/s; previous commit in turn 483,623 | no |
| `print(1)`, measurement included | under 5 ms | 4.17 ms on average, of which 0.50 ms of measurement | yes |
| `kepler do` listing this repository | under 10 ms | 2.94 ms | yes |
| A `.ml` in `src/` rebuilt and tested, `dev` profile | under 5 s | 4.4 to 4.5 s (`tools/check.sh`) | yes, thin margin |
| A Kepler function active in a running program | under 100 ms | 17 ms (`tools/reload_test.sh`) | yes |
| Tests on both paths | all | 499 + 3 + 22 tests, golden 244/244, and 218/218 with `--no-spec` | yes |
| `tools/check.sh` | passes | yes, 11,187 lines of 15,000, 235 lines of C of 300 | yes |
| 10-minute fuzz, seed 20261102 | no internal error | 194,927 trials, 11,802 ran to the end, 7,705 toml accepted, 0 failures | yes |

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

The result in turn is 58,370 against 64,741 req/s, and 31,242 against 34,339: about 10% remains. It sits in what requests
now pay for: the `io` closures, HEAD and upgrades.

The miss at 1,000 connections is new because Node moved: the previous commit gives 34,339 req/s against Node's 40,062. Why
`http.serve` falls from 57,000 to 31,500 req/s between 100 and 1,000 connections has not been investigated.

### Loading

Loading is not a regression of this work: the previous commit gives 483,623 lines/s in turn. The 1% margin noted earlier
did not survive this machine. `bench/load.sh` had failed since `defn` replaced `function`, and now writes `defn`.

### The change loop

`tools/check.sh` had gone to 5.8 s with the review's tests, unseen because it stopped earlier on a forbidden word. A costly
model in the rope test and fixed waits in the others account for it. Each of the four tests that changed their numbers was
seen failing again with its defect put back: no pause after a failed `accept`, no `io.arm(idle)`, no `Runtime.reserve`, a
leaf merge that loses lines. `sleep_huge`, `flush_idle` and `stop` only wait less, and were not run with a defect.

### The fuzz

Two runs came to 0 failures: seed 20261101 gave 186,126 trials, before the HTTP change, and seed 20261102 gave the line in
the table, on the final tree. A first run with seed 2026 was lost at about 498 s: the PC went off with its GPU at 95 °C
while Steam was looping, and went off the same way 10 minutes later without the fuzzer. No failure had been saved.

Not verified: macOS, Windows and arm64. `.github/workflows/ci.yml` is written and has never run, as there is no remote.

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

At the end of the roadmap: 776, 1234, 613, 2725 and 1658 ms, in the same order.

## What made dyn and fib faster

- The version cache lives on the function, not on the site: a site alternating between two functions missed on every call.
- A single check per call: depth costs nothing on the call path. A call adds one frame and counts one step, so the limit
  can't fall before `max_depth - d` steps: `fuel` is bounded by that margin, and frames are counted at the checkpoint,
  each one once.
- `mod(i, 2^k)` as a mask: `idiv` costs about twenty nanoseconds on this processor.
- No jump table to read an argument's type: an indirect jump predicts badly when types alternate.
- Cold paths out of the closure: `Runtime.grow` was inlined in every call site.
- `float op int` and `array[i] op array[j]` without a closure: a closure returning a float allocates it.
