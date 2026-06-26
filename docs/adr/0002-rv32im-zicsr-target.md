# Target RV32IM_Zicsr (machine-mode), not RV64

The Hart implements RV32IM_Zicsr in machine mode only, targeting the `rv32ui-p`,
`rv32um-p`, and `rv32mi-p` test environments. No RV64, no float (F/D), no supervisor
mode or virtual memory (`-v`).

## Considered Options

- **RV32 (chosen)** — Factorio runs stock **Lua 5.2**, whose numbers are doubles with a
  53-bit mantissa. A 32-bit word fits exactly; arithmetic is mask-to-32 via the `bit32`
  stdlib. RV64 would need split-limb math for every operation because 64-bit integers do
  not fit in a double.
- **RV64** — authentic to most real hardware, but fights the Lua 5.2 number model
  throughout.

## Consequences

`Zicsr` + trap handling (`ecall`/`ebreak`/`mret`, `mtvec`/`mepc`/`mcause`/…) is in scope
even though "just integer tests" sounds simpler — the `-p` tests signal pass via a trap.
Float and S-mode are explicit non-goals; revisit only if a use case demands them.
