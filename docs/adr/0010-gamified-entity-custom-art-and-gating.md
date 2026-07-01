# Gamified RISC-V Combinator: custom art, 3×2 footprint, research gating

The RISC-V Combinator stops being a pure decider-combinator clone that "ships no binary
assets": it now carries a **custom 3×2, four-way sprite** and is **gated behind a technology
and recipe** instead of being craftable from the start. Under Space Age the recipe is
**electromagnetic-plant-only** and its technology chains off Fulgora; in vanilla it unlocks
after the selector combinator and blue circuits. We accept shipping PNGs and a branching
data stage to make the entity read as a deliberate mid/late-game milestone rather than a free
reskinned combinator.

## Why depart from clone-only

The clone-only stance (reuse the decider's graphics, ship no binary assets — see `data.lua`)
kept the repo asset-free and the entity visually a combinator. But a 1×2 decider silhouette
reads as "just another combinator," undercutting the fiction that this hosts a whole Hart. A
3×2 footprint has no decider art to borrow, so custom sprites and clone-only are mutually
exclusive — we chose presence over purity. The entity keeps `type = "decider-combinator"` for
its native two-sided connectors (ADR-0005); only the collision/selection boxes, `sprites`, and
the per-direction `input_connection_points` / `output_connection_points` are overridden. Art
starts as a flat placeholder PNG (four directions + shadow), with Blender-rendered art tracked
as debt.

## Space-Age-conditional gating

Branched at data load on `mods["space-age"]`:

- **Vanilla**: recipe category `crafting` (2.1 spelling: `categories = { "crafting" }`);
  technology `riscv-combinator` prerequisites `{ advanced-combinators, processing-unit }`
  (`processing-unit` is the 2.1 blue-circuit tech — the 1.1 `advanced-electronics-2`).
  Ingredients: 5× selector-combinator, 2× processing-unit.
- **Space Age**: recipe `category = "electromagnetics"` (crafted only by the electromagnetic
  plant); technology prerequisite `{ electromagnetic-plant }`, which itself chains off
  `holmium-processing` (Fulgora) and so guarantees the plant exists; unit adds the
  electromagnetic science pack. Ingredients: 3× selector-combinator, 2× supercapacitor,
  3× processing-unit.

The selector combinator is an ingredient in both branches, tying the build to its own tech
gate. `info.json` gains `"(?) space-age"` as an optional dependency for load order.

## Consequences

- The repo now ships binary PNGs (placeholder first, real art later). `.gitattributes` already
  treats `*.png` / `*.blend` as binary and export-ignores `*.blend`.
- The recipe is `enabled = false`; a fresh game no longer starts with the combinator until the
  technology is researched. Pre-release (0.0.0), so **no migration** is provided — existing
  1×2 placements may be dropped on load and old saves should be restarted.
- Item balance: `stack_size = 10` and `weight = 100 kg` (rocket capacity =
  `default_rocket_lift_weight / weight` = 1 000 000 / 100 000 = **10**, i.e. one full stack per
  rocket).
- The hidden output combinator needs no geometry change: it is placed at the entity centre
  (`position = e.position`) and wired by connector id, not by tile geometry, so it survives the
  resize and rotation unchanged.
- The entity face shows the Hart's **run-state** via a script-driven `LuaRendering` overlay,
  not the native combinator operation symbol — the decider's decision logic is inert (ADR-0005),
  so the game has no Hart state to draw. `control.lua` creates the overlay on entity appear,
  re-points it on each mode transition (`stopped`/`running`/`paused`/`halted:pass`/`halted:fail`
  ·`error`), and destroys it on removal; updates are event-driven off the existing transitions in
  `inspector.lua` plus the on-tick self-halt check, so there is no per-tick polling. The overlay
  is world-global, unlike the per-player Inspector view state. This adds a "screen" region to the
  base sprite and five placeholder status glyphs.
- CONTEXT.md is untouched — this adds no domain vocabulary; the term "RISC-V Combinator" and the
  prototype id `riscv-combinator` are unchanged. This is an implementation/packaging decision,
  not a language one.
