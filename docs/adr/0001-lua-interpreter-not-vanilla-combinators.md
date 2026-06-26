# Emulate the Hart in Lua, not from vanilla combinators

The RISC-V Combinator emulates its Hart entirely in the mod's Lua control script —
registers and memory are Lua tables, the fetch/decode/execute loop is Lua code. We did
*not* build the CPU out of in-game circuit-network combinators (the path a reader
familiar with fcpu's vanilla SIMD memory might expect).

## Considered Options

- **Pure-Lua emulator (chosen)** — deterministic, runs in `busted` with no game engine,
  so the `riscv-tests` conformance gate is plain unit tests.
- **Hybrid / full vanilla circuit build** — more "authentic Factorio", but making a
  combinator lattice pass `riscv-tests` is a multi-year effort and is untestable outside
  a running game.

## Consequences

The conformance suite is engine-independent; the Factorio headless smoke only has to
prove the entity loads, not that the ISA is correct.
