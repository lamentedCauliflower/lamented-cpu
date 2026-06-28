-- Circuit-network controller (ADR-0005): a pure, engine-independent memory-mapped
-- peripheral at a fixed low base. It never calls a Factorio API -- it takes the
-- input wires as plain red/green tables and the Hart's memory, fills the Input
-- snapshot on Sample, and drains the Output staging to a plain output set on
-- Commit. The engine adapter (control.lua) does the real wire reads/writes; the
-- busted suite drives the same two entry points with fake tables.
--
-- Memory map (the ABI the Program image addresses with lw/sw), offsets from BASE:
--   0x000 STATUS    (RO) bit0 = snapshot overflow
--   0x004 SAMPLE    (WO) doorbell; value = colour mask (1=red 2=green 3=both)
--   0x008 COMMIT    (WO) doorbell; flush staging
--   0x100 SNAPSHOT       word0 = count, then (id, value) pairs  <- Sample fills
--   0x800 STAGING        word0 = count, then (id, value) pairs  <- program fills
-- The two buffers cannot both sit in one +/-2KiB lw/sw window, so programs keep a
-- base register per region (ADR-0005).
local rv = require("lib.rvbit")
local band, bor, bnot, u32, signed = rv.band, rv.bor, rv.bnot, rv.u32, rv.signed

local STATUS_OVERFLOW = 1 -- bit0: last Sample truncated
local STATUS_DROP = 2 -- bit1: last Commit dropped an unmapped id

local M = {}

M.BASE = 0x10000000
M.STATUS = 0x000
M.SAMPLE = 0x004
M.COMMIT = 0x008
M.SNAPSHOT = 0x100
M.STAGING = 0x800
M.CAP = 256 -- (id, value) entries per buffer

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

-- Fill the Input snapshot from the input wires. `input` = { red = {id=value},
-- green = {id=value} }; ids are already Signal-map IDs (the adapter mapped them).
function M.sample(mem, input, colour)
  local merged = merge(input, colour)
  local ids = {}
  for id in pairs(merged) do
    ids[#ids + 1] = id
  end
  table.sort(ids) -- deterministic snapshot order so programs can scan it
  local n, overflow = #ids, false
  if n > M.CAP then -- truncate to the lowest-id CAP entries, flag overflow
    n, overflow = M.CAP, true
  end
  mem:w32(M.BASE + M.SNAPSHOT, n)
  for i = 1, n do
    local at = M.BASE + M.SNAPSHOT + 4 + (i - 1) * 8
    mem:w32(at, ids[i])
    mem:w32(at + 4, u32(merged[ids[i]]))
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
