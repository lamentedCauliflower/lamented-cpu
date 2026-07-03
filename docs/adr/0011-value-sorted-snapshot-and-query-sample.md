# Snapshot pairs sort by value, and targeted reads are a Query sample

The Input snapshot's `(id, value)` pairs were ordered ascending by Signal-map ID. But
those IDs are per-save and append-only (ADR-0006) — their numeric order carries no
meaning a program can use, and at one instruction per tick a program cannot afford to
scan 256 pairs for the one signal it wants. Two changes, one per access pattern:

- **Full sample** pairs now sort **descending by signed value**, ties ascending by id.
  The first pair is always the strongest signal — the thing a program most often wants —
  and overflow truncation keeps the top 256 instead of an arbitrary id-range. One rule:
  the snapshot is the head of the sorted list.
- **Targeted reads** get a **Query sample**: bit2 of the `SAMPLE` doorbell value flips
  the Sample into answering the 16 program-owned **Query registers** (ids at
  `0x010`–`0x04C`, written once, persistent). The snapshot block then holds a hit count
  and exactly 16 positional echo pairs — `Qn` → pair *n*, `(id, value)`, misses and
  unused slots value 0 — so every answer is at a fixed offset, O(1) for the program.
  Steady state costs 16 loads per cycle, no stores. `STATUS` bit0 now means "most
  recent Sample of either kind truncated"; a query never truncates, so it clears it.

## Considered Options

- **Keep id order** — enables binary search (~64 instructions) for one signal. Rejected:
  order is meaningless for every other use, and the query mode answers the lookup case
  in 1 load, making binary search pointless.
- **Single lookup doorbell** (write id, controller writes value back) — O(1) but one
  signal per doorbell store, and a read-triggered variant is impossible: the Hart's load
  path must stay hook-free for conformance (ADR-0005).
- **Per-Q store-watch doorbells** (store an id to Qn, the word becomes the value) —
  answers immediately from the last snapshot, but widens the watched store window from
  2 addresses to 18 and consumes the id on every read, forcing a rewrite per cycle.
  The Sample-time fill keeps ids standing and adds zero watches.
- **Separate result block for queries** — no mode bit, both layouts live at once.
  Rejected: burns another fixed window for what is temporally exclusive data anyway;
  the two Sample kinds already cannot race within one instruction.

## Consequences

- ABI change from 1.0.x: programs relying on "ascending by id" or "lowest 256 kept"
  (as the Manual documented) must re-read the Circuit I/O chapter. Accepted as a
  minor-version feature — the mod is days old.
- The Query registers sit just past the 16-byte doorbell window `hart.lua` watches
  (`0x010` is the first unwatched offset), so id stores are plain RAM writes — the
  conformance-critical load path and the store-watch surface are both untouched.
- A query sample writes only word0 and 16 pairs; the snapshot tail beyond `0x184` is
  stale (whatever the last full sample left). Programs read only what the mode defines.
- A red/green zero-sum counts as a hit (the signal is on the wires) but reads as
  value 0, indistinguishable per-slot from a miss; the hit count is the tiebreaker.
