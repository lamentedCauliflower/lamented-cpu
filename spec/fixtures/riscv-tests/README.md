# riscv-tests fixtures (assembly)

Flat RISC-V **assembly** (`.s`) expanded from
[riscv-software-src/riscv-tests](https://github.com/riscv-software-src/riscv-tests),
the upstream conformance suite (ADR-0004). The Hart runs assembly, not binaries: the
conformance spec assembles these with the in-Lua Assembler, runs the Hart to halt, and
asserts the `tohost` result.

- **Pinned revision:** `34e6b6d1e7936b526075432fb730d89148623484`
- **Families:** `rv32ui-p-*`, `rv32um-p-*` (50 tests), and the in-scope subset of
  `rv32mi-p-*`: `csr`, `mcsr`, `scall`, `sbreak`, `shamt` (5 tests).
- **Env:** wrapped in our custom minimal machine-mode env, `../../riscv-env/riscv_test.h`,
  not riscv-tests' `env/p` — it sets `mtvec` and runs the body directly in M-mode (no
  PMP / `satp` / supervisor). `tohost` is defined in each file.
- **Expansion:** `cpp -P -D__riscv_xlen=32` only — no RISC-V toolchain, no machine code.

## rv32mi-p: why only 5 of 16

The omitted `rv32mi-p` tests are out of scope for an RV32IM_Zicsr machine-mode core
(ADR-0002), and one group directly contradicts a test we already pass:

- **Misalign-trap variants** — `ma_addr`, `lh/lw/sh/sw-misaligned`: these require
  misaligned load/store to **trap**. The Hart *handles* misaligned access (needed by
  the already-green `rv32ui-p-ma_data`), and a single CPU cannot do both. Mutually
  exclusive in upstream by design.
- **Out-of-extension** — `pmpaddr` (PMP), `breakpoint` (debug triggers),
  `instret_overflow` + `zicntr` (hardware counters): none are in RV32IM_Zicsr.
- **Interrupt/compressed machinery** — `illegal` (vectored interrupts, `wfi`,
  `mideleg`), `ma_fetch` (compressed `c.j`): beyond the scalar M-mode trap core.

Regenerate with `gen-riscv-tests` (dev-only; pulls `cpp` via `nix shell`, never on the
`devenv test` CI gate). Bump the pinned rev in `devenv.nix`'s `gen-riscv-tests` script
to update.
