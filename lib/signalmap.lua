-- Per-save, append-only Signal map (ADR-0006): every Factorio signal gets a small
-- integer ID the first time it is seen or named, and is never renumbered, so a
-- running Program image's baked IDs stay valid for the life of the save.
--
-- Pure data + methods; in-game it lives in `storage` and the metatable is
-- reattached on load (like the Hart). One instance is shared by the Assembler's
-- resolver and the Circuit-network controller so assemble-time and run-time IDs
-- always agree. IDs start at 1 (0 means "no signal").
local M = {}
M.__index = M

local function key(typ, name)
  return typ .. "\0" .. name
end

function M.new()
  return setmetatable({ ids = {}, names = {}, next = 1 }, M)
end

-- type, name -> id (append-only: same pair always returns the same id).
function M:lookup_or_alloc(typ, name)
  local k = key(typ, name)
  local id = self.ids[k]
  if not id then
    id = self.next
    self.ids[k] = id
    self.names[id] = { type = typ, name = name }
    self.next = id + 1
  end
  return id
end

-- id -> type, name (nil if the id was never allocated). Commit rebuilds SignalIDs
-- from this; a staged id absent here is dropped by the caller.
function M:reverse(id)
  local e = self.names[id]
  if e then
    return e.type, e.name
  end
end

return M
