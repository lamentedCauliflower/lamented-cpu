-- Sparse, little-endian Hart memory (ADR-0002).
-- ponytail: byte-keyed. Composing words from bytes makes misaligned access
-- (rv32ui-p-ma_data) just work, which is what the only vendored ma_data fixture
-- wants -- cheaper than a trap-and-emulate handler. Ceiling: one table entry per
-- written byte; swap for a word store + byte overlay if memory ever matters.
local rv = require("lib.rvbit")
local rsh = rv.rsh
local M = {}
M.__index = M

function M.new()
  return setmetatable({ b = {} }, M)
end

function M:rb(addr)
  return self.b[addr] or 0
end

function M:wb(addr, value)
  self.b[addr] = rv.band(value, 0xFF)
end

function M:r16(addr)
  return self:rb(addr) + self:rb(addr + 1) * 256
end

function M:r32(addr)
  return rv.u32(
    self:rb(addr)
      + self:rb(addr + 1) * 256
      + self:rb(addr + 2) * 65536
      + self:rb(addr + 3) * 16777216
  )
end

function M:w16(addr, value)
  self:wb(addr, value)
  self:wb(addr + 1, rsh(value, 8))
end

function M:w32(addr, value)
  value = rv.u32(value)
  self:wb(addr, value)
  self:wb(addr + 1, rsh(value, 8))
  self:wb(addr + 2, rsh(value, 16))
  self:wb(addr + 3, rsh(value, 24))
end

return M
