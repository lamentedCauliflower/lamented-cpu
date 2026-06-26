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
The machine code a Hart executes, produced by the Assembler from assembly source and
placed in the Hart's memory. The Hart has no compiled-binary input — the loadable
artifact is always assembly text, in-game and in conformance. Distinct from the
assembly source it was built from.
_Avoid_: Binary, ELF, ROM, firmware, code.

**Assembler**:
The mod component that turns RISC-V assembly text into a Program image (32-bit
encodings). A small RV32IM_Zicsr assembler owned by the mod — used both for in-game
programs and to build the conformance tests — needing no external toolchain at run
time. It also produces the symbol table from which `tohost` is resolved.
_Avoid_: Compiler, codegen, gas (except when naming the tool we are NOT using).

**riscv-tests**:
The upstream conformance suite (`riscv-software-src/riscv-tests`) that defines correct
behaviour for this mod. We run the suite's **assembly sources** (assembled by our
Assembler against the Test env), not its prebuilt binaries. "Correct" means the
relevant TVMs (`rv32ui-p`, `rv32um-p`, `rv32mi-p`) pass.
_Avoid_: Test suite, the tests (when ambiguous), spec tests.

**Test env**:
The small machine-mode harness — reset vector, trap handler, and `tohost` — that wraps
a `riscv-tests` body so it runs on our Hart. A minimal in-repo replacement for
`riscv-tests`' `env/p`, using only the M-mode CSRs the Hart implements (no PMP, `satp`,
or supervisor mode).
_Avoid_: crt0, bootrom, env/p (except when naming what we replace).

**Host interface**:
The channel through which a running Program image signals the outside world. For
conformance it is the `riscv-tests` HTIF convention — a write to the `tohost` symbol
halts the Hart and reports pass or the failing test number. In-game the same boundary
is repurposed to bridge the Hart to Factorio circuit wires.
_Avoid_: HTIF (in prose — name it "host interface" and mention HTIF once), syscall, MMIO.

**tohost / fromhost**:
The two symbols that make up the conformance Host interface. `tohost` is written by the
Program image to report results; `fromhost` is the reverse channel. Their addresses
come from the Assembler's symbol table.
_Avoid_: Magic address, result register.
