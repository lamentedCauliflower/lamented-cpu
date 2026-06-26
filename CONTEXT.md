# lamented-cpu

A Factorio mod that adds a single combinator entity which strictly emulates a RISC-V
hart. "Strictly" means conformance is defined by the upstream `riscv-tests` suite —
if a behaviour disagrees with those tests, the tests are right. Target ISA is
**RV32IM_Zicsr**, machine-mode only.

## Language

**RISC-V Combinator**:
The in-world entity the mod adds and the player places. Shown in-game as "RISC-V
Combinator"; prototype id `riscv-combinator`. It hosts exactly one Hart.
_Avoid_: CPU entity, processor block, fcpu combinator.

**Hart**:
A single RISC-V hardware thread — the unit that holds architectural state (registers,
program counter, CSRs) and executes instructions. The mod emulates exactly one Hart per
RISC-V Combinator. Borrowed from the RISC-V spec; we use it instead of "core" or "CPU"
to keep one precise word.
_Avoid_: Core, CPU, processor.

**Program image**:
The bytes loaded into a Hart's memory before it runs — for conformance, a compiled
`riscv-tests` ELF; in-game, the player's program. The flat sequence of bytes placed in
memory, distinct from the source it was built from.
_Avoid_: Binary, ROM, firmware, code.

**riscv-tests**:
The upstream conformance suite (`riscv-software-src/riscv-tests`) that defines correct
behaviour for this mod. When we say the Hart is "correct", we mean the relevant TVMs
(`rv32ui-p`, `rv32um-p`, `rv32mi-p`) pass.
_Avoid_: Test suite, the tests (when ambiguous), spec tests.

**Host interface**:
The channel through which a running Program image signals the outside world. For
conformance it is the `riscv-tests` HTIF convention — a write to the `tohost` memory
symbol halts the Hart and reports pass or the failing test number. In-game the same
boundary is repurposed to bridge the Hart to Factorio circuit wires.
_Avoid_: HTIF (in prose — name it "host interface" and mention HTIF once), syscall, MMIO.

**tohost / fromhost**:
The two memory symbols that make up the conformance Host interface. `tohost` is written
by the Program image to report results; `fromhost` is the reverse channel. Their
addresses are resolved from the Program image's ELF symbol table.
_Avoid_: Magic address, result register.
