# In-game I/O is a memory-mapped circuit-network controller, not HTIF reuse

The Hart reaches Factorio's circuit network through a **memory-mapped peripheral** — the
*circuit-network controller* — at a fixed low base address (`~0x1000_0000`), driven by
ordinary `lw`/`sw`. We did *not* reuse the conformance `tohost`/`fromhost` (HTIF)
symbols: real RISC-V has no port I/O — all I/O is memory-mapped — and HTIF is a
simulator artifact whose `tohost` write *halts* the Hart. Bulk transfer is a
shared-memory **mailbox + doorbell**: a `Sample` strobe latches the input wires into an
Input snapshot block, the program reads it and fills an Output staging block, and a
`Commit` strobe flushes it atomically to a hidden output combinator on the device's
output side. Signals are named by a mod-assigned stable **Signal map** (base prototypes,
normal quality). Glossary terms are in [`CONTEXT.md`](../../CONTEXT.md) under *Circuit
I/O*.

## Considered Options

- **MMIO controller, mailbox + doorbell (chosen)** — the only I/O shape real RV32 has,
  and the authentic pattern for moving a *set* of values (DMA descriptor ring + doorbell,
  like a NIC/virtio). Critically, it is the least invasive to the conformance core: only
  the `Sample`/`Commit` doorbell stores are watched — reusing the existing `tohost`
  store-watch pattern (`hart.lua` `store32`) — so the hot *load* path gains no hook and
  the green `rv32ui/um/mi-p` suite is untouched (the I/O window sits far below the tests'
  `0x8000_0000`).
- **Reuse `tohost`/`fromhost` (HTIF)** — what `CONTEXT.md` originally hinted. Rejected:
  a `tohost` store halts the Hart and reports pass/fail, so in-game output would force
  `store32` to branch on conformance-vs-game at one address; HTIF addresses are also
  *program-chosen* (assembler symbol table), a poor anchor for a stable I/O contract; and
  HTIF is not real hardware.
- **Indirect index/data register ports** (UART/PCI-config style) — authentic, but needs
  a read-side MMIO hook in the Hart load path, touching the conformance-critical hot path.
- **Dense signal→address map** (`base + id*4`) — huge, hostile to the sparse snapshot
  (a wire carries only nonzero signals), and its size tracks the installed mod set.
- **Single shared connector** — the device's own committed output feeds back into the
  next Input snapshot; the program would have to subtract itself.
- **Program-supplied DMA pointers** — more authentic-NIC and flexible, but more machinery
  than basic I/O needs. Deferred, not rejected.

## Consequences

- `data.lua` is no longer a plain constant-combinator reskin: the entity gains **two
  sides** (separate input/output connectors) plus a **hidden output combinator** whose
  signals the mod rewrites on `Commit`.
- Conformance is untouched by construction — no load-path hook, only doorbell
  store-watches, and the I/O window never overlaps test memory.
- Signals are named by a **Signal map**; its assignment scheme — per-save, append-only,
  named in source via the game's rich-text tags — is settled in ADR-0006. Per-quality
  signal IDs are an explicit non-goal for now.
- Blocks are capacity-capped (256 `(id,value)` entries each); an input set larger than
  the cap truncates and sets a `STATUS` overflow bit.
- Each block is 2 KiB, so the two blocks cannot both sit within one ±2 KiB `lw`/`sw`
  offset window — programs keep a base register per region. Acceptable; it is the normal
  way to address a device.
- The committed output **latches**: a `Commit` holds on the output side until the next
  `Commit`, and is *not* cleared when the Hart halts or errors (the last output stays on
  the wire and inspectable). Assemble & Run resets staging and output to a clean slate.
