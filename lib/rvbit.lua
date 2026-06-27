-- 32-bit RISC-V arithmetic over Lua 5.2's bit32 (ADR-0002): the game runs stock
-- Lua 5.2, whose doubles hold a 32-bit word exactly. Everything here is unsigned
-- mod 2^32; `signed` is the only place we leave that domain.
local b = bit32
local M = {}

local TWO31, TWO32 = 2 ^ 31, 2 ^ 32

function M.u32(x)
  return b.band(x, 0xFFFFFFFF)
end

-- sign-extend the low `bits` of v, returned as an unsigned 32-bit value.
function M.sext(v, bits)
  v = b.band(v, 2 ^ bits - 1)
  if v >= 2 ^ (bits - 1) then
    v = v - 2 ^ bits
  end
  return M.u32(v)
end

-- interpret an unsigned 32-bit value as signed (-2^31 .. 2^31-1).
function M.signed(v)
  if v >= TWO31 then
    return v - TWO32
  end
  return v
end

M.band, M.bor, M.bxor, M.bnot = b.band, b.bor, b.bxor, b.bnot
M.lsh, M.rsh, M.ash = b.lshift, b.rshift, b.arshift

-- extract bits [hi:lo] (inclusive) of an unsigned value.
function M.bits(v, hi, lo)
  return b.band(b.rshift(v, lo), 2 ^ (hi - lo + 1) - 1)
end

return M
