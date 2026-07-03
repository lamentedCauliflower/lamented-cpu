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
halts the Hart and reports pass or the failing test number. In-game the boundary is
realized separately as the **Circuit-network controller** (below), a memory-mapped
device with its own fixed addresses; the conformance `tohost`/`fromhost` symbols are
not reused for circuit I/O.
_Avoid_: HTIF (in prose — name it "host interface" and mention HTIF once), syscall.

**tohost / fromhost**:
The two symbols that make up the conformance Host interface. `tohost` is written by the
Program image to report results; `fromhost` is the reverse channel. Their addresses
come from the Assembler's symbol table.
_Avoid_: Magic address, result register.

## Circuit I/O

How an in-game Program image talks to Factorio's circuit network. Distinct from the
conformance Host interface above.

**Circuit-network controller**:
The memory-mapped peripheral that bridges the Hart to Factorio's circuit network — the
in-game realization of the Host interface. A device at a fixed address that the Program
image drives with ordinary loads and stores. (Name provisional.)
_Avoid_: I/O combinator, bridge, virtual combinator.

**Signal map**:
The save's append-only table assigning each Factorio signal a small integer ID — grown
when a signal is first seen on a wire or named in source, and never renumbered (so a
running Program image's baked IDs stay valid). Source names a signal by the game's
rich-text tag (`[item=processing-unit]`, `[virtual-signal=signal-D]`), which the
Assembler resolves to the save's ID; programs are thus portable as source, not as images
(ADR-0004). Basic scope: base prototypes, normal quality; per-quality deferred.
_Avoid_: Signal table, channel map, datasheet, raw signal index.

**Input snapshot**:
The frozen copy of input-wire signals taken at the instant of a Sample — everything
present (Full sample) or the answers to the Query registers (Query sample). The Program
image reads from this copy, so the circuit network changing after a Sample cannot
perturb a computation already in flight.
_Avoid_: Input buffer, read buffer.

**Output staging**:
The pending set of signals a Program image builds up before a Commit. It has no effect
on the circuit network until committed, so partial output is never visible on the wires.
_Avoid_: Output buffer, write buffer.

**Sample**:
The trigger that latches the chosen input wire(s) — red, green, or both — into the Input
snapshot. Comes in two kinds: Full sample and Query sample.
_Avoid_: Read, poll.

**Full sample**:
A Sample that captures every signal present on the chosen wires, largest value first.
_Avoid_: Dump, bulk read, plain sample.

**Query sample**:
A Sample that answers only the signals named in the Query registers, one result per
register, instead of capturing everything. A queried signal absent from the wires reads
as zero, matching the circuit network's own convention.
_Avoid_: Lookup, targeted sample, poll.

**Query registers**:
The program-owned slots, sixteen of them, each naming one signal the program wants a
Query sample to answer. They persist until the Program image overwrites them.
_Avoid_: Watch list, lookup registers, Q slots.

**Commit**:
The trigger that flushes the Output staging atomically onto the controller's output,
where it becomes visible on the circuit network.
_Avoid_: Write, flush, publish.

## Inspector

**Inspector**:
The in-game debugger GUI for a RISC-V Combinator: one window giving a live, synchronized
view of a single Hart — the editable assembly source with the currently executing
instruction's source line marked, the register file, and a memory browser — driven by
Run / Pause / Step transport over a master On/Off enable.
_Avoid_: Control panel, debugger window, fcpu panel.

## Documentation

**Manual**:
The mod's in-game RISC-V reference — a chaptered education resource for writing assembly
on the Hart, authored once and rendered through Informatron. Covers the
register file, the instruction set (only the mnemonics the Assembler accepts), the calling
convention, the memory/execution model, CSRs and traps, and Circuit I/O. Grows by one
chapter per extension the mod adds. Distinct from the Inspector (the live debugger); the
Manual is static reference, not a view of any one Hart.
_Avoid_: Docs, help, wiki, guide, tooltip.

**Wiki mirror**:
The GitHub-wiki rendering of the Manual — the same chapters, generated from the same
source as the in-game Manual and published by CI, one wiki page per chapter. A pure
build artifact: never hand-edited, always overwritten on the next publish, and never
containing content the in-game Manual lacks.
_Avoid_: The wiki (when ambiguous), online docs, GitHub docs.
