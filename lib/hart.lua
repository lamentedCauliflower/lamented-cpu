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
-- misa: MXL=1 (RV32, bits 31:30 = 01) with the I and M extension bits set.
local MISA_RV32IM = 0x40000000 + 0x100 + 0x1000
local CAUSE_ILLEGAL = 2

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
  return setmetatable({ mem = mem, x = x, pc = 0x80000000, csr = { [MISA] = MISA_RV32IM } }, M)
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
  if self.watch and addr == self.watch and u32(value) ~= 0 then
    self.tohost = u32(value)
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
    end
  elseif op ~= 0x0F then -- fence is a nop for a single hart; anything else is illegal
    error(string.format("illegal/unimplemented opcode 0x%02x at pc=0x%08x", op, self.pc))
  end

  self.pc = npc
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
