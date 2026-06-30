# In-game Manual via Informatron over a neutral IR

The mod ships a chaptered in-game RISC-V reference (the **Manual**, see CONTEXT.md) as
a comprehensive resource for writing assembly on the Hart. Base Factorio 2.x offers no
system fit for this: Tips and Tricks is unlock-gated, tableless, and notification-driven;
Factoriopedia is prototype-keyed with no chaptered prose or real tables. So the Manual is
rendered through the third-party **Informatron** documentation mod, authored once as a
neutral block-list intermediate representation (headings, paragraphs, tables, structured
instruction rows, code) and fed to the backend by a thin adapter: Informatron consumes
`informatron_menu` / `informatron_page_content` callbacks that build LuaGuiElements at view
time. One source of truth; a new extension appends one chapter; a backend that is not
installed simply has its adapter skipped.

## Considered Options

- **Inline GUI code** (build the LuaGuiElements directly per page, no IR) — rejected: the
  IR keeps content declarative and testable (a busted pass walks it to assemble every
  documented mnemonic and example), and keeps the door open to a second renderer.
- **A second backend, Booktorio** (render the same IR into Booktorio threads too) —
  evaluated and dropped: Booktorio has not been updated since Factorio 1.1 and exposes no
  way to open it programmatically, so it is not worth carrying. The IR means adding it back
  later is just one more adapter if it is ever revived.
- **Built-in zero-dependency viewer** (a mod-owned GUI rendering the same IR, so docs
  survive with no doc mod installed) — deferred for now: extra GUI surface to maintain; the
  IR keeps it cheap to add later as just another adapter.
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
- `info.json` declares `informatron` as a `?` optional dependency, guarded on
  `remote.interfaces` so a missing backend is a no-op. Moving to `factorio_version` 2.1 to use
  the 2.1 `recommended` dependency flag is deferred until a 2.1 engine is in the toolchain;
  the current engine is 2.0.76, and bumping would make the mod fail to load there.
- The Inspector's Manual button opens Informatron via `informatron_open_to_page`.
