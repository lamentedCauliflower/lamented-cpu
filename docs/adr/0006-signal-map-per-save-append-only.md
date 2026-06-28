# Signal IDs are a per-save, append-only map; source names signals by rich-text tag

The circuit-network controller (ADR-0005) moves `(id, value)` pairs, so each Factorio
signal needs an integer ID. We assign IDs from a **per-save, append-only Signal map**:
a signal gets the next free ID the first time it is seen on a wire or named in source,
and is **never renumbered**. Source does not write raw IDs — it names a signal with the
game's **rich-text tag** (`[item=processing-unit]`, `[virtual-signal=signal-D]`), and the
Assembler resolves the tag to the save's ID through an injected resolver. Because the
loadable artifact is assembly *source* (ADR-0004), per-save numbering costs nothing:
programs are shared and re-resolved as source, not as fixed-ID binaries.

## Considered Options

- **Per-save append-only map + rich-text naming (chosen)** — covers any signal (base or
  modded) with zero maintenance, needs no global registry, and the rich-text tag carries
  the signal type *and* renders as the real icon in the GUI source text-box. Per-save IDs
  are non-portable, but only the source is meant to travel (ADR-0004), so that is a
  non-issue.
- **Global committed append-only table** — gives stable global IDs and a printable
  datasheet, but must be regenerated as the game/mods evolve and still cannot cover an
  arbitrary installed mod set. Once source names signals instead of numbering them, the
  global table earns nothing.
- **`hash(type/name) -> id`** — universal and registry-free, but IDs are opaque and
  collisions are mod-set-dependent (a program runs for one player, collides for another).
- **Custom `.signal handle, type, name` directive** — works, but the rich-text tag
  already encodes the type, draws as the actual icon while editing, and round-trips as
  plain text for sharing. The directive is strictly more typing for less.

## Consequences

- The Assembler takes an injected `signal(type, name) -> id` resolver; `lib/asm.lua`
  stays engine-free and busted-testable (ADR-0001). The allocation (the save mutation)
  lives in the in-game resolver in `control.lua`, backed by `storage`, not in the
  Assembler. Tests pass a stub resolver.
- Resolution is a source preprocessing step: each `[type=name]` tag is replaced with its
  resolved decimal ID before the normal two-pass assemble, so `evalexpr` is untouched.
- Append-only is load-bearing: a seen/named signal keeps its ID for the life of the save
  so a running image's baked IDs never invalidate; a signal later removed from the game
  keeps its reserved ID.
- Output `Commit` needs the reverse `id -> (type, name)` map to turn staged IDs back into
  `SignalID`s on the output combinator; a staged ID absent from the map is dropped and
  flagged in `STATUS`.
- Rich-text type `virtual-signal` maps to `SignalID` type `virtual`. Basic accepts
  `item` / `fluid` / `virtual-signal`; other 2.0 signal types and a `,quality=` clause
  error for now (quality deferred).
- Relies on the GUI source `text-box` returning literal tag markup in `.text` (verify
  in-engine); resolution works from the literal text whether or not icons render.
