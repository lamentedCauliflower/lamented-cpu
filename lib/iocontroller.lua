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
local band, u32, signed = rv.band, rv.u32, rv.signed

local M = {}

M.BASE = 0x10000000
M.STATUS = 0x000
M.SAMPLE = 0x004
M.COMMIT = 0x008
M.SNAPSHOT = 0x100
M.STAGING = 0x800
M.CAP = 256 -- (id, value) entries per buffer

-- ponytail: skeleton merge -- red/green selected by the colour mask, "both" sums
-- same-id values (Factorio's native circuit merge). Full colour/overflow rigor is
-- slice 2 (#12); the cap + STATUS overflow bit are already wired here.
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
  local n, overflow = #ids, 0
  if n > M.CAP then
    n, overflow = M.CAP, 1
  end
  mem:w32(M.BASE + M.SNAPSHOT, n)
  for i = 1, n do
    local at = M.BASE + M.SNAPSHOT + 4 + (i - 1) * 8
    mem:w32(at, ids[i])
    mem:w32(at + 4, u32(merged[ids[i]]))
  end
  mem:w32(M.BASE + M.STATUS, overflow)
end

-- Drain the Output staging to a plain set [{ id, value }], signed values. The
-- adapter turns each id back into a SignalID via the Signal map's reverse lookup.
function M.commit(mem)
  local n = mem:r32(M.BASE + M.STAGING)
  if n > M.CAP then
    n = M.CAP
  end
  local set = {}
  for i = 1, n do
    local at = M.BASE + M.STAGING + 4 + (i - 1) * 8
    set[#set + 1] = { id = mem:r32(at), value = signed(mem:r32(at + 4)) }
  end
  return set
end

return M
