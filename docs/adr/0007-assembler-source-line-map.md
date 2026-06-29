# Assembler emits a source-line map for the in-game debugger

The Inspector (the RISC-V Combinator's in-game debugger GUI) marks the *currently
executing instruction in the player's own source*, but the Hart executes machine code
at a PC and the mapping is not one-to-one: pseudo-ops expand many-to-one (`li`/`la` →
two instructions), and labels, blank lines, comments and directives emit no instruction
at all — so a source line is not an instruction. The Assembler therefore returns an
`addr → source-line` table (a line counter threaded through `emit`/`emit_data`), and the
Inspector maps the live PC back to a source line for its gutter marker and auto-scroll.
Conformance is untouched: it is an extra return field, the line tracking is additive, and
the `riscv-tests` path (assemble with no resolver) is byte-for-byte unchanged.

## Considered Options

- **Source-line map (chosen)** — keeps the player's program on screen exactly as typed
  (labels, comments, pseudo-ops), and the marker only needs a PC→line lookup. The cost is
  a small, additive change to the Assembler's return shape.
- **Disassembly view** — render one row per decoded instruction; PC→row is then trivial
  and needs no Assembler change. Rejected: the displayed code stops matching what the
  player wrote (no labels or comments, pseudo-ops shown post-expansion), and the Inspector
  exists to edit and read *your* source.
- **Constrain the in-game language to one-line-per-instruction** (fcpu's model, where
  line == instruction so no map is needed). Rejected: it guts the full RV32IM_Zicsr
  grammar — pseudo-ops, macros, `.rept`, directives — the Assembler already supports
  (ADR-0004).

## Consequences

- A multi-instruction source line (e.g. `li a0, 0x12345`) holds the marker for several
  steps; label / blank / comment / directive lines never carry it.
- The Hart stays **uninstrumented**: the Inspector's register and memory "changed-cell"
  highlights are computed by GUI-side diffing (snapshot → step → compare), not by trace
  fields added to `step()`. This keeps the ADR-0005 discipline — no new per-step hook on
  the conformance hot path.
- The line map is debug metadata: it is not part of the loadable Program image and is
  recomputed on each assemble.
