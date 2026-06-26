# riscv-tests fixtures (assembly)

Flat RISC-V **assembly** (`.s`) expanded from
[riscv-software-src/riscv-tests](https://github.com/riscv-software-src/riscv-tests),
the upstream conformance suite (ADR-0004). The Hart runs assembly, not binaries: the
conformance spec assembles these with the in-Lua Assembler, runs the Hart to halt, and
asserts the `tohost` result.

- **Pinned revision:** `34e6b6d1e7936b526075432fb730d89148623484`
- **Families:** `rv32ui-p-*`, `rv32um-p-*` (50 tests)
- **Env:** wrapped in our custom minimal machine-mode env, `../../riscv-env/riscv_test.h`,
  not riscv-tests' `env/p` — it sets `mtvec` and runs the body directly in M-mode (no
  PMP / `satp` / supervisor). Only `mtvec` and `mcause` are referenced; `tohost` is
  defined in each file.
- **Expansion:** `cpp -P -D__riscv_xlen=32` only — no RISC-V toolchain, no machine code.

`rv32mi-p` is **not** here yet: those tests need M-mode encoding constants
(`MSTATUS_*`, `CAUSE_*`) and broader CSR support, which arrive with the CSR/trap slice
(issue #7), at which point the env and this set extend to cover them.

Regenerate with `gen-riscv-tests` (dev-only; pulls `cpp` via `nix shell`, never on the
`devenv test` CI gate). Bump the pinned rev in `devenv.nix`'s `gen-riscv-tests` script
to update.
