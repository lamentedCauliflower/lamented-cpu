-- RV32IM_Zicsr hart: fetch / decode / execute (ADR-0001, ADR-0002).
-- Pure Lua, engine-independent. Machine mode only; the minimal CSR + ecall-trap
-- path is what the riscv-tests env needs to report results via tohost.
--
-- ponytail: only the instructions the walking skeleton's first test needs are
-- fleshed out fully; mul/div (M, #6) and byte/halfword loads (#4) raise a clear
-- error so an out-of-scope test fails loudly instead of silently misbehaving.
local rv = require("lib.rvbit")
local u32, sext, signed = rv.u32, rv.sext, rv.signed
local band, bor, bnot, lsh, rsh, ash, bits =
  rv.band, rv.bor, rv.bnot, rv.lsh, rv.rsh, rv.ash, rv.bits

local M = {}
M.__index = M

local MTVEC, MEPC, MCAUSE, MTVAL = 0x305, 0x341, 0x342, 0x343
local MISA = 0x301
local MSTATUS = 0x300
-- misa: MXL=1 (RV32, bits 31:30 = 01) with the I and M extension bits set.
local MISA_RV32IM = 0x40000000 + 0x100 + 0x1000
local CAUSE_ILLEGAL = 2

-- Zve32x at fixed VLEN=128 (ADR-0012). Vector CSRs, the mstatus.VS field, and
-- the vill bit of vtype.
local VSTART, VXSAT, VXRM, VCSR = 0x008, 0x009, 0x00A, 0x00F
local VL, VTYPE, VLENB = 0xC20, 0xC21, 0xC22
local VLEN = 128
local MSTATUS_VS = 0x600 -- bits 10:9; 0 = Off (vector instructions trap)
local VILL = 0x80000000
local CAUSE_STORE_ACCESS = 7

-- 32x32 -> 64-bit unsigned product via 16-bit limbs, so every term stays below
-- 2^34 and is exact in a double. Returns high, low (each unsigned 32-bit).
local function mul64u(a, b)
  local a0, a1 = a % 65536, math.floor(a / 65536)
  local b0, b1 = b % 65536, math.floor(b / 65536)
  local p00 = a0 * b0
  local mid = math.floor(p00 / 65536) + a0 * b1 + a1 * b0
  local lo = p00 % 65536 + (mid % 65536) * 65536
  local hi = a1 * b1 + math.floor(mid / 65536)
  return hi, lo
end

-- exact floor(a/b) for non-negative integers, correcting any double rounding.
local function udiv(a, b)
  local q = math.floor(a / b)
  if (q + 1) * b <= a then
    q = q + 1
  elseif q * b > a then
    q = q - 1
  end
  return q
end

function M.new(mem)
  local x = {}
  for i = 0, 31 do
    x[i] = 0
  end
  -- 32 vector registers as plain word tables (serializable Factorio storage
  -- data). Reset state: VS = Initial (vector instructions execute; the Test
  -- env's csrs is then a no-op), vtype = vill until the first vset.
  local v = {}
  for i = 0, 31 do
    v[i] = { 0, 0, 0, 0 }
  end
  local csr = {
    [MISA] = MISA_RV32IM,
    [MSTATUS] = 0x200,
    [VTYPE] = VILL,
    [VL] = 0,
    [VLENB] = VLEN / 8,
    [VSTART] = 0,
    [VXSAT] = 0,
    [VXRM] = 0,
    [VCSR] = 0,
  }
  return setmetatable({ mem = mem, x = x, pc = 0x80000000, csr = csr, v = v }, M)
end

-- element access at eew (8/16/32) with LMUL register grouping: element e of
-- the group based at v[base] lives at byte offset e*eew/8, VLEN/8 bytes per
-- register, little-endian words within.
local function velt_get(v, base, eew, e)
  local byte = e * (eew / 8)
  local reg = v[base + math.floor(byte / 16)]
  local wi = math.floor((byte % 16) / 4) + 1
  if eew == 32 then
    return reg[wi]
  end
  local sh = (byte % 4) * 8
  return band(rsh(reg[wi], sh), eew == 8 and 0xFF or 0xFFFF)
end

local function velt_set(v, base, eew, e, val)
  local byte = e * (eew / 8)
  local reg = v[base + math.floor(byte / 16)]
  local wi = math.floor((byte % 16) / 4) + 1
  if eew == 32 then
    reg[wi] = u32(val)
    return
  end
  local sh = (byte % 4) * 8
  local mask = (eew == 8 and 0xFF or 0xFFFF)
  reg[wi] = bor(band(reg[wi], bnot(lsh(mask, sh))), lsh(band(val, mask), sh))
end

-- bit e of mask register r (mask layout is independent of SEW/LMUL)
local function mreg_bit(v, r, e)
  return band(rsh(v[r][math.floor(e / 32) + 1], e % 32), 1)
end

-- mask bit e is bit e of v0
local function mask_bit(v, e)
  return mreg_bit(v, 0, e)
end

-- write bit e of the mask register vd (mask-producing compares and carry-outs
-- touch exactly their bit: other bits stay undisturbed)
local function mask_set_bit(v, vd, e, on)
  local reg = v[vd]
  local wi = math.floor(e / 32) + 1
  local b = lsh(1, e % 32)
  reg[wi] = on and bor(reg[wi], b) or band(reg[wi], bnot(b))
end

-- signed view of a sew-wide element
local function sxt(val, sew)
  if val >= 2 ^ (sew - 1) then
    return val - 2 ^ sew
  end
  return val
end

-- OP-V single-width elementwise integer ops by funct6 (vv/vx/vi share the
-- table): f(vs2 element, vs1/rs1/imm operand, sew) -> raw value, masked to
-- sew width by velt_set. Shift amounts use the low lg2(sew) bits.
local VOPI = {
  [0x00] = function(a, b)
    return a + b
  end, -- vadd
  [0x02] = function(a, b)
    return a - b
  end, -- vsub
  [0x03] = function(a, b)
    return b - a
  end, -- vrsub
  [0x04] = function(a, b)
    return math.min(a, b)
  end, -- vminu
  [0x05] = function(a, b, s)
    return sxt(a, s) < sxt(b, s) and a or b
  end, -- vmin
  [0x06] = function(a, b)
    return math.max(a, b)
  end, -- vmaxu
  [0x07] = function(a, b, s)
    return sxt(a, s) > sxt(b, s) and a or b
  end, -- vmax
  [0x09] = function(a, b)
    return band(a, b)
  end, -- vand
  [0x0A] = function(a, b)
    return bor(a, b)
  end, -- vor
  [0x0B] = function(a, b)
    return rv.bxor(a, b)
  end, -- vxor
  [0x25] = function(a, b, s)
    return lsh(a, band(b, s - 1))
  end, -- vsll
  [0x28] = function(a, b, s)
    return rsh(a, band(b, s - 1))
  end, -- vsrl
  [0x29] = function(a, b, s)
    return ash(u32(sxt(a, s)), band(b, s - 1))
  end, -- vsra
}

-- fixed-point rounding: floor(val / 2^d) plus the vxrm increment computed
-- from the shifted-out bits (rnu/rne/rdn/rod). Exact for |val| < 2^53.
local function roundoff(val, d, rm)
  if d == 0 then
    return val
  end
  local q = math.floor(val / 2 ^ d)
  local low = val % 2 ^ d
  local half = 2 ^ (d - 1)
  if rm == 0 then -- rnu: round half up
    return low >= half and q + 1 or q
  elseif rm == 1 then -- rne: round half to even
    if low > half or (low == half and q % 2 == 1) then
      return q + 1
    end
    return q
  elseif rm == 2 then -- rdn: truncate
    return q
  end
  -- rod: jam the low bit if anything was shifted out
  if low ~= 0 and q % 2 == 0 then
    return q + 1
  end
  return q
end

-- sew-wide products, low and high halves, with per-operand signedness. A
-- product below SEW=32 is exact in a double; SEW=32 goes through mul64u the
-- same way the scalar M extension does.
local function vmullo(a, b, sew)
  if sew < 32 then
    return (a * b) % 2 ^ sew
  end
  local _, lo = mul64u(a, b)
  return lo
end

local function vmulhi(a, b, sew, sa, sb)
  if sew < 32 then
    local ea = sa and sxt(a, sew) or a
    local eb = sb and sxt(b, sew) or b
    return math.floor(ea * eb / 2 ^ sew)
  end
  local hi = mul64u(a, b)
  if sa and a >= 0x80000000 then
    hi = hi - b
  end
  if sb and b >= 0x80000000 then
    hi = hi - a
  end
  return hi
end

-- OP-V multiply/divide/remainder by funct6 (OPMVV/OPMVX): same signature as
-- VOPI. Divide semantics mirror the scalar M extension at element width:
-- divide by zero yields all-ones (or the dividend for remainder), and the
-- most-negative / -1 overflow wraps.
local VOPM = {
  [0x08] = function(a, b, _, rm)
    return roundoff(a + b, 1, rm)
  end, -- vaaddu
  [0x09] = function(a, b, s, rm)
    return roundoff(sxt(a, s) + sxt(b, s), 1, rm)
  end, -- vaadd
  [0x0A] = function(a, b, _, rm)
    return roundoff(a - b, 1, rm)
  end, -- vasubu
  [0x0B] = function(a, b, s, rm)
    return roundoff(sxt(a, s) - sxt(b, s), 1, rm)
  end, -- vasub
  [0x20] = function(a, b, s)
    return b == 0 and 2 ^ s - 1 or udiv(a, b)
  end, -- vdivu
  [0x21] = function(a, b, s)
    local sa, sb = sxt(a, s), sxt(b, s)
    if sb == 0 then
      return 2 ^ s - 1
    elseif sa == -(2 ^ (s - 1)) and sb == -1 then
      return a
    end
    local q = udiv(sa < 0 and -sa or sa, sb < 0 and -sb or sb)
    return (sa < 0) ~= (sb < 0) and -q or q
  end, -- vdiv
  [0x22] = function(a, b)
    return b == 0 and a or a - udiv(a, b) * b
  end, -- vremu
  [0x23] = function(a, b, s)
    local sa, sb = sxt(a, s), sxt(b, s)
    if sb == 0 then
      return a
    elseif sa == -(2 ^ (s - 1)) and sb == -1 then
      return 0
    end
    local q = udiv(sa < 0 and -sa or sa, sb < 0 and -sb or sb)
    q = (sa < 0) ~= (sb < 0) and -q or q
    return sa - q * sb
  end, -- vrem
  [0x24] = function(a, b, s)
    return vmulhi(a, b, s, false, false)
  end, -- vmulhu
  [0x25] = vmullo, -- vmul
  [0x26] = function(a, b, s)
    return vmulhi(a, b, s, true, false)
  end, -- vmulhsu (vs2 signed, operand unsigned)
  [0x27] = function(a, b, s)
    return vmulhi(a, b, s, true, true)
  end, -- vmulh
}

-- vsmul: (a*b) >> (sew-1) with vxrm rounding; the only overflow is
-- (-2^(sew-1))^2, which saturates to the positive max. SEW=32 needs the
-- 64-bit product as (signed high, unsigned low) limbs: the shifted value is
-- hi*2 + lo[31] and the shifted-out bits are lo[30:0].
local function vsmul_f(a, b, sew, rm)
  local sa, sb = sxt(a, sew), sxt(b, sew)
  if sa == -(2 ^ (sew - 1)) and sb == sa then
    return 2 ^ (sew - 1) - 1, true
  end
  if sew < 32 then
    return roundoff(sa * sb, sew - 1, rm), false
  end
  local hi, lo = mul64u(a, b)
  if a >= 0x80000000 then
    hi = hi - b
  end
  if b >= 0x80000000 then
    hi = hi - a
  end
  hi = signed(u32(hi))
  local q = hi * 2 + rsh(lo, 31)
  local low = band(lo, 0x7FFFFFFF)
  local half = 2 ^ 30
  if rm == 0 then
    q = low >= half and q + 1 or q
  elseif rm == 1 then
    if low > half or (low == half and q % 2 == 1) then
      q = q + 1
    end
  elseif rm == 3 then
    if low ~= 0 and q % 2 == 0 then
      q = q + 1
    end
  end
  return q, false
end

-- fixed-point OP-V by funct6 (OPIVV/X/I): f(vs2 element, operand, sew, rm)
-- -> value, saturated. Saturating adds/subs clamp and report vxsat; the
-- scaling shifts only round.
local VFIX = {
  [0x20] = function(a, b, s)
    local r = a + b
    if r > 2 ^ s - 1 then
      return 2 ^ s - 1, true
    end
    return r, false
  end, -- vsaddu
  [0x21] = function(a, b, s)
    local r = sxt(a, s) + sxt(b, s)
    if r > 2 ^ (s - 1) - 1 then
      return 2 ^ (s - 1) - 1, true
    elseif r < -(2 ^ (s - 1)) then
      return -(2 ^ (s - 1)), true
    end
    return r, false
  end, -- vsadd
  [0x22] = function(a, b)
    if b > a then
      return 0, true
    end
    return a - b, false
  end, -- vssubu
  [0x23] = function(a, b, s)
    local r = sxt(a, s) - sxt(b, s)
    if r > 2 ^ (s - 1) - 1 then
      return 2 ^ (s - 1) - 1, true
    elseif r < -(2 ^ (s - 1)) then
      return -(2 ^ (s - 1)), true
    end
    return r, false
  end, -- vssub
  [0x27] = vsmul_f,
  [0x2A] = function(a, b, s, rm)
    return roundoff(a, band(b, s - 1), rm), false
  end, -- vssrl
  [0x2B] = function(a, b, s, rm)
    return roundoff(sxt(a, s), band(b, s - 1), rm), false
  end, -- vssra
}

-- single-width integer reductions by funct6 (OPMVV): f(accumulator, vs2
-- element, sew) -> next accumulator; the accumulator is seeded from vs1[0]
local VRED = {
  [0x00] = function(a, b)
    return a + b
  end, -- vredsum
  [0x01] = function(a, b)
    return band(a, b)
  end, -- vredand
  [0x02] = function(a, b)
    return bor(a, b)
  end, -- vredor
  [0x03] = function(a, b)
    return rv.bxor(a, b)
  end, -- vredxor
  [0x04] = function(a, b)
    return math.min(a, b)
  end, -- vredminu
  [0x05] = function(a, b, s)
    return sxt(a, s) < sxt(b, s) and a or b
  end, -- vredmin
  [0x06] = function(a, b)
    return math.max(a, b)
  end, -- vredmaxu
  [0x07] = function(a, b, s)
    return sxt(a, s) > sxt(b, s) and a or b
  end, -- vredmax
}

-- mask-register logicals by funct6 (OPMVV, .mm): p(vs2 bit, vs1 bit) with
-- 0/1 inputs -> boolean result bit
local VMLOG = {
  [0x18] = function(a, b)
    return a == 1 and b == 0
  end, -- vmandn
  [0x19] = function(a, b)
    return a == 1 and b == 1
  end, -- vmand
  [0x1A] = function(a, b)
    return a == 1 or b == 1
  end, -- vmor
  [0x1B] = function(a, b)
    return a ~= b
  end, -- vmxor
  [0x1C] = function(a, b)
    return a == 1 or b == 0
  end, -- vmorn
  [0x1D] = function(a, b)
    return not (a == 1 and b == 1)
  end, -- vmnand
  [0x1E] = function(a, b)
    return not (a == 1 or b == 1)
  end, -- vmnor
  [0x1F] = function(a, b)
    return a == b
  end, -- vmxnor
}

-- VXUNARY0 vs1-field codes: { widening factor, signed }
local VEXTF = {
  [4] = { 4, false }, -- vzext.vf4
  [5] = { 4, true }, -- vsext.vf4
  [6] = { 2, false }, -- vzext.vf2
  [7] = { 2, true }, -- vsext.vf2
}

-- mask-producing integer compares by funct6: pred(vs2 element, operand, sew)
local VCMP = {
  [0x18] = function(a, b)
    return a == b
  end, -- vmseq
  [0x19] = function(a, b)
    return a ~= b
  end, -- vmsne
  [0x1A] = function(a, b)
    return a < b
  end, -- vmsltu
  [0x1B] = function(a, b, s)
    return sxt(a, s) < sxt(b, s)
  end, -- vmslt
  [0x1C] = function(a, b)
    return a <= b
  end, -- vmsleu
  [0x1D] = function(a, b, s)
    return sxt(a, s) <= sxt(b, s)
  end, -- vmsle
  [0x1E] = function(a, b)
    return a > b
  end, -- vmsgtu
  [0x1F] = function(a, b, s)
    return sxt(a, s) > sxt(b, s)
  end, -- vmsgt
}

function M:load(image)
  for addr, word in pairs(image.words) do
    self.mem:w32(addr, word)
  end
  for addr, byte in pairs(image.bytes or {}) do
    self.mem:wb(addr, byte)
  end
  self.pc = image.entry or self.pc
  self.watch = image.symbols and image.symbols.tohost
end

function M:store32(addr, value)
  self.mem:w32(addr, value)
  value = u32(value)
  if self.watch and addr == self.watch and value ~= 0 then
    self.tohost = value
  end
  -- MMIO doorbell watch: generalises the tohost watch (ADR-0005). io_base is nil
  -- under conformance (load path and hot loads untouched, suite stays green); set
  -- in-game to the controller's base. A store into the 16-byte register window
  -- records a doorbell as plain data for the driver to service between steps --
  -- the same record-and-let-the-host-act shape as tohost, so it stays serialisable
  -- (no closures in `storage`). Offset disambiguates SAMPLE/COMMIT.
  if self.io_base then
    local off = addr - self.io_base
    if off >= 0 and off < 0x10 then
      self.doorbell = { off = off, value = value }
    end
  end
end

function M:step()
  local w = self.mem:r32(self.pc)
  local op = band(w, 0x7F)
  local rd, f3, rs1, rs2 = bits(w, 11, 7), bits(w, 14, 12), bits(w, 19, 15), bits(w, 24, 20)
  local x = self.x
  local npc = u32(self.pc + 4)
  local function set(r, v)
    if r ~= 0 then
      x[r] = u32(v)
    end
  end
  -- enter a trap: record cause/epc/tval and redirect to mtvec. Returns the new
  -- pc so the caller can divert npc.
  local function trap(cause, tval)
    self.csr[MCAUSE] = cause
    self.csr[MEPC] = self.pc
    self.csr[MTVAL] = tval or 0
    return band(self.csr[MTVEC] or 0, 0xFFFFFFFC)
  end

  if op == 0x37 then -- lui
    set(rd, band(w, 0xFFFFF000))
  elseif op == 0x17 then -- auipc
    set(rd, u32(self.pc + band(w, 0xFFFFF000)))
  elseif op == 0x6F then -- jal
    local off = sext(
      lsh(bits(w, 19, 12), 12)
        + lsh(bits(w, 20, 20), 11)
        + lsh(bits(w, 30, 21), 1)
        + lsh(bits(w, 31, 31), 20),
      21
    )
    set(rd, npc)
    npc = u32(self.pc + off)
  elseif op == 0x67 then -- jalr
    local off = sext(bits(w, 31, 20), 12)
    local t = npc
    npc = band(u32(x[rs1] + off), 0xFFFFFFFE)
    set(rd, t)
  elseif op == 0x63 then -- branches
    local off = sext(
      lsh(bits(w, 31, 31), 12)
        + lsh(bits(w, 7, 7), 11)
        + lsh(bits(w, 30, 25), 5)
        + lsh(bits(w, 11, 8), 1),
      13
    )
    local a, b = x[rs1], x[rs2]
    local take
    if f3 == 0 then
      take = a == b
    elseif f3 == 1 then
      take = a ~= b
    elseif f3 == 4 then
      take = signed(a) < signed(b)
    elseif f3 == 5 then
      take = signed(a) >= signed(b)
    elseif f3 == 6 then
      take = a < b
    elseif f3 == 7 then
      take = a >= b
    else
      error("bad branch funct3")
    end
    if take then
      npc = u32(self.pc + off)
    end
  elseif op == 0x03 then -- loads (misaligned handled, not trapped: see mem.lua)
    local addr = u32(x[rs1] + sext(bits(w, 31, 20), 12))
    if f3 == 0 then -- lb
      set(rd, sext(self.mem:rb(addr), 8))
    elseif f3 == 1 then -- lh
      set(rd, sext(self.mem:r16(addr), 16))
    elseif f3 == 2 then -- lw
      set(rd, self.mem:r32(addr))
    elseif f3 == 4 then -- lbu
      set(rd, self.mem:rb(addr))
    elseif f3 == 5 then -- lhu
      set(rd, self.mem:r16(addr))
    else
      error("bad load funct3")
    end
  elseif op == 0x23 then -- stores
    local imm = sext(lsh(bits(w, 31, 25), 5) + bits(w, 11, 7), 12)
    local addr = u32(x[rs1] + imm)
    if f3 == 0 then -- sb
      self.mem:wb(addr, x[rs2])
    elseif f3 == 1 then -- sh
      self.mem:w16(addr, x[rs2])
    elseif f3 == 2 then -- sw (store32 also drives the tohost watch)
      self:store32(addr, x[rs2])
    else
      error("bad store funct3")
    end
  elseif op == 0x13 then -- op-imm
    local imm = sext(bits(w, 31, 20), 12)
    local top = bits(w, 31, 25)
    if f3 == 0 then
      set(rd, u32(x[rs1] + imm))
    elseif f3 == 1 then -- slli: RV32 shamt is 5 bits, so funct7 must be 0
      if top ~= 0 then
        npc = trap(CAUSE_ILLEGAL, w)
      else
        set(rd, lsh(x[rs1], bits(w, 24, 20)))
      end
    elseif f3 == 2 then
      set(rd, signed(x[rs1]) < signed(imm) and 1 or 0)
    elseif f3 == 3 then
      set(rd, x[rs1] < u32(imm) and 1 or 0)
    elseif f3 == 4 then
      set(rd, rv.bxor(x[rs1], u32(imm)))
    elseif f3 == 5 then -- srli/srai: funct7 must be 0 or 0x20
      local sh = bits(w, 24, 20)
      if top ~= 0 and top ~= 0x20 then
        npc = trap(CAUSE_ILLEGAL, w)
      else
        set(rd, bits(w, 30, 30) == 1 and ash(x[rs1], sh) or rsh(x[rs1], sh))
      end
    elseif f3 == 6 then
      set(rd, bor(x[rs1], u32(imm)))
    elseif f3 == 7 then
      set(rd, band(x[rs1], u32(imm)))
    end
  elseif op == 0x33 then -- op
    local f7 = bits(w, 31, 25)
    local a, b = x[rs1], x[rs2]
    if f7 == 1 then -- M extension: mul/div/rem
      if f3 == 0 then -- mul (low 32)
        local _, lo = mul64u(a, b)
        set(rd, lo)
      elseif f3 <= 3 then -- mulh / mulhsu / mulhu (high 32)
        local hi = mul64u(a, b)
        if f3 ~= 3 and a >= 0x80000000 then -- subtract b when a is signed-negative
          hi = hi - b
        end
        if f3 == 1 and b >= 0x80000000 then -- mulh: also when b is negative
          hi = hi - a
        end
        set(rd, u32(hi))
      elseif f3 == 4 then -- div (signed, truncate toward zero)
        local sa, sb = signed(a), signed(b)
        if sb == 0 then
          set(rd, 0xFFFFFFFF)
        elseif sa == -0x80000000 and sb == -1 then
          set(rd, 0x80000000) -- overflow
        else
          local q = udiv(sa < 0 and -sa or sa, sb < 0 and -sb or sb)
          set(rd, (sa < 0) ~= (sb < 0) and u32(-q) or u32(q))
        end
      elseif f3 == 5 then -- divu
        set(rd, b == 0 and 0xFFFFFFFF or udiv(a, b))
      elseif f3 == 6 then -- rem (signed, sign of dividend)
        local sa, sb = signed(a), signed(b)
        if sb == 0 then
          set(rd, a)
        elseif sa == -0x80000000 and sb == -1 then
          set(rd, 0)
        else
          local q = udiv(sa < 0 and -sa or sa, sb < 0 and -sb or sb)
          q = (sa < 0) ~= (sb < 0) and -q or q
          set(rd, u32(sa - q * sb))
        end
      else -- remu
        set(rd, b == 0 and a or u32(a - udiv(a, b) * b))
      end
    elseif f3 == 0 then
      set(rd, f7 == 0x20 and u32(a - b) or u32(a + b))
    elseif f3 == 1 then
      set(rd, lsh(a, band(b, 0x1F)))
    elseif f3 == 2 then
      set(rd, signed(a) < signed(b) and 1 or 0)
    elseif f3 == 3 then
      set(rd, a < b and 1 or 0)
    elseif f3 == 4 then
      set(rd, rv.bxor(a, b))
    elseif f3 == 5 then
      set(rd, f7 == 0x20 and ash(a, band(b, 0x1F)) or rsh(a, band(b, 0x1F)))
    elseif f3 == 6 then
      set(rd, bor(a, b))
    elseif f3 == 7 then
      set(rd, band(a, b))
    end
  elseif op == 0x73 then -- system
    if w == 0x00000073 or w == 0x00100073 then -- ecall / ebreak
      npc = trap((w == 0x73) and 11 or 3, 0) -- machine ecall / breakpoint
    elseif w == 0x30200073 then -- mret: return to mepc (M-mode only, no priv switch)
      npc = u32(self.csr[MEPC] or 0)
    else -- Zicsr
      local c = bits(w, 31, 20)
      local old = self.csr[c] or 0
      local imm_form = f3 >= 5
      local src = imm_form and rs1 or x[rs1]
      set(rd, old)
      if f3 == 1 or f3 == 5 then -- csrrw[i]
        self.csr[c] = u32(src)
      elseif f3 == 2 or f3 == 6 then -- csrrs[i]
        if (imm_form and src ~= 0) or (not imm_form and rs1 ~= 0) then
          self.csr[c] = bor(old, u32(src))
        end
      elseif f3 == 3 or f3 == 7 then -- csrrc[i]
        if (imm_form and src ~= 0) or (not imm_form and rs1 ~= 0) then
          self.csr[c] = band(old, bnot(u32(src)))
        end
      end
      -- vcsr is an architectural mirror of vxrm[2:1] | vxsat[0]; writes to
      -- either side land on both (ADR-0012)
      if c == VCSR then
        local nv = self.csr[c] or 0
        self.csr[VXRM], self.csr[VXSAT] = band(rsh(nv, 1), 3), band(nv, 1)
      elseif c == VXRM or c == VXSAT then
        self.csr[VXRM] = band(self.csr[VXRM] or 0, 3)
        self.csr[VXSAT] = band(self.csr[VXSAT] or 0, 1)
        self.csr[VCSR] = bor(lsh(self.csr[VXRM], 1), self.csr[VXSAT])
      end
    end
  elseif op == 0x57 or op == 0x07 or op == 0x27 then -- Zve32x (ADR-0012)
    npc = self:vstep(w, op, rd, f3, rs1, rs2, npc, set, trap)
  elseif op ~= 0x0F then -- fence is a nop for a single hart; anything else is illegal
    error(string.format("illegal/unimplemented opcode 0x%02x at pc=0x%08x", op, self.pc))
  end

  self.pc = npc
end

-- VLMAX for a candidate vtype, or nil when the vtype is unsupported here
-- (reserved bits, reserved LMUL, SEW > ELEN=32, or LMUL < SEW/ELEN).
local function vlmax_of(vt)
  if band(vt, 0xFFFFFF00) ~= 0 then
    return nil
  end
  local sew = lsh(8, band(rsh(vt, 3), 7))
  local lm = band(vt, 7)
  local num, den
  if lm <= 3 then
    num, den = lsh(1, lm), 1
  elseif lm >= 5 then
    num, den = 1, lsh(1, 8 - lm)
  else
    return nil
  end
  if sew > 32 or num * 32 < sew * den then
    return nil
  end
  return math.floor(VLEN * num / (den * sew))
end

-- Circuit I/O rule (#41): a vector element store landing in the armed
-- controller's 16-byte trigger-register window is a store access-fault, not a
-- doorbell -- a slip in vector address arithmetic must not fire Sample or
-- Commit. io_base is nil under conformance, so this is reachable in-game only.
function M:vstore_faults(addr, len)
  return self.io_base and addr + len > self.io_base and addr < self.io_base + 0x10
end

-- Zve32x decode/execute: configuration (op 0x57 funct3=7), OP-V arithmetic
-- (0x57), unit-stride loads (0x07) and stores (0x27), as an element loop over
-- vl at the vtype SEW, honouring vstart and the v0.t mask (ADR-0012). The two
-- floating-point operand categories and every unimplemented funct6 raise a
-- loud error so an out-of-scope fixture fails visibly, mirroring the scalar
-- decoder's style.
function M:vstep(w, op, rd, f3, rs1, rs2, npc, set, trap)
  local csr, x = self.csr, self.x
  if band(csr[MSTATUS] or 0, MSTATUS_VS) == 0 then
    return trap(CAUSE_ILLEGAL, w) -- VS Off (also catches scalar FP loads/stores)
  end
  self.v = self.v or M.new(self.mem).v -- additive field for pre-extension saves
  local v = self.v

  if op == 0x57 and f3 == 7 then -- vsetvli / vsetivli / vsetvl
    local vt, avl
    if bits(w, 31, 30) == 3 then -- vsetivli
      vt, avl = bits(w, 29, 20), rs1
    elseif bits(w, 31, 25) == 0x40 then -- vsetvl
      vt = x[rs2]
    elseif bits(w, 31, 31) == 0 then -- vsetvli
      vt = bits(w, 30, 20)
    else
      return trap(CAUSE_ILLEGAL, w)
    end
    if not avl then -- register AVL forms share the x0 conventions
      if rs1 ~= 0 then
        avl = x[rs1]
      elseif rd ~= 0 then
        avl = 0xFFFFFFFF -- vl = VLMAX
      else
        avl = csr[VL] -- keep vl (we take min against the new VLMAX)
      end
    end
    local vlmax = vlmax_of(vt)
    if not vlmax then
      csr[VTYPE], csr[VL] = VILL, 0
      set(rd, 0)
    else
      local vl = math.min(avl, vlmax)
      csr[VTYPE], csr[VL] = vt, vl
      set(rd, vl)
    end
    csr[MSTATUS] = bor(csr[MSTATUS], MSTATUS_VS)
    return npc
  end

  if band(csr[VTYPE] or 0, VILL) ~= 0 then
    return trap(CAUSE_ILLEGAL, w) -- vector instruction under vill
  end
  local sew = lsh(8, band(rsh(csr[VTYPE], 3), 7))
  local vl, vstart = csr[VL] or 0, csr[VSTART] or 0
  local vm = bits(w, 25, 25)

  if op == 0x57 then -- OP-V arithmetic
    local f6 = bits(w, 31, 26)
    local sewmask = 2 ^ sew - 1
    -- operand b: vs1 element (vv), truncated x[rs1] (vx), or sew-truncated
    -- sign-extended 5-bit immediate (vi) -- truncate-then-interpret, per spec
    local bscalar
    if f3 == 4 or f3 == 6 then
      bscalar = band(x[rs1], sewmask)
    elseif f3 == 3 then
      bscalar = band(sext(rs1, 5), sewmask)
    end
    local function bval(e)
      return bscalar or velt_get(v, rs1, sew, e)
    end
    local opiv = f3 == 0 or f3 == 3 or f3 == 4

    if opiv and VOPI[f6] then
      local f = VOPI[f6]
      for e = vstart, vl - 1 do
        if vm == 1 or mask_bit(v, e) == 1 then
          velt_set(v, rd, sew, e, f(velt_get(v, rs2, sew, e), bval(e), sew))
        end
      end
    elseif opiv and VCMP[f6] then
      local p = VCMP[f6]
      for e = vstart, vl - 1 do
        if vm == 1 or mask_bit(v, e) == 1 then
          mask_set_bit(v, rd, e, p(velt_get(v, rs2, sew, e), bval(e), sew))
        end
      end
    elseif opiv and (f6 == 0x10 or f6 == 0x12) then
      -- vadc/vsbc: v0 is the carry/borrow input, every element active
      for e = vstart, vl - 1 do
        local a, b, cin = velt_get(v, rs2, sew, e), bval(e), mask_bit(v, e)
        velt_set(v, rd, sew, e, f6 == 0x10 and (a + b + cin) or (a - b - cin))
      end
    elseif opiv and (f6 == 0x11 or f6 == 0x13) then
      -- vmadc/vmsbc: carry/borrow-out into a mask register; vm=0 also adds
      -- the carry/borrow-in, every element active either way
      for e = vstart, vl - 1 do
        local a, b = velt_get(v, rs2, sew, e), bval(e)
        local cin = vm == 0 and mask_bit(v, e) or 0
        local out
        if f6 == 0x11 then
          out = a + b + cin > sewmask
        else
          out = a - b - cin < 0
        end
        mask_set_bit(v, rd, e, out)
      end
    elseif opiv and f6 == 0x17 then
      -- vm=0: vmerge (v0 selects); vm=1: vmv.v.* (vs2 encoded as v0)
      for e = vstart, vl - 1 do
        local val
        if vm == 1 or mask_bit(v, e) == 1 then
          val = bval(e)
        else
          val = velt_get(v, rs2, sew, e)
        end
        velt_set(v, rd, sew, e, val)
      end
    elseif opiv and VFIX[f6] then
      local f = VFIX[f6]
      local rm = band(csr[VXRM] or 0, 3)
      local sat = false
      for e = vstart, vl - 1 do
        if vm == 1 or mask_bit(v, e) == 1 then
          local val, s2 = f(velt_get(v, rs2, sew, e), bval(e), sew, rm)
          velt_set(v, rd, sew, e, val)
          sat = sat or s2
        end
      end
      if sat then -- sticky, mirrored into vcsr[0]
        csr[VXSAT] = 1
        csr[VCSR] = bor(lsh(band(csr[VXRM] or 0, 3), 1), 1)
      end
    elseif opiv and f6 >= 0x2C and f6 <= 0x2F then
      -- narrowing shifts (vnsrl/vnsra) and clips (vnclipu/vnclip): vs2 is
      -- read at 2*SEW, shift amounts use lg2(2*SEW) bits, clips round per
      -- vxrm then saturate to SEW range with vxsat reporting
      local dsew = sew * 2
      if dsew > 32 then
        return trap(CAUSE_ILLEGAL, w)
      end
      local rm = band(csr[VXRM] or 0, 3)
      local sat = false
      for e = vstart, vl - 1 do
        if vm == 1 or mask_bit(v, e) == 1 then
          local a, b = velt_get(v, rs2, dsew, e), bval(e)
          local sh = band(b, dsew - 1)
          local val
          if f6 == 0x2C then
            val = math.floor(a / 2 ^ sh) -- vnsrl
          elseif f6 == 0x2D then
            val = math.floor(sxt(a, dsew) / 2 ^ sh) -- vnsra
          elseif f6 == 0x2E then -- vnclipu
            val = roundoff(a, sh, rm)
            if val > 2 ^ sew - 1 then
              val, sat = 2 ^ sew - 1, true
            end
          else -- vnclip
            val = roundoff(sxt(a, dsew), sh, rm)
            if val > 2 ^ (sew - 1) - 1 then
              val, sat = 2 ^ (sew - 1) - 1, true
            elseif val < -(2 ^ (sew - 1)) then
              val, sat = -(2 ^ (sew - 1)), true
            end
          end
          velt_set(v, rd, sew, e, val)
        end
      end
      if sat then
        csr[VXSAT] = 1
        csr[VCSR] = bor(lsh(band(csr[VXRM] or 0, 3), 1), 1)
      end
    elseif (f3 == 2 or f3 == 6) and VOPM[f6] then
      local f = VOPM[f6]
      local rm = band(csr[VXRM] or 0, 3)
      for e = vstart, vl - 1 do
        if vm == 1 or mask_bit(v, e) == 1 then
          velt_set(v, rd, sew, e, f(velt_get(v, rs2, sew, e), bval(e), sew, rm))
        end
      end
    elseif (f3 == 2 or f3 == 6) and (f6 == 0x29 or f6 == 0x2B or f6 == 0x2D or f6 == 0x2F) then
      -- multiply-accumulate: vd is both source and destination. vmacc/vnmsac
      -- accumulate the vs1*vs2 product into vd; vmadd/vnmsub multiply vd and
      -- overwrite it (the operand from bval is always the multiplier vs1/rs1).
      for e = vstart, vl - 1 do
        if vm == 1 or mask_bit(v, e) == 1 then
          local a, b = velt_get(v, rs2, sew, e), bval(e)
          local d = velt_get(v, rd, sew, e)
          local val
          if f6 == 0x2D then
            val = d + vmullo(a, b, sew) -- vmacc
          elseif f6 == 0x2F then
            val = d - vmullo(a, b, sew) -- vnmsac
          elseif f6 == 0x29 then
            val = vmullo(d, b, sew) + a -- vmadd
          else
            val = a - vmullo(d, b, sew) -- vnmsub
          end
          velt_set(v, rd, sew, e, val)
        end
      end
    elseif (f3 == 2 or f3 == 6) and f6 >= 0x30 then
      -- widening add/sub/multiply/accumulate: destination elements at 2*SEW
      -- (2*SEW > ELEN=32 is reserved). The .w add/sub forms (0x34-0x37) read
      -- vs2 already wide; the MACs (0x3C-0x3F) accumulate into wide vd.
      local dsew = sew * 2
      if dsew > 32 or f6 == 0x39 then
        return trap(CAUSE_ILLEGAL, w)
      end
      local dmask = 2 ^ dsew - 1
      for e = vstart, vl - 1 do
        if vm == 1 or mask_bit(v, e) == 1 then
          local b = bval(e)
          local val
          if f6 <= 0x37 then
            local wide = f6 >= 0x34
            local a = velt_get(v, rs2, wide and dsew or sew, e)
            if band(f6, 1) == 1 then -- signed variant
              a = sxt(a, wide and dsew or sew)
              b = sxt(b, sew)
            end
            val = band(f6, 2) == 2 and a - b or a + b
          elseif f6 == 0x38 or f6 == 0x3A or f6 == 0x3B then
            local a = velt_get(v, rs2, sew, e)
            if f6 ~= 0x38 then
              a = sxt(a, sew) -- vwmulsu/vwmul: vs2 signed
            end
            if f6 == 0x3B then
              b = sxt(b, sew) -- vwmul: both signed
            end
            val = a * b
          else
            local a = velt_get(v, rs2, sew, e)
            if f6 == 0x3D then -- vwmacc: both signed
              a, b = sxt(a, sew), sxt(b, sew)
            elseif f6 == 0x3E then -- vwmaccus: rs1 unsigned, vs2 signed
              a = sxt(a, sew)
            elseif f6 == 0x3F then -- vwmaccsu: vs1 signed, vs2 unsigned
              b = sxt(b, sew)
            end
            val = velt_get(v, rd, dsew, e) + a * b
          end
          velt_set(v, rd, dsew, e, band(val, dmask))
        end
      end
    elseif f3 == 2 and VRED[f6] then
      -- reductions collapse active vs2 elements into vd[0], seeded from
      -- vs1[0]; vl=0 leaves vd untouched. Nonzero vstart is illegal (spec).
      if vstart ~= 0 then
        return trap(CAUSE_ILLEGAL, w)
      end
      if vl > 0 then
        local f = VRED[f6]
        local acc = velt_get(v, rs1, sew, 0)
        for e = 0, vl - 1 do
          if vm == 1 or mask_bit(v, e) == 1 then
            acc = band(f(acc, velt_get(v, rs2, sew, e), sew), sewmask)
          end
        end
        velt_set(v, rd, sew, 0, acc)
      end
    elseif f3 == 0 and (f6 == 0x30 or f6 == 0x31) then
      -- vwredsumu/vwredsum: sum at 2*SEW into vd[0] seeded from vs1[0] at
      -- 2*SEW; 2*SEW > ELEN=32 is reserved
      if vstart ~= 0 or sew * 2 > 32 then
        return trap(CAUSE_ILLEGAL, w)
      end
      if vl > 0 then
        local dsew = sew * 2
        local dmask = 2 ^ dsew - 1
        local acc = velt_get(v, rs1, dsew, 0)
        for e = 0, vl - 1 do
          if vm == 1 or mask_bit(v, e) == 1 then
            local val = velt_get(v, rs2, sew, e)
            if f6 == 0x31 then
              val = band(sxt(val, sew), dmask)
            end
            acc = band(acc + val, dmask)
          end
        end
        velt_set(v, rd, dsew, 0, acc)
      end
    elseif f3 == 2 and VMLOG[f6] then
      -- mask logicals: unmasked bitwise ops over the low vl mask bits
      local p = VMLOG[f6]
      for e = vstart, vl - 1 do
        mask_set_bit(v, rd, e, p(mreg_bit(v, rs2, e), mreg_bit(v, rs1, e)))
      end
    elseif f3 == 2 and f6 == 0x10 and (rs1 == 0x10 or rs1 == 0x11) then
      -- VWXUNARY0: vcpop.m counts the set active mask bits of vs2, vfirst.m
      -- finds the first (or -1); both write x[rd], both require vstart = 0
      if vstart ~= 0 then
        return trap(CAUSE_ILLEGAL, w)
      end
      if rs1 == 0x10 then
        local n = 0
        for e = 0, vl - 1 do
          if (vm == 1 or mask_bit(v, e) == 1) and mreg_bit(v, rs2, e) == 1 then
            n = n + 1
          end
        end
        set(rd, n)
      else
        local first = -1
        for e = 0, vl - 1 do
          if (vm == 1 or mask_bit(v, e) == 1) and mreg_bit(v, rs2, e) == 1 then
            first = e
            break
          end
        end
        set(rd, first)
      end
    elseif f3 == 6 and f6 == 0x10 and rs2 == 0 then
      -- VRXUNARY0: vmv.s.x writes x[rs1] at SEW into vd[0]; a no-op (not
      -- even a tail write) when vstart >= vl
      if vstart < vl then
        velt_set(v, rd, sew, 0, band(x[rs1], sewmask))
      end
    elseif f3 == 2 and f6 == 0x14 then
      -- VMUNARY0 by vs1 code: vmsbf/vmsof/vmsif (1/2/3) write mask bits up to
      -- the first set active bit of vs2, viota (0x10) prefix-counts it into
      -- SEW elements, vid (0x11) writes element indices. All but vid require
      -- vstart = 0 (spec).
      if rs1 == 0x11 then -- vid.v honours vstart like a normal elementwise op
        for e = vstart, vl - 1 do
          if vm == 1 or mask_bit(v, e) == 1 then
            velt_set(v, rd, sew, e, e)
          end
        end
      elseif vstart ~= 0 then
        return trap(CAUSE_ILLEGAL, w)
      elseif rs1 == 0x10 then -- viota.m: inactive elements neither written nor counted
        local sum = 0
        for e = 0, vl - 1 do
          if vm == 1 or mask_bit(v, e) == 1 then
            velt_set(v, rd, sew, e, sum)
            if mreg_bit(v, rs2, e) == 1 then
              sum = sum + 1
            end
          end
        end
      elseif rs1 >= 1 and rs1 <= 3 then
        local found = false
        for e = 0, vl - 1 do
          if vm == 1 or mask_bit(v, e) == 1 then
            local b = mreg_bit(v, rs2, e) == 1
            local out
            if rs1 == 1 then
              out = not found and not b -- vmsbf: strictly before the first
            elseif rs1 == 2 then
              out = not found and b -- vmsof: only the first
            else
              out = not found -- vmsif: up to and including the first
            end
            if b then
              found = true
            end
            mask_set_bit(v, rd, e, out)
          end
        end
      else
        error(string.format("unimplemented VMUNARY0 vs1=0x%02x", rs1))
      end
    elseif f3 == 2 and f6 == 0x12 and VEXTF[rs1] then
      -- VXUNARY0: vzext/vsext.vf2/.vf4 read the source at a narrower EEW
      local frac, sgn = VEXTF[rs1][1], VEXTF[rs1][2]
      local seew = sew / frac
      if seew < 8 then
        return trap(CAUSE_ILLEGAL, w)
      end
      for e = vstart, vl - 1 do
        if vm == 1 or mask_bit(v, e) == 1 then
          local val = velt_get(v, rs2, seew, e)
          if sgn then
            val = u32(sxt(val, seew))
          end
          velt_set(v, rd, sew, e, val)
        end
      end
    else
      error(string.format("unimplemented vector instruction funct6=0x%02x funct3=%d", f6, f3))
    end
  else -- vector loads (0x07) / stores (0x27)
    local eew = ({ [0] = 8, [5] = 16, [6] = 32 })[f3]
    local mop, nf, mew = bits(w, 27, 26), bits(w, 31, 29), bits(w, 28, 28)
    if not eew or mew ~= 0 then
      error(string.format("unimplemented vector memory form 0x%08x", w))
    end
    local load = op == 0x07
    local base = x[rs1]

    if mop == 0 and rs2 == 0x08 then
      -- whole-register vl<n>re<eew>/vs<n>r: moves nf+1 registers regardless
      -- of vl and the mask (EEW only affects non-architectural layout hints)
      for r = 0, nf do
        for wi = 0, 3 do
          local addr = u32(base + r * 16 + wi * 4)
          if load then
            v[rd + r][wi + 1] = self.mem:r32(addr)
          elseif self:vstore_faults(addr, 4) then
            csr[VSTART] = r * 16 + wi * 4 -- element index at EEW=8
            return trap(CAUSE_STORE_ACCESS, addr)
          else
            self:store32(addr, v[rd + r][wi + 1])
          end
        end
      end
    elseif mop == 0 and rs2 == 0x0B then
      -- vlm/vsm: EEW=8 over ceil(vl/8) bytes, unconditionally unmasked
      local evl = math.ceil(vl / 8)
      for e = vstart, evl - 1 do
        local addr = u32(base + e)
        if load then
          velt_set(v, rd, 8, e, self.mem:rb(addr))
        elseif self:vstore_faults(addr, 1) then
          csr[VSTART] = e
          return trap(CAUSE_STORE_ACCESS, addr)
        else
          self.mem:wb(addr, velt_get(v, rd, 8, e))
        end
      end
    else
      -- unit-stride (with fault-only-first), strided, indexed, and their
      -- segment forms in one element x field loop. Indexed forms address by
      -- an index vector at the encoded EEW but move data at the vtype SEW;
      -- everything else moves data at the encoded EEW. Loads never fault, so
      -- fault-only-first is the unit-stride path with vl untouched.
      local deew -- data element width
      if mop == 1 or mop == 3 then
        deew = sew
      else
        deew = eew
        if mop == 0 and rs2 ~= 0 and rs2 ~= 0x10 then
          error(string.format("unimplemented vector memory form 0x%08x", w))
        end
      end
      local esz = deew / 8
      -- registers per segment field: max(1, EMUL) with EMUL = deew/sew * LMUL
      local lm = band(csr[VTYPE], 7)
      local num, den
      if lm <= 3 then
        num, den = lsh(1, lm), 1
      else
        num, den = 1, lsh(1, 8 - lm)
      end
      local rpf = math.max(1, math.floor((deew * num) / (sew * den)))
      local stride = mop == 2 and signed(x[rs2]) or (nf + 1) * esz
      for e = vstart, vl - 1 do
        if vm == 1 or mask_bit(v, e) == 1 then
          local ebase
          if mop == 1 or mop == 3 then
            ebase = base + velt_get(v, rs2, eew, e)
          else
            ebase = base + e * stride
          end
          for f = 0, nf do
            local addr = u32(ebase + f * esz)
            local vr = rd + f * rpf
            if load then
              local val
              if deew == 8 then
                val = self.mem:rb(addr)
              elseif deew == 16 then
                val = self.mem:r16(addr)
              else
                val = self.mem:r32(addr)
              end
              velt_set(v, vr, deew, e, val)
            elseif self:vstore_faults(addr, esz) then
              csr[VSTART] = e
              return trap(CAUSE_STORE_ACCESS, addr)
            else
              local val = velt_get(v, vr, deew, e)
              if deew == 8 then
                self.mem:wb(addr, val)
              elseif deew == 16 then
                self.mem:w16(addr, val)
              else
                self:store32(addr, val)
              end
            end
          end
        end
      end
    end
  end

  csr[VSTART] = 0
  csr[MSTATUS] = bor(csr[MSTATUS], MSTATUS_VS) -- VS = Dirty
  return npc
end

function M:run(opts)
  opts = opts or {}
  self.watch = opts.tohost or self.watch
  local max = opts.max_steps or 1000000
  for i = 1, max do
    self:step()
    if self.tohost ~= nil then
      return { tohost = self.tohost, steps = i }
    end
  end
  return { tohost = nil, steps = max, timeout = true }
end

return M
