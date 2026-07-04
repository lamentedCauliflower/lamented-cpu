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

-- mask bit e is bit e of v0 (mask layout is independent of SEW/LMUL)
local function mask_bit(v, e)
  return band(rsh(v[0][math.floor(e / 32) + 1], e % 32), 1)
end

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
    if f3 == 0 and f6 == 0x00 then -- vadd.vv
      for e = vstart, vl - 1 do
        if vm == 1 or mask_bit(v, e) == 1 then
          velt_set(v, rd, sew, e, velt_get(v, rs2, sew, e) + velt_get(v, rs1, sew, e))
        end
      end
    elseif f3 == 3 and f6 == 0x17 and vm == 1 and rs2 == 0 then -- vmv.v.i
      local imm = sext(rs1, 5)
      for e = vstart, vl - 1 do
        velt_set(v, rd, sew, e, imm)
      end
    else
      error(string.format("unimplemented vector instruction funct6=0x%02x funct3=%d", f6, f3))
    end
  else -- unit-stride loads (0x07) / stores (0x27)
    local eew = ({ [0] = 8, [5] = 16, [6] = 32 })[f3]
    if not eew or bits(w, 31, 26) ~= 0 or rs2 ~= 0 then
      error(string.format("unimplemented vector memory form 0x%08x", w))
    end
    local base = x[rs1]
    for e = vstart, vl - 1 do
      if vm == 1 or mask_bit(v, e) == 1 then
        local addr = u32(base + e * (eew / 8))
        if op == 0x07 then
          local val
          if eew == 8 then
            val = self.mem:rb(addr)
          elseif eew == 16 then
            val = self.mem:r16(addr)
          else
            val = self.mem:r32(addr)
          end
          velt_set(v, rd, eew, e, val)
        else
          local val = velt_get(v, rd, eew, e)
          if eew == 8 then
            self.mem:wb(addr, val)
          elseif eew == 16 then
            self.mem:w16(addr, val)
          else
            self:store32(addr, val)
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
