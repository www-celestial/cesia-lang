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

- `mir-gen-x86_64.c`, `target_change_to_direct_calls`: two reads of a 32-bit and a 64-bit word inside machine code, through
  casts of unaligned pointers, are `memcpy` now. UBSan reported the first one ("load of misaligned address"); x86-64
  tolerates it, C doesn't promise it.
- `mir-gen.c`, `change_reg`: the integer register for the address of a spilled value's stack slot is taken only when the
  slot's offset doesn't fit the instruction (never on x86-64). Taken always, a spilled double stored through a base and an
  index (`dmov d:-8(base, index, 4), r`, which MIR's ssa combine forms from our separate add) needed a third integer
  reload register, and `get_reload_hreg`'s `gen_assert (rld_num <= 1)` aborted the process.
- `mir-gen-x86_64.c`, `target_make_prolog_epilog`: a frame of more than 2 KB touches its pages from the top down, then its
  bottom, as `__chkstk` does. Windows commits a thread's stack one guard page at a time, and MIR's prologue moved the
  stack pointer past it at once, so the first access of a frame over a page could fault there. Done on every system, so
  that the tests of each one run the same code; no frame of the suite or the benches is that large (`tests/jit_test.ml`
  makes one, of 8 KB).
- `mir-gen.c`, `loop_invariant_p`: an instruction that sets the overflow flag (`addo`, `subo`, `mulo` and their kin) is
  never moved out of a loop. Moved alone, it left its `bo` in the loop reading the flags of another instruction: an
  overflow of an operation on a value fixed in the inner loop, as `k * c` with `k` an outer counter, went unseen.
- `mir-gen.c` `gen_assert` and `mir.h` `mir_assert`: a failed check calls `cesia_mir_failed` (in `src/sys/jit.c`), which goes
  back to the load as MIR's errors do, and the JIT is off for the rest of the run: a check of MIR never kills Cesia.
- `mir-gen-x86_64.c`, `patterns_init`: the table of patterns, shared by every context, gets its sizes from the first
  context made, not from each one. The JIT makes a context per unit, and a unit's level 2 in another thread: a context
  made then would write the table while that thread's context reads it, the same values, but a race in C all the same.
- `mir-interp.c`, `interp_init`: the offsets of MIR's interpreter, shared by every context, are written by the first context
  made only, for the same reason.
