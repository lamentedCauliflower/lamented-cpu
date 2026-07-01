# Blueprint / copy / clone preserves source, not a live image

Copying a RISC-V Combinator — by blueprint, settings-paste, or clone — preserves only its
**configuration** (the assembly source and the master-enable flag), never the Hart's live
execution state (registers, pc, CSRs, memory, run mode). The source and enable ride in the
entity's blueprint `tags` (a versioned table `{v=1, source, enabled}`) written in
`on_player_setup_blueprint` and read back in the build events; settings-paste and clone copy
the same two fields. A built/pasted/cloned combinator starts **stopped** and reassembles from
source on the next Run. Hand-placing a fresh combinator still seeds the tutorial `DEFAULT_SRC`.

## Why not the live image

A Program image's memory holds **per-save signal-map IDs** (ADR-0006): IDs allocated in *this*
save that mean nothing in another. Blueprints cross saves, so a frozen image would carry
garbage IDs. Programs are portable **as source**, never as images (ADR-0004) — so a blueprint
*cannot* correctly carry live memory even if we wanted it to. Beyond that constraint, template
semantics demand it: stamping N copies should yield N CPUs running the program from reset, not
N frozen at one author's old register snapshot — matching how vanilla combinators blueprint
their settings, not transient wire values.

## Consequences

- The hidden output combinator stays `not-blueprintable` / `not-deconstructable`; it never
  enters a blueprint and is recreated alongside the visible entity on build and on clone.
- Pasting source onto a *running* destination marks it dirty and forces it to stopped, mirroring
  how the editor blocks edits while running.
- Undo/redo and blueprint-string export/import need no extra handling — they flow through the
  same tags.
- The Inspector's per-player view state (memory base, region) is transient UI, not entity
  configuration, and is not carried.
- This unblocks runnable Booktorio `TopicBlueprint` examples in the Manual (ADR-0008): an example
  combinator can now be blueprinted with its source intact.
