# Vector conformance via riscv-vector-tests at fixed VLEN=128

The Hart grows the **Zve32x** vector subset (integer-only RVV 1.0, ELEN=32 — full V
mandates vector FP, which needs the F extension the Hart lacks). Upstream `riscv-tests`
has no usable RVV 1.0 coverage, so V gets a second oracle: **riscv-vector-tests**
(`chipsalliance/riscv-vector-tests`), whose generated, self-checking assembly sources
are vendored — flattened with `cpp` against our Test env, committed as plain `.s`
fixtures, and assembled in-Lua — exactly the ADR-0004 pipeline. Golden values are baked
by Spike at generation time for a fixed **VLEN=128**, which thereby becomes part of the
mod's architecture, frozen alongside the fixture pin.

The ship gate is the **full `zve32x` generator preset green**: the conformance
allowlist grows slice by slice during development (the existing pattern), but the
`misa` V bit, the Manual's vector chapter, and any in-game claim of V stay off until
every generated test passes. Where the RVV spec allows implementation choice (e.g.
tail-/mask-agnostic element values), the generated golden values — i.e. Spike's
behaviour — are the tie-breaker, consistent with "if a behaviour disagrees with the
tests, the tests are right".

## Considered Options

- **riscv-vector-tests, vendored generated `.s` (chosen)** — the community's de facto
  RVV oracle; self-checking via the same `tohost` convention and `riscv-test-env` swap
  point our Test env already implements. Generation (Go + Spike) happens only at vendor
  time, like `cpp` — never on the CI gate path.
- **riscv-arch-test / RISCOF** — stronger authority claim, but signature-based
  (memory-dump diff against a reference model), a different harness shape than
  `tohost` pass/fail, and its RVV coverage is younger.
- **Own tests, differential against Spike** — full control, weakest external-authority
  claim; contradicts conformance-first.
- **Full V instead of Zve32x** — requires ELEN=64 and vector FP on an FP-less RV32IM
  hart; Zve32x is the subset the architecture actually admits.

## Consequences

- **VLEN=128 is frozen.** Golden values and each save's serialized v-register state
  (32 × 16 bytes, plain data) bake it in; changing it means regenerating fixtures and
  breaking saves. 128 bounds the worst case at 128 element ops per instruction (e8, m8).
- Fixtures are committed as plain `.s` like the existing 56 — diffable, but the repo
  grows by the full generated suite and CI assembles all of it in-Lua each run. If
  gate time becomes painful, that is a CI problem to solve, not a licence to shrink
  the gate.
- The pinned generator + Spike revisions and the generation config (VLEN=128, XLEN=32,
  `zve32x`) must be recorded so regeneration is reproducible, mirroring the
  `riscv-tests` pin.
- The Test env grows vector support: enabling `mstatus.VS` at reset and whatever
  macros the generated preamble needs. The Assembler must accept the generated
  sources' full syntax (vector mnemonics, `v0.t` masks, `vtype` operand lists).
- In-game there is no research gate and no per-instruction cost model: V is present
  from ship (once green), and a vector instruction costs one tick like any other —
  the throughput win is the feature.
