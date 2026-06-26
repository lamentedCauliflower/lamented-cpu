# Conformance runs assembled assembly, not prebuilt binaries

The Hart's only program input is RISC-V assembly text; there is no compiled-binary path.
A small in-Lua RV32IM_Zicsr **Assembler** turns assembly into the Program image, both
in-game and for tests. Conformance therefore runs the `riscv-tests` **assembly sources**
(vendored at a pinned revision), wrapped in a custom minimal machine-mode **Test env**
— our replacement for `env/p`, using only the M-mode CSRs the Hart implements (no PMP,
`satp`, or supervisor). Sources are flattened once with plain `cpp` at vendor time and
committed as `.s` fixtures; the Assembler consumes those.

## Considered Options

- **Assemble riscv-tests sources in-Lua (chosen)** — the CPU runs human-readable
  assembly like the reference combinator CPUs, and the conformance inputs are the same
  assembly a developer reads. `cpp` (ubiquitous) expands macros at vendor time; no
  RISC-V cross-toolchain anywhere.
- **Prebuilt ELF fixtures + ELF loader** (ADR-0003, superseded) — hides the program
  behind an opaque binary and a toolchain; contradicts "run assembly, not binaries".
- **Hand-roll `cpp` + `gas` + `ld` fully in Lua** — reimplements the toolchain. `cpp`
  at vendor time plus a bounded assembler is far less code.
- **Core interprets mnemonics directly** — drops encoding-level conformance; the
  `rv32mi-p` illegal-instruction and misaligned-fetch tests are *about* encodings.

## Consequences

- `tohost`'s address comes from the Assembler's symbol table, not an ELF `.symtab`.
- The Assembler must evaluate C-style constant expressions and expand pseudo-instructions
  (`li`, `la`, `j`, `ret`, `csrr`, `csrw`, …) plus a handful of directives and local
  labels. It is the most intricate non-core module and grows alongside the ISA slices —
  each instruction needs both an encoder (Assembler) and a decoder (Hart).
- The only external tool is `cpp`, used at vendor time to expand the `riscv-tests` macro
  bodies and our Test env; it is never on the run-time or CI gate path.
- Using a custom Test env (riscv-tests' intended swap point) keeps the assembler and the
  Hart's CSR surface bounded to RV32IM_Zicsr machine mode.
