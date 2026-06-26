# Commit prebuilt riscv-tests ELFs as fixtures; no toolchain in CI

The compiled `riscv-tests` ELFs (from a pinned upstream revision) are committed under
`spec/fixtures/riscv-tests/` and consumed directly by the `busted` gate, which parses
their `.symtab` to find `tohost`. A devenv command regenerates them via the RISC-V
cross-toolchain; that toolchain is **not** part of the CI test gate.

## Considered Options

- **Commit prebuilt ELFs (chosen)** — CI stays fast and hermetic with no
  `riscv-gnu-toolchain` fetch, matching the repo's existing habit of committing
  `benchmark/*.zip` fixtures. Cost: opaque binaries in git, refreshed manually.
- **Build in CI** — add the cross-toolchain to `devenv.nix` and compile every run.
  Nothing opaque committed, but a heavy cold fetch on top of the already-uncacheable
  unfree Factorio binary.

## Consequences

Refreshing tests is a deliberate, reviewed act (rerun the command, commit the new ELFs),
not an implicit consequence of a CI run. The fixtures' upstream revision must be pinned
and recorded so regeneration is reproducible.
