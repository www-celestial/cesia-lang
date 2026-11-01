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

## Generic path only (`--no-spec`)

| Benchmark | Kepler | Times Python |
|---|---:|---:|
| fib | 758 ms | 1.94 |
| mandel | 1206 ms | 2.17 |
| structs | 645 ms | 2.73 |
| matmul | 2651 ms | 1.85 |
| dyn | 1541 ms | 0.92 |

## What made dyn and fib faster

- The version cache lives on the function, not on the site: a site alternating between two functions missed on every call.
- A single check per call: depth costs nothing on the call path. A call adds one frame and counts one step, so the limit
  can't fall before `max_depth - d` steps: `fuel` is bounded by that margin, and frames are counted at the checkpoint,
  each one once.
- `mod(i, 2^k)` as a mask: `idiv` costs about twenty nanoseconds on this processor.
- No jump table to read an argument's type: an indirect jump predicts badly when types alternate.
- Cold paths out of the closure: `Runtime.grow` was inlined in every call site.
- `float op int` and `array[i] op array[j]` without a closure: a closure returning a float allocates it.
