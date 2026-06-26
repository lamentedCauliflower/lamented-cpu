# PRD: Factorio Mod Development Environment (devenv)

## Problem Statement

A developer who clones this template to build a Factorio mod has no batteries-included
development environment. There is no test runner, no linter, no formatter, no way to
launch the game with the in-progress mod loaded, and no way to benchmark the mod's
runtime performance. Every mod author has to assemble this themselves, and most never
do — so mods ship with no unit tests, no proof they even load in the real engine, and
no performance signal.

Factorio modding makes this harder than a normal Lua project:

- The game runs **stock Lua 5.2** (not LuaJIT, not 5.4), and injects globals
  (`game`, `script`, `defines`, `data`, `prototypes`, `settings`, `remote`) that do
  not exist outside the engine — so plain test tooling cannot load mod code directly.
- The full game client is **unfree** and needs a Factorio account token to fetch at
  build time, while the **headless** server is free and needs no token.
- **Stable** and **experimental** game versions currently have **breaking API
  differences**, so a mod targets exactly one channel at a time and cannot be run
  against both simultaneously.

The developer needs an environment that hides all of this behind a few commands and
works on first `direnv allow`.

## Solution

Ship a `devenv` (Nix-based) development environment **with the template**, so every
mod created from it inherits a working setup. The environment provides:

- **busted** (pinned to Lua 5.2) for fast unit tests of pure-logic modules, with a
  minimal hand-written stub layer for the engine globals.
- **factorio-headless** / **factorio-headless-experimental** (free, no token) for an
  in-engine "does the mod actually load" smoke test and for performance benchmarking.
- The full **factorio** / **factorio-experimental** client as an **opt-in** package
  for manual play-testing.
- A small set of commands — `modtest`, `bench`, `play`, `lint`, `fmt`, `package` — that
  operate against a single active game **channel** (`stable` | `experimental`,
  defaulting to `experimental`), resolved from a per-invocation argument, then the
  `FACTORIO_CHANNEL` environment variable, then the default.
- Lua tooling (luacheck, stylua, lua-language-server), git hooks that guard formatting,
  linting, tests, and the conventional-commit convention the release pipeline depends
  on, and a lightweight CI workflow that runs the same `devenv test` command.
- A minimal, clearly-deletable **example mod** so that on first clone every command is
  green against real code.

All game state is kept in a project-local, gitignored `.factorio/` sandbox; the
machine's global `~/.factorio` is never touched.

## User Stories

1. As a mod developer, I want the dev environment to come with the template, so that I
   get a working setup the moment I clone my new repo.
2. As a mod developer, I want to run `direnv allow` (or `devenv shell`) once and have
   every tool present, so that I don't assemble a toolchain by hand.
3. As a mod developer, I want a one-screen command cheatsheet printed when I enter the
   shell, so that I can discover what the environment can do.
4. As a mod developer, I want `modtest` (and `devenv test`) to run my busted unit tests,
   so that I can verify pure logic quickly without launching the game.
5. As a mod developer, I want busted pinned to Lua 5.2, so that my tests run under the
   same Lua semantics as the game and don't pass on syntax the engine rejects.
6. As a mod developer, I want a minimal stub layer for engine globals (`defines`,
   `data`, etc.), so that I can unit-test modules that lightly reference the API.
7. As a mod developer, I want a `.busted` config that points the Lua path at my repo,
   so that `require("foo")` in a spec resolves to my mod's `foo.lua`.
8. As a mod developer, I want `modtest` to also run a headless load-smoke in the real
   engine, so that I catch data-stage and control-stage errors my mocked unit tests
   can never see.
9. As a mod developer, I want the load-smoke to fail the command on any engine error,
   so that a broken prototype or an `on_init` crash is caught as a non-zero exit.
10. As a mod developer, I want the load-smoke to use the free headless server, so that
    it needs no Factorio token and runs anywhere.
11. As a mod developer, I want `bench` to run the game's `--benchmark` against my mod,
    so that I get per-tick timing for performance work.
12. As a mod developer, I want `bench` to generate a fixed-seed save automatically when
    none is provided, so that the command works out of the box with nothing committed.
13. As a mod developer, I want to point `bench` at a committed representative save, so
    that I can benchmark a real built factory rather than an empty world.
14. As a mod developer, I want `play` to launch the full game client with my in-progress
    mod loaded, so that I can manually play-test it.
15. As a mod developer, I want `play` to symlink my working tree into the mods folder,
    so that edits are reflected without repackaging.
16. As a mod developer, I want `play` to fail with a clear message if the full client
    isn't built (because it needs my account token), so that I understand why and how
    to enable it, rather than seeing a cryptic Nix error.
17. As a mod developer, I want all game state (config, saves, logs, mods) confined to a
    gitignored `.factorio/` folder in my project, so that runs are reproducible and my
    global Factorio install is never modified.
18. As a mod developer, I want `test`, `bench`, and `play` to target one game channel
    at a time, so that I'm never accidentally running against an incompatible API.
19. As a mod developer, I want the channel to default to **experimental**, so that I
    catch breakage on the upcoming game version before it reaches stable.
20. As a mod developer, I want to override the channel per invocation (e.g. `test
    stable`), so that I can check a single command against the other channel.
21. As a mod developer, I want to pin a whole shell to a channel via `FACTORIO_CHANNEL`,
    so that I don't retype the channel on every command while migrating.
22. As a mod developer, I want an unknown channel value to error clearly listing the
    valid options, so that a typo doesn't silently run the wrong game.
23. As a mod developer, I want `lint` to run luacheck, so that I catch undefined
    globals and dead code statically.
24. As a mod developer, I want luacheck pre-configured with Factorio's globals declared
    read-only, so that real uses of `game`/`defines` aren't flagged while typos are.
25. As a mod developer, I want `fmt` to run stylua, so that my Lua is consistently
    formatted.
26. As a mod developer, I want stylua configured for the Lua dialect the game accepts,
    so that the formatter never rewrites my code into syntax the engine rejects.
27. As a mod developer, I want a lua-language-server config in the repo, so that my
    editor gives completion and diagnostics.
28. As a mod developer, I want documented (not silently-missing) steps to add the
    Factorio API type definitions to the language server, so that I know editor types
    are an opt-in fetch rather than assuming they're bundled.
29. As a mod developer, I want a `package` command that produces the release zip the
    way the release pipeline does, so that I can test packaging locally.
30. As a mod developer, I want pre-commit hooks that format and lint my changes, so
    that I never commit unformatted or lint-broken Lua.
31. As a mod developer, I want busted to run on pre-push rather than pre-commit, so
    that my commits stay fast but bad code still can't reach the remote.
32. As a mod developer, I want a commit-message hook that enforces conventional
    commits, so that I don't accidentally break the semantic-release versioning.
33. As a mod developer, I want all hooks to be easy to bypass with `--no-verify`, so
    that I'm not blocked in an emergency.
34. As a mod developer, I want a CI workflow that runs `devenv test` on every PR and
    non-main push, so that the mod is proven to load on the active channel before merge.
35. As a mod developer, I want CI to run the same command I run locally, so that "green
    locally" and "green in CI" mean the same thing.
36. As a mod developer, I want CI to use the free headless server, so that no Factorio
    token is required as a CI secret.
37. As a mod developer, I want CI to read the same channel knob, so that CI tracks the
    channel my mod currently targets.
38. As a mod developer, I do NOT want CI to run performance benchmarks, so that I'm not
    misled by noisy shared-runner timing.
39. As a mod developer, I want the existing release workflow left untouched, so that
    adding a dev environment doesn't risk my publishing pipeline.
40. As a mod developer cloning the template, I want a minimal example mod present, so
    that `test`, `bench`, and `play` all do something real on first run.
41. As a mod developer, I want the example mod's files loudly marked as deletable, so
    that I know exactly what to remove before writing my own mod.
42. As a mod developer, I want the example to demonstrate a pure module + its busted
    spec + a stub, a data-stage prototype, and a control-stage handler, so that I have
    a working pattern for each layer.
43. As a mod developer, I want the example to target the experimental API (the default
    channel), so that it is green under the out-of-the-box configuration.
44. As a mod developer who only wants unit tests, I want the heavy unfree game download
    to be avoidable, so that I can run busted without pulling the full client.
45. As a template maintainer, I want the environment expressed as `devenv.nix` /
    `devenv.yaml`, so that it's reproducible and version-pinned via `devenv.lock`.
46. As a template maintainer, I want `allow_unfree` set, so that the unfree Factorio
    packages evaluate at all.
47. As a template maintainer, I want game versions to float on rolling nixpkgs but pin
    per-checkout via the lockfile, so that clones are reproducible and `devenv update`
    is the explicit way to bump.
48. As a template maintainer, I want auto-fetching dependency mods from the portal
    documented as a non-goal, so that contributors know it's deliberately out of scope.
49. As a mod developer migrating from experimental to stable, I want to flip a single
    `FACTORIO_CHANNEL` knob and have local commands and CI follow, so that the
    migration is one deliberate switch rather than many edits.
50. As a mod developer, I want switching channels to never mean "run against both at
    once", so that the breaking API differences between channels can't corrupt a run.

## Implementation Decisions

**Distribution model.** The environment ships with the template (path A); consumers
inherit it. Pure unit testing (busted) must be usable without pulling the unfree game,
so the headless/full game packages must not be a hard dependency of the busted path.

**Game packages.**
- Benchmarking and the load-smoke use **factorio-headless** /
  **factorio-headless-experimental** (free, no token, CI-runnable). These are on by
  default.
- The full **factorio** / **factorio-experimental** client is **opt-in** (it requires
  the developer's Factorio account token at Nix build time) and powers `play` only.
- All Factorio packages are unfree; `allow_unfree: true` is set in `devenv.yaml`.

**Single-channel model.** Stable and experimental have breaking API differences. The
environment operates on exactly **one** active channel per invocation — never both.
The dropped concept: there is no "compare stable vs experimental in one run" command.

**Channel resolution** (design sketch, encodes the precedence decision):

```
resolve_channel(arg):
    c := arg            if provided
       else $FACTORIO_CHANNEL  if set
       else "experimental"     # default

    case c of
        "experimental" -> headless: factorio-headless-experimental
                          client:   factorio-experimental
        "stable"       -> headless: factorio-headless
                          client:   factorio
        _              -> error: "unknown channel '$c' (expected: stable | experimental)"
```

**Command surface.** Simple commands are `devenv` scripts; commands with a real setup
ordering (ensure isolated sandbox, symlink the mod, write `mod-list.json`, ensure a
save) are `devenv` tasks.

| Command         | Channel-aware | Default      | Behaviour |
| --------------- | ------------- | ------------ | --------- |
| `modtest [chan]`| yes (smoke)   | experimental | busted (channel-agnostic) then headless load-smoke on channel; also wired as `enterTest`, so `devenv test` runs the same gate (channel via `FACTORIO_CHANNEL`). Named `modtest` because `test` is a shell builtin |
| `bench [chan]`  | yes           | experimental | headless `--benchmark` on channel; auto-creates a fixed-seed save if none given |
| `play [chan]`   | yes           | experimental | full client on channel with the mod symlinked; clean error if client not built |
| `lint`          | no            | —            | luacheck |
| `fmt`           | no            | —            | stylua |
| `package`       | no            | —            | the release zip via the existing `git archive` recipe |

**Isolated game state.** A project-local, gitignored `.factorio/` directory holds
`config.ini`, `mods/`, `saves/`, and logs. The working tree is symlinked into
`.factorio/mods/<internal-mod-name>` so edits reflect instantly; a generated
`mod-list.json` enables `base` plus the mod. The game is always launched with
`--config .factorio/config.ini --mod-directory .factorio/mods`. The global
`~/.factorio` is never read or written.

**Benchmark save.** `bench` takes a save path variable. Default: `--create` a
fixed-seed throwaway save (no binary committed to the template). Override: point the
variable at a committed `benchmark/*.zip` representative save for real perf numbers.

**busted fake layer.** Minimal hand-written stubs plus discipline — tests target pure
modules; the example ships a small stub defining the engine globals it touches, not a
heavyweight third-party mock framework. A `.busted` config sets `lua_path` to the repo
root and `spec/`.

**Lua tooling.** luacheck with a `.luacheckrc` declaring Factorio globals read-only;
stylua with a `.stylua.toml` targeting the accepted Lua dialect; lua-language-server
with a `.luarc.json`. The Factorio API **type definitions are a documented opt-in
fetch** (FMTK is not packaged in nixpkgs), not bundled.

**Git hooks** (via devenv's git-hooks integration, which generates the already-gitignored
`.pre-commit-config.yaml`):
- pre-commit: stylua + luacheck (fast, auto-fixable)
- pre-push: busted
- commit-msg: conventional-commit lint (guards the semantic-release pipeline)
- All bypassable with `--no-verify`; enabled by default.

**CI.** A new lightweight `ci.yml`: on PR and non-main push, install Nix + devenv and
run `devenv test` (busted + headless load-smoke) against the single active channel
(reads the same `FACTORIO_CHANNEL`, default experimental). No perf-bench in CI (runner
noise). The existing `release.yml` is untouched.

**Example mod.** Minimal and loudly marked deletable: a pure `lib/` module with a
busted spec and a stub, a one-prototype `data` stage, and a `control` stage handler
exercised by the smoke and benchmark. It targets the experimental API.

**Pinning.** Game versions float on rolling nixpkgs, pinned per-checkout by
`devenv.lock`; `devenv update` is the explicit bump. The `enterShell` prints a command
cheatsheet. `.gitignore` gains `.factorio/`.

## Testing Decisions

A good test here exercises **external behaviour at the highest seam**, not Nix
internals or script wiring. Three seams, preferring reuse over new ones:

1. **`devenv test` (top seam).** The canonical gate: the environment evaluates,
   packages resolve, busted passes, and the headless load-smoke exits zero. CI reuses
   this exact command, so there is no separate CI seam. A passing `devenv test` is the
   single definition of "this mod is sane on the active channel".

2. **Channel resolution (unit seam).** The one piece of genuine logic. Tested in
   isolation by feeding `(arg, FACTORIO_CHANNEL)` combinations and asserting the chosen
   package/directory — including the unknown-channel error path. This must not require
   launching the game.

3. **busted example (the test is the seam).** `lib/<thing>.lua` ↔
   `spec/<thing>_spec.lua` demonstrates and verifies that the busted path, Lua 5.2
   pinning, stub layer, and `.busted` path config all work together.

4. **Headless load-smoke (integration seam).** `factorio-headless --benchmark <tiny
   save> --benchmark-ticks 1 --mod-directory .factorio/mods` — the exit code is the
   assertion: any data- or control-stage error fails it. Free, no token.

Tests assert observable outcomes (exit codes, benchmark output present, resolved
channel) rather than implementation details of the scripts.

**Prior art:** none in this repo — it currently has only a stub `enterTest` that greps
the git version, which this work replaces. This PRD establishes the test infrastructure.

## Out of Scope

- **Auto-fetching dependency mods** from the Factorio Mod Portal (needs a token and
  portal API integration). Documented as a deliberate non-goal.
- **Performance benchmarking in CI** — shared runners are too noisy for reliable
  per-tick timing; `bench` stays a local tool.
- **Running one mod against both channels simultaneously** — impossible given breaking
  API differences; explicitly removed from the design.
- **A heavyweight Factorio mock framework** (FMTK runtime mocks, faketorio) — the
  template ships a minimal stub pattern instead.
- **Bundling Factorio API type definitions** for the language server — provided as a
  documented opt-in fetch, not vendored.
- **Changes to the existing `release.yml` / semantic-release pipeline.**
- **In-game automated test harnesses** (e.g. `--instrument-mod` based test runners) —
  noted as a possible future direction, not built here.
- **Multiplayer / dedicated-server workflows.**

## Further Notes

- At the time of writing, nixpkgs `factorio-headless` and `factorio-headless-experimental`
  are both `2.0.76`, so the two channels are momentarily identical; the single-channel
  design matters for the periods when experimental leads stable with breaking changes.
- cachix cannot cache the unfree Factorio binary, so CI re-fetches it (~100–200 MB)
  from the Factorio CDN each run. This is tolerated, not optimised.
- The full client's Nix build needs the developer's Factorio account token; this is why
  `play` is opt-in and degrades to a clear error rather than a hard dependency.
- `.gitignore` already ignores `.pre-commit-config.yaml` and the `devenv.*` artifacts,
  which is consistent with generating hooks through devenv.
