-- Circuit-network controller (ADR-0005): a pure, engine-independent memory-mapped
-- peripheral at a fixed low base. It never calls a Factorio API -- it takes the
-- input wires as plain red/green tables and the Hart's memory, fills the Input
-- snapshot on Sample, and drains the Output staging to a plain output set on
-- Commit. The engine adapter (control.lua) does the real wire reads/writes; the
-- busted suite drives the same two entry points with fake tables.
--
-- Memory map (the ABI the Program image addresses with lw/sw), offsets from BASE:
--   0x000 STATUS    (RO) bit0 = snapshot overflow
--   0x004 SAMPLE    (WO) doorbell; bit0 = red, bit1 = green, bit2 = query mode
--   0x008 COMMIT    (WO) doorbell; flush staging
--   0x010 Q1..Q16   (RW) Query registers: signal ids, program-owned, persistent
--   0x100 SNAPSHOT       full sample:  word0 = pair count, then (id, value)
--                        pairs descending by signed value, ties ascending by id
--                        query sample: word0 = hit count, then exactly 16
--                        (id, value) pairs, Qn -> pair n (miss/unused = value 0)
--   0x800 STAGING        word0 = count, then (id, value) pairs  <- program fills
-- The two buffers cannot both sit in one +/-2KiB lw/sw window, so programs keep a
-- base register per region (ADR-0005). Sort order, truncation, and the query
-- mode are ADR-0011. The Query registers sit just past the 16-byte doorbell
-- window hart.lua watches, so id stores are plain RAM writes.
local rv = require("lib.rvbit")
local band, bor, bnot, u32, signed = rv.band, rv.bor, rv.bnot, rv.u32, rv.signed

local STATUS_OVERFLOW = 1 -- bit0: last Sample truncated
local STATUS_DROP = 2 -- bit1: last Commit dropped an unmapped id

local M = {}

M.BASE = 0x10000000
M.STATUS = 0x000
M.SAMPLE = 0x004
M.COMMIT = 0x008
M.QUERY = 0x010 -- Q1..Q16, one id word each
M.QCOUNT = 16
M.SNAPSHOT = 0x100
M.STAGING = 0x800
M.CAP = 256 -- (id, value) entries per buffer
M.QUERY_MODE = 4 -- SAMPLE doorbell bit2: query sample instead of full sample

-- Merge the chosen wires: colour mask bit0 = red, bit1 = green; "both" (3) sums
-- same-id values across red and green, matching Factorio's native circuit merge.
local function merge(input, colour)
  local out = {}
  if band(colour, 1) ~= 0 then
    for id, v in pairs(input.red or {}) do
      out[id] = (out[id] or 0) + v
    end
  end
  if band(colour, 2) ~= 0 then
    for id, v in pairs(input.green or {}) do
      out[id] = (out[id] or 0) + v
    end
  end
  return out
end

-- Query sample (ADR-0011): answer the program's standing Query registers from
-- the merged input instead of dumping everything. Pair n mirrors Qn even when
-- Q slots are unused, so results are at fixed offsets; the id is echoed back
-- and a miss (or unused Qn = 0) reads as value 0, matching an absent signal.
-- word0 counts hits -- ids present in the merge, a red/green zero-sum included.
local function query(mem, merged)
  local hits = 0
  for i = 1, M.QCOUNT do
    local id = mem:r32(M.BASE + M.QUERY + (i - 1) * 4)
    local v = merged[id]
    if v then
      hits = hits + 1
    end
    local at = M.BASE + M.SNAPSHOT + 4 + (i - 1) * 8
    mem:w32(at, id)
    mem:w32(at + 4, u32(v or 0))
  end
  mem:w32(M.BASE + M.SNAPSHOT, hits)
end

-- Full sample: dump the whole merge, largest signal first. Programs read the
-- most significant signals at the top; a truncated snapshot keeps the top CAP.
-- Values compare as the signed words the program will lw (a wrapped sum sorts
-- where its wrapped value belongs); ties break ascending by id for determinism.
local function full(mem, merged)
  local ids = {}
  for id in pairs(merged) do
    ids[#ids + 1] = id
  end
  table.sort(ids, function(a, b)
    local va, vb = signed(u32(merged[a])), signed(u32(merged[b]))
    if va ~= vb then
      return va > vb
    end
    return a < b
  end)
  local n = #ids
  if n > M.CAP then
    n = M.CAP
  end
  mem:w32(M.BASE + M.SNAPSHOT, n)
  for i = 1, n do
    local at = M.BASE + M.SNAPSHOT + 4 + (i - 1) * 8
    mem:w32(at, ids[i])
    mem:w32(at + 4, u32(merged[ids[i]]))
  end
  return #ids > M.CAP
end

-- Fill the Input snapshot from the input wires. `input` = { red = {id=value},
-- green = {id=value} }; ids are already Signal-map IDs (the adapter mapped them).
-- `colour` is the raw SAMPLE doorbell value: bit0/bit1 pick the wires, bit2
-- picks a query sample over a full one. bit0 of STATUS reflects the most recent
-- Sample of either kind -- a query never truncates, so it clears the bit.
function M.sample(mem, input, colour)
  local merged = merge(input, colour)
  local overflow = false
  if band(colour, M.QUERY_MODE) ~= 0 then
    query(mem, merged)
  else
    overflow = full(mem, merged)
  end
  -- own STATUS bit0 only; read-modify-write so Commit's drop flag (slice 3)
  -- survives a later Sample.
  local status = band(mem:r32(M.BASE + M.STATUS), bnot(STATUS_OVERFLOW))
  mem:w32(M.BASE + M.STATUS, overflow and bor(status, STATUS_OVERFLOW) or status)
end

-- Drain the whole Output staging in one read (atomic: the program builds staging
-- in RAM, invisible, until this single Commit flushes it) to a plain set of
-- { id, type, name, value } with signed values. Each staged id is resolved through
-- the Signal map's reverse table; an id absent from it is dropped and STATUS bit1
-- is set, so the adapter just builds SignalIDs from type/name. RMW preserves the
-- Sample overflow bit.
function M.commit(mem, signalmap)
  local n = mem:r32(M.BASE + M.STAGING)
  if n > M.CAP then
    n = M.CAP
  end
  local set, dropped = {}, false
  for i = 1, n do
    local at = M.BASE + M.STAGING + 4 + (i - 1) * 8
    local id = mem:r32(at)
    local typ, name = signalmap:reverse(id)
    if typ then
      set[#set + 1] = { id = id, type = typ, name = name, value = signed(mem:r32(at + 4)) }
    else
      dropped = true
    end
  end
  local status = band(mem:r32(M.BASE + M.STATUS), bnot(STATUS_DROP))
  mem:w32(M.BASE + M.STATUS, dropped and bor(status, STATUS_DROP) or status)
  return set
end

return M
