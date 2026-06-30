# In-game Manual via Booktorio + Informatron over a neutral IR

The mod ships a chaptered in-game RISC-V reference (the **Manual**, see CONTEXT.md) as
a comprehensive resource for writing assembly on the Hart. Base Factorio 2.x offers no
system fit for this: Tips and Tricks is unlock-gated, tableless, and notification-driven;
Factoriopedia is prototype-keyed with no chaptered prose or real tables. So the Manual is
rendered through two third-party documentation mods — **Informatron** and **Booktorio** —
authored once as a neutral block-list intermediate representation (headings, paragraphs,
tables, structured instruction rows, code) and fed to each backend by a thin adapter:
Booktorio consumes a declarative `add_thread` topic table at control init; Informatron
consumes `informatron_menu` / `informatron_page_content` callbacks that build LuaGuiElements
at view time. One source of truth; a new extension appends one chapter; a backend that is
not installed simply has its adapter skipped.

## Considered Options

- **Double-authored** (write each page as Booktorio topics *and* as Informatron GUI code) —
  rejected: a declarative backend and a callback backend would drift, and every edit is
  double-entry.
- **Built-in zero-dependency viewer** (a third adapter rendering the same IR into a mod-owned
  GUI, so docs survive with neither mod installed) — rejected for now: extra GUI surface to
  maintain; the IR keeps the door open to add it later as just another adapter.
- **A base-game system** (Tips and Tricks / Factoriopedia) — rejected: neither supports a
  chaptered, table-heavy reference.

## Consequences

- Content lives **inline in Lua doc modules**, not locale `.cfg`: the prose/table volume makes
  `.cfg` hostile and a niche RV32 mod is unlikely to be translated. The IR accepts a
  `LocalisedString` anywhere a string goes, so per-page locale migration stays possible later.
- The Manual documents the **honest subset** — only the mnemonics/CSRs/directives the
  Assembler actually accepts (RV32IM_Zicsr, M-mode, no A/F/D/C, no S/U mode, misaligned access
  allowed) — derived from real behaviour, not the ISA name or code comments (some of which
  already misstate coverage). Instruction/register/CSR/directive pages use structured rows; a
  busted test assembles every documented mnemonic so the Manual cannot claim what the
  Assembler rejects.
- `info.json` moves to **`factorio_version` 2.1**, dropping 2.0 users, to use the 2.1
  `recommended` dependency flag for `informatron`. `Booktorio` stays a plain `?` optional.
  Both registrations guard on `remote.interfaces` so a missing backend is a no-op.
- Runnable Booktorio `TopicBlueprint` examples are deferred until blueprint state-preservation
  (ADR-0009) lands; until then examples are plain code-text, which both backends render.
