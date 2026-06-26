# AGENTS.md

Guidance for AI agents working in this repository.

## What this repo is

A **template** for building Factorio mods. The repo root *is* the mod: `info.json`,
`locale/`, `changelog.txt`, and (once written) `data.lua` / `control.lua` / `lib/` live
at the top level. People click **Use this template** to start their own mod, so changes
here are inherited by every downstream mod — keep things generic and clearly marked.

Releases are automated: pushing to `main` triggers `semantic-release`, which reads
**conventional commits** to compute the version, generate the changelog, and publish to
the Factorio Mod Portal. See `README.md` for the commit-type → changelog-section table.

## Development environment

The dev environment is a **devenv** (`devenv.nix` / `devenv.yaml`). Its full design and
rationale are in [`docs/prd/devenv-mod-dev-env.md`](docs/prd/devenv-mod-dev-env.md) —
read that before changing the environment.

Commands the devenv provides:

| Command          | What it does |
| ---------------- | ------------ |
| `modtest [chan]` | busted unit tests, then a headless load-smoke in the real engine (`devenv test` runs the same gate; named `modtest` because `test` is a shell builtin) |
| `bench [chan]` | `--benchmark` the mod for per-tick timing (auto-creates a save if none) |
| `play [chan]`  | launch the full game client with the working tree mod loaded |
| `lint`         | luacheck |
| `fmt`          | stylua |
| `package`      | build the release zip locally (same `git archive` recipe as CI) |

## Conventions that matter

- **Conventional commits are mandatory.** They drive versioning and the changelog. A
  malformed `feat:`/`fix:` mis-versions or skips a release. A commit-msg hook enforces
  this; do not bypass it on `main`.
- **`main` is the release branch.** Pushing to `main` publishes. Do real work on a
  branch and merge when ready, unless the user explicitly wants to release.
- **Lua 5.2.** The game runs stock Lua 5.2 (not LuaJIT, not 5.4). busted is pinned to
  5.2 so tests share the game's semantics. Don't use 5.4-only syntax (`//`, native
  bitwise ops, integer/float split).
- **One game channel at a time.** `stable` and `experimental` have breaking API
  differences — never target both in one run. Channel resolves from a command argument,
  then `FACTORIO_CHANNEL`, then the default **experimental**. To migrate a mod between
  channels, flip the one knob.
- **Headless vs full client.** The free **headless** server powers `test`/`bench` and
  CI (no token). The full **client** (`play`) is **unfree and opt-in** — it needs the
  developer's Factorio account token to build, so it degrades to a clear error if absent.
- **Isolated game state.** All runtime state (config, saves, logs, the symlinked mod)
  lives in the gitignored `.factorio/` sandbox. Never read or write the machine's global
  `~/.factorio`.
- **Packaging.** The mod zip is built with `git archive` honoring `.gitattributes`
  `export-ignore`. To exclude a path from the released mod, mark it `export-ignore`.

## Testing

`devenv test` is the single gate — it runs busted (pure logic, mocked engine globals via
a minimal stub) and then a headless load-smoke (`factorio-headless --benchmark <save>
--benchmark-ticks 1`) whose exit code proves the mod actually loads in the engine. **CI
runs this exact command** on PRs and non-main pushes; there is no separate CI path.

Test external behaviour (exit codes, resolved channel, benchmark output), not script
internals. The channel-resolution logic is the one piece worth a dedicated unit test,
including its unknown-channel error path.

## Gotchas

- `*.zip` is gitignored (so packaged mods aren't committed) **except** `benchmark/*.zip`
  — representative benchmark saves are allowed to be committed.
- No performance benchmarking in CI: shared runners are too noisy. `bench` is local-only.
- cachix cannot cache the unfree Factorio binary, so CI re-fetches it each run.
- Leave `release.yml` / the semantic-release pipeline alone unless explicitly asked.

## Pointers

- `README.md` — template usage, repo setup, commit convention, packaging.
- `docs/prd/devenv-mod-dev-env.md` — the dev-environment design (source of truth).
- `info.json`, `.gitattributes`, `.releaserc` — mod metadata, packaging excludes,
  release config.
