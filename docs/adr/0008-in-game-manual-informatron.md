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
- `info.json` declares `informatron` as a `+` recommended dependency, guarded on
  `remote.interfaces` so a missing backend is a no-op. Done 2026-07-01: `factorio_version` is
  now `2.1` (the recommended `+` prefix needs 2.1), validated on the experimental headless
  **2.1.9** with **informatron 0.5.0**. nixpkgs still packages only 2.0.76, so `devenv.nix`
  overrides the experimental headless src to 2.1.9 until nixpkgs catches up.
- The Inspector's Manual button opens Informatron via `informatron_open_to_page`.
- Done 2026-07-03: the anticipated second renderer exists — the **Wiki mirror**
  (CONTEXT.md), `lib/manual/markdown.lua`, renders the same IR to GitHub-wiki Markdown;
  `.github/workflows/wiki.yml` publishes it to the wiki repo on every push to main. The
  wiki is a build artifact, never hand-edited.
