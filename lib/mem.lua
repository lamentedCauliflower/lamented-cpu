-- Sparse, little-endian Hart memory (ADR-0002 / issue #3).
-- ponytail: word-granular (keyed by 4-aligned address). Byte/halfword access and
-- misaligned-trap handling arrive with the load/store slice (#4); the walking
-- skeleton only touches aligned words (instruction fetch + the tohost store).
local rv = require("rvbit")
local M = {}
M.__index = M

function M.new()
  return setmetatable({ w = {} }, M)
end

function M:r32(addr)
  return self.w[addr] or 0
end

function M:w32(addr, value)
  self.w[addr] = rv.u32(value)
end

return M
