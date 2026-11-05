# Our copy of MIR

MIR is Vladimir Makarov's JIT compiler (https://github.com/vnmakarov/mir, MIT, see `LICENSE`). This folder is our copy,
at the upstream commit in `VERSION`. `tools/mir-diff.sh` shows how it differs from that commit, so that upstream fixes can
be brought in by hand.

## Rules

- Change MIR through its own hooks first: `MIR_init2` takes our allocators, `MIR_set_error_func` our error handler.
- Patch its C only when no hook does it; each changed place carries a comment that starts with `Cesia:`, and each patch is
  listed below with its reason.
- MIR only ever reads MIR text that Cesia's generator writes: names it makes and numbers, never a name, a text or any byte
  of a user's program.

## Taken from upstream

The core only: `mir.c`, `mir-gen.c` and what they include (the five targets, the headers, the default allocators,
`mir-interp.c`), `LICENSE`. Left out: `c2mir/` (we write MIR, not C), the drivers, tests, benchmarks and docs.

`mir-interp.c` stays although Cesia never interprets MIR: `mir.c` uses it to evaluate data expressions at link time.

## Ours

- `dune`, `VERSION` and this file.
- In `src/sys/jit.c`, not here: the code allocator. MIR's default one keeps code pages writable and executable at once
  while it writes them on Linux and Windows; ours makes them read-write while MIR writes, then read and execute, never both.
  On Apple's arm64 it keeps MAP_JIT and the switch per thread, Apple's own way. Also the error handler, which comes back to
  the load instead of exiting.

## Patches to MIR's C

None yet.
