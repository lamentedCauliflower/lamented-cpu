-- RV32IM_Zicsr assembler (ADR-0004): assembly text -> machine code + symbols.
-- The Hart runs assembly, not binaries; this is what turns the riscv-tests
-- assembly sources (and in-game programs) into a loadable image.
--
-- Two passes: pass 1 walks statements assigning addresses to instructions and
-- labels (pseudo-ops expand to a fixed number of real instructions, so sizes are
-- known); pass 2 encodes each instruction with the resolved symbol table.
--
-- ponytail: sections are flattened in source order (.section/.data/.pushsection
-- are treated as no-ops bar their .align), because memory is sparse and the tests
-- only need labels at distinct, consistent, aligned addresses. Real section
-- placement is deferred until something needs it.
local rv = require("lib.rvbit")
local u32, sext, signed = rv.u32, rv.sext, rv.signed
local band, bor, lsh, rsh, bits = rv.band, rv.bor, rv.lsh, rv.rsh, rv.bits

local M = {}

local RESET = 0x80000000

-- Rich-text signal types we accept, mapped to their SignalID type (ADR-0006).
-- "virtual-signal" becomes "virtual" so a signal named in source and the same
-- signal read off the wire (Factorio reports type "virtual") get one Signal-map
-- id. Other 2.0 types (recipe/entity/space-location/asteroid-chunk/quality) and a
-- quality clause are rejected for now.
local SIGNAL_TYPE = { item = "item", fluid = "fluid", ["virtual-signal"] = "virtual" }

-- Replace each `[type=name]` rich-text tag with its resolved decimal id before the
-- two passes, so the id is a plain integer usable in any expression position and
-- evalexpr never sees a tag. The resolver is injected (engine-free); nil under
-- conformance, leaving the riscv-tests path byte-for-byte unchanged.
local function resolve_tags(src, resolver)
  return (
    src:gsub("%[([%w%-]+)=([^%]]+)%]", function(typ, value)
      local tag = "[" .. typ .. "=" .. value .. "]"
      if value:find(",") then -- e.g. [item=iron-plate,quality=uncommon]
        error(
          "signal tag " .. tag .. ": quality/extra clauses are not supported (quality deferred)"
        )
      end
      local sid = SIGNAL_TYPE[typ]
      if not sid then
        error(
          "signal tag "
            .. tag
            .. ": unsupported type '"
            .. typ
            .. "' (use item, fluid, or virtual-signal)"
        )
      end
      return tostring(resolver(sid, value))
    end)
  )
end
M.resolve_tags = resolve_tags

----------------------------------------------------------------------- tables
local REG = { fp = 8 }
for i = 0, 31 do
  REG["x" .. i] = i
end
local ABI = {
  "zero",
  "ra",
  "sp",
  "gp",
  "tp",
  "t0",
  "t1",
  "t2",
  "s0",
  "s1",
  "a0",
  "a1",
  "a2",
  "a3",
  "a4",
  "a5",
  "a6",
  "a7",
  "s2",
  "s3",
  "s4",
  "s5",
  "s6",
  "s7",
  "s8",
  "s9",
  "s10",
  "s11",
  "t3",
  "t4",
  "t5",
  "t6",
}
for i, n in ipairs(ABI) do
  REG[n] = i - 1
end

local CSR = {
  misa = 0x301,
  mstatus = 0x300,
  medeleg = 0x302,
  mideleg = 0x303,
  mie = 0x304,
  mtvec = 0x305,
  mcounteren = 0x306,
  scounteren = 0x106,
  mscratch = 0x340,
  mepc = 0x341,
  mcause = 0x342,
  mtval = 0x343,
  mip = 0x344,
  cycle = 0xC00,
  mvendorid = 0xF11,
  marchid = 0xF12,
  mimpid = 0xF13,
  mhartid = 0xF14,
  -- Zve32x (ADR-0012)
  vstart = 0x008,
  vxsat = 0x009,
  vxrm = 0x00A,
  vcsr = 0x00F,
  vl = 0xC20,
  vtype = 0xC21,
  vlenb = 0xC22,
}

-- vector registers v0..v31 (a class of their own; never valid where an x
-- register is expected, so they live outside REG)
local function vreg(t)
  local n = tonumber(t:gsub("%s", ""):match("^v(%d+)$") or "")
  assert(n and n <= 31, "bad vector register '" .. tostring(t) .. "'")
  return n
end

-- vtype operand list (e32, m2, ta, ma) -> vtype/zimm bits. Order-free; the
-- policy tokens default to tu,mu when omitted (gas accepts that form).
local VTYPE_TOK = {
  e8 = { sew = 0 },
  e16 = { sew = 1 },
  e32 = { sew = 2 },
  e64 = { sew = 3 }, -- encodable; the Hart flags vill (ELEN=32)
  m1 = { lmul = 0 },
  m2 = { lmul = 1 },
  m4 = { lmul = 2 },
  m8 = { lmul = 3 },
  mf8 = { lmul = 5 },
  mf4 = { lmul = 6 },
  mf2 = { lmul = 7 },
  tu = { ta = 0 },
  ta = { ta = 0x40 },
  mu = { ma = 0 },
  ma = { ma = 0x80 },
}
local function vtypebits(toks)
  local sew, lmul, ta, ma = 0, 0, 0, 0
  for _, t in ipairs(toks) do
    local d = VTYPE_TOK[t:gsub("%s", "")] or error("bad vtype operand '" .. tostring(t) .. "'")
    sew = d.sew and d.sew or sew
    lmul = d.lmul and d.lmul or lmul
    ta = d.ta and d.ta or ta
    ma = d.ma and d.ma or ma
  end
  return lmul + lsh(sew, 3) + ta + ma
end

local function reg(t)
  local r = REG[(t:gsub("%s", ""))]
  assert(r, "bad register '" .. tostring(t) .. "'")
  return r
end

local function csrnum(t)
  t = t:gsub("%s", "")
  return CSR[t] or tonumber(t) or error("bad csr '" .. t .. "'")
end

------------------------------------------------------------- constant expressions
-- C-like precedence over unsigned-32 arithmetic. Identifiers resolve via the
-- symbol table (or 0 for declared-weak undefined symbols, e.g. mtvec_handler).
local function evalexpr(s, sym, weak)
  local pos = 1
  local parse
  local function ws()
    local _, e = s:find("^%s*", pos)
    pos = e + 1
  end
  local function number()
    ws()
    local cc = s:match("^'(.)'", pos) -- character constant, e.g. 'A'
    if cc then
      pos = pos + 3
      return u32(string.byte(cc))
    end
    local h = s:match("^0[xX](%x+)", pos)
    if h then
      pos = pos + 2 + #h
      local v = 0
      for d in h:gmatch("%x") do
        v = u32(v * 16 + tonumber(d, 16))
      end
      return v
    end
    local d = s:match("^%d+", pos)
    if d then
      pos = pos + #d
      local v = 0
      for c in d:gmatch("%d") do
        v = u32(v * 10 + tonumber(c))
      end
      return v
    end
    local id = s:match("^[%a_%.][%w_%.]*", pos)
    if id then
      pos = pos + #id
      if sym and sym[id] then
        return u32(sym[id])
      end
      if weak and weak[id] then
        return 0
      end
      error("undefined symbol '" .. id .. "'")
    end
    error("bad expression near '" .. s:sub(pos) .. "'")
  end
  local function primary()
    ws()
    local c = s:sub(pos, pos)
    if c == "(" then
      pos = pos + 1
      local v = parse(0)
      ws()
      assert(s:sub(pos, pos) == ")", "missing ) in '" .. s .. "'")
      pos = pos + 1
      return v
    elseif c == "-" then
      pos = pos + 1
      return u32(-primary())
    elseif c == "~" then
      pos = pos + 1
      return u32(-1 - primary())
    elseif c == "+" then
      pos = pos + 1
      return primary()
    end
    return number()
  end
  local PREC = {
    ["*"] = 6,
    ["/"] = 6,
    ["%"] = 6,
    ["+"] = 5,
    ["-"] = 5,
    ["<<"] = 4,
    [">>"] = 4,
    ["&"] = 3,
    ["^"] = 2,
    ["|"] = 1,
  }
  local function nextop()
    ws()
    local two = s:sub(pos, pos + 1)
    if two == "<<" or two == ">>" then
      return two
    end
    local one = s:sub(pos, pos)
    if PREC[one] then
      return one
    end
  end
  parse = function(minp)
    local left = primary()
    while true do
      local op = nextop()
      if not op or PREC[op] < minp then
        break
      end
      pos = pos + #op
      local right = parse(PREC[op] + 1) -- left-associative
      if op == "*" then
        left = u32(left * right)
      elseif op == "/" then
        left = math.floor(left / right)
      elseif op == "%" then
        left = left % right
      elseif op == "+" then
        left = u32(left + right)
      elseif op == "-" then
        left = u32(left - right)
      elseif op == "<<" then
        -- assembler const-expr shift, NOT the 5-bit-masked instruction shift:
        -- `1 << 32` overflows to 0 so `(1 << 32) - 1` yields 0xFFFFFFFF. Mask the
        -- surviving low bits first so the product stays exact in a double (a wide
        -- left operand like `-1 << 31` would otherwise round).
        if right >= 32 then
          left = 0
        else
          left = u32(band(left, 2 ^ (32 - right) - 1) * 2 ^ right)
        end
      elseif op == ">>" then
        left = right >= 32 and 0 or rsh(left, right)
      elseif op == "&" then
        left = band(left, right)
      elseif op == "|" then
        left = bor(left, right)
      elseif op == "^" then
        left = rv.bxor(left, right)
      end
    end
    return left
  end
  return parse(0)
end
M.eval = evalexpr

------------------------------------------------------------------------ encoders
local function eR(op, f3, f7, rd, rs1, rs2)
  return u32(op + lsh(rd, 7) + lsh(f3, 12) + lsh(rs1, 15) + lsh(rs2, 20) + lsh(f7, 25))
end
local function eI(op, f3, rd, rs1, imm)
  return u32(op + lsh(rd, 7) + lsh(f3, 12) + lsh(rs1, 15) + lsh(band(imm, 0xFFF), 20))
end
local function eS(op, f3, rs1, rs2, imm)
  imm = band(imm, 0xFFF)
  return u32(
    op
      + lsh(bits(imm, 4, 0), 7)
      + lsh(f3, 12)
      + lsh(rs1, 15)
      + lsh(rs2, 20)
      + lsh(bits(imm, 11, 5), 25)
  )
end
local function eU(op, rd, imm20)
  return u32(op + lsh(rd, 7) + lsh(band(imm20, 0xFFFFF), 12))
end
local function eB(op, f3, rs1, rs2, off)
  off = u32(off)
  return u32(
    op
      + lsh(f3, 12)
      + lsh(rs1, 15)
      + lsh(rs2, 20)
      + lsh(bits(off, 11, 11), 7)
      + lsh(bits(off, 4, 1), 8)
      + lsh(bits(off, 10, 5), 25)
      + lsh(bits(off, 12, 12), 31)
  )
end
-- OP-V (0x57): funct6 | vm | vs2 | vs1/rs1/imm5 | funct3 | vd/rd
local function eV(f6, vm, vs2, vs1, f3, vd)
  return u32(
    0x57 + lsh(vd, 7) + lsh(f3, 12) + lsh(vs1, 15) + lsh(vs2, 20) + lsh(vm, 25) + lsh(f6, 26)
  )
end
-- vector load (0x07) / store (0x27): nf | mew=0 | mop | vm | lumop/rs2/vs2 |
-- rs1 | width | vd/vs3
local function eVmem(op, width, vm, rs1, r2, mop, nf, vreg3)
  return u32(
    op
      + lsh(vreg3, 7)
      + lsh(width, 12)
      + lsh(rs1, 15)
      + lsh(r2, 20)
      + lsh(vm, 25)
      + lsh(mop, 26)
      + lsh(nf, 29)
  )
end
local function eJ(op, rd, off)
  off = u32(off)
  return u32(
    op
      + lsh(rd, 7)
      + lsh(bits(off, 19, 12), 12)
      + lsh(bits(off, 11, 11), 20)
      + lsh(bits(off, 10, 1), 21)
      + lsh(bits(off, 20, 20), 31)
  )
end

----------------------------------------------------------------------- assemble
function M.assemble(src, resolver)
  if resolver then
    src = resolve_tags(src, resolver)
  end
  local sym, weak, locals = {}, {}, {}
  local items = {} -- { addr, gen(sym, weak, locals) -> word }
  local lc = RESET
  local lines = {} -- ponytail: addr -> source line for the Inspector gutter (ADR-0007)
  local curline = 0
  local macros, capturing, reptcap = {}, nil, nil

  local function emit(gen)
    items[#items + 1] = { addr = lc, gen = gen }
    lines[lc] = curline
    lc = lc + 4
  end

  -- data blobs: n little-endian bytes, value resolved in pass 2 (so .word/.dword
  -- can name a symbol). ponytail: values fold to u32, so a .dword's high word is
  -- always 0 -- fine, the only .dwords in the tests are tohost/fromhost = 0.
  local data = {}
  local function emit_data(n, genval)
    data[#data + 1] = { addr = lc, n = n, gen = genval }
    lc = lc + n
  end

  -- resolve an operand to an absolute target address (local label NfNb, or expr)
  local function local_label(n, fb, here)
    n = tonumber(n)
    local best
    for _, L in ipairs(locals) do
      if L.num == n then
        if fb == "f" and L.addr > here and (not best or L.addr < best) then
          best = L.addr
        elseif fb == "b" and L.addr <= here and (not best or L.addr > best) then
          best = L.addr
        end
      end
    end
    return assert(best, "unresolved local label '" .. n .. fb .. "'")
  end

  local function targetfn(tok)
    return function(here)
      -- a leading local-label ref (e.g. `1f + 10000`) resolves to its address,
      -- then the rest is constant-folded as an expression.
      local n, fb, rest = tok:match("^(%d+)([fb])(.*)$")
      if n then
        local addr = local_label(n, fb, here)
        if rest:match("^%s*$") then
          return addr
        end
        return evalexpr(tostring(addr) .. rest, sym, weak)
      end
      return evalexpr(tok, sym, weak)
    end
  end

  local function operands(rest)
    local t = {}
    for o in (rest .. ","):gmatch("(.-),") do
      o = o:match("^%s*(.-)%s*$")
      if o ~= "" then
        t[#t + 1] = o
      end
    end
    return t
  end

  -- pseudo: load a 32-bit immediate (addi, or lui+addi)
  local function li(rd, v)
    v = u32(v)
    local lo = signed(sext(band(v, 0xFFF), 12))
    if u32(lo) == v then
      emit(function()
        return eI(0x13, 0, rd, 0, lo)
      end)
    else
      local hi = rsh(u32(v - lo), 12)
      emit(function()
        return eU(0x37, rd, hi)
      end)
      emit(function()
        return eI(0x13, 0, rd, rd, lo)
      end)
    end
  end

  -- pseudo: la rd, symbol  (auipc + addi, pc-relative)
  local function la(rd, tok)
    local base = lc
    local tf = targetfn(tok)
    emit(function()
      local d = u32(tf(base) - base)
      local lo = signed(sext(band(d, 0xFFF), 12))
      local hi = rsh(u32(d - lo), 12)
      return eU(0x17, rd, hi)
    end)
    emit(function()
      local d = u32(tf(base) - base)
      local lo = signed(sext(band(d, 0xFFF), 12))
      return eI(0x13, 0, rd, rd, lo)
    end)
  end

  local function parse_mem(tok) -- "imm(reg)" -> imm, regnum
    local imm, r = tok:match("^(.-)%(%s*([%w]+)%s*%)$")
    return (imm == "" and 0 or evalexpr(imm, sym, weak)), reg(r)
  end

  -- OP-V arithmetic, table-driven (ADR-0012: families grow by table rows, not
  -- new branches). funct3 selects the operand category: OPIVV=0, OPMVV=2,
  -- OPIVI=3, OPIVX=4, OPMVX=6; the .vv/.vx/.vi suffix picks it, and a trailing
  -- `m` (.vvm/.vxm/.vim) is the carry/merge form with vm=0 and a literal v0
  -- final operand. Encoded operand order is vd, vs2, vs1/rs1/imm.
  local VF6 = {
    vadd = 0x00,
    vsub = 0x02,
    vrsub = 0x03,
    vminu = 0x04,
    vmin = 0x05,
    vmaxu = 0x06,
    vmax = 0x07,
    vand = 0x09,
    vor = 0x0A,
    vxor = 0x0B,
    vadc = 0x10,
    vmadc = 0x11,
    vsbc = 0x12,
    vmsbc = 0x13,
    vmerge = 0x17,
    vmseq = 0x18,
    vmsne = 0x19,
    vmsltu = 0x1A,
    vmslt = 0x1B,
    vmsleu = 0x1C,
    vmsle = 0x1D,
    vmsgtu = 0x1E,
    vmsgt = 0x1F,
    vsll = 0x25,
    vsrl = 0x28,
    vsra = 0x29,
  }
  local VSUFF = { vv = 0, vx = 4, vi = 3, vvm = 0, vxm = 4, vim = 3 }
  -- vmv.v.* is vmerge's encoding with vm=1 and vs2=0
  local VMV = { ["vmv.v.v"] = 0, ["vmv.v.i"] = 3, ["vmv.v.x"] = 4 }
  -- VXUNARY0 (OPMVV funct6=0x12): vs1 field encodes the widening factor/sign
  local VEXT = {
    ["vzext.vf4"] = 4,
    ["vsext.vf4"] = 5,
    ["vzext.vf2"] = 6,
    ["vsext.vf2"] = 7,
  }

  -- Vector memory mnemonic -> encoding fields + operand style. Covers every
  -- Zve32x form: unit-stride, fault-only-first, strided, indexed
  -- (ordered/unordered), mask, whole-register, and the seg<n> variants of
  -- each (ADR-0012). Styles: "unit" = vd,(rs1); "stride" = vd,(rs1),xreg;
  -- "index" = vd,(rs1),vreg. Returns nil for non-memory mnemonics.
  local WIDTH_F3 = { ["8"] = 0, ["16"] = 5, ["32"] = 6, ["64"] = 7 }
  local function vmemform(m)
    local ls, rest = m:match("^v([ls])(.+)%.v$")
    if not ls then
      return nil
    end
    local op = ls == "l" and 0x07 or 0x27
    local n, e
    n, e = rest:match("^(%d)re(%d+)$") -- whole-register load
    if n and op == 0x07 then
      return { op = op, nf = n - 1, mop = 0, um = 0x08, w = WIDTH_F3[e], style = "unit" }
    end
    n = rest:match("^(%d)r$") -- whole-register store (EEW=8 form only)
    if n and op == 0x27 then
      return { op = op, nf = n - 1, mop = 0, um = 0x08, w = 0, style = "unit" }
    end
    if rest == "m" then -- vlm/vsm mask load/store
      return { op = op, nf = 0, mop = 0, um = 0x0B, w = 0, style = "unit", nomask = true }
    end
    n, e = rest:match("^seg(%d)e(%d+)$") -- unit-stride segment
    if n then
      return { op = op, nf = n - 1, mop = 0, um = 0, w = WIDTH_F3[e], style = "unit" }
    end
    n, e = rest:match("^seg(%d)e(%d+)ff$") -- fault-only-first segment
    if n and op == 0x07 then
      return { op = op, nf = n - 1, mop = 0, um = 0x10, w = WIDTH_F3[e], style = "unit" }
    end
    n, e = rest:match("^sseg(%d)e(%d+)$") -- strided segment
    if n then
      return { op = op, nf = n - 1, mop = 2, w = WIDTH_F3[e], style = "stride" }
    end
    local ord
    ord, n, e = rest:match("^([ou])xseg(%d)ei(%d+)$") -- indexed segment
    if ord then
      return { op = op, nf = n - 1, mop = ord == "o" and 3 or 1, w = WIDTH_F3[e], style = "index" }
    end
    ord, e = rest:match("^([ou])xei(%d+)$") -- indexed
    if ord then
      return { op = op, nf = 0, mop = ord == "o" and 3 or 1, w = WIDTH_F3[e], style = "index" }
    end
    e = rest:match("^se(%d+)$") -- strided
    if e then
      return { op = op, nf = 0, mop = 2, w = WIDTH_F3[e], style = "stride" }
    end
    e = rest:match("^e(%d+)ff$") -- fault-only-first
    if e and op == 0x07 then
      return { op = op, nf = 0, mop = 0, um = 0x10, w = WIDTH_F3[e], style = "unit" }
    end
    e = rest:match("^e(%d+)$") -- unit-stride
    if e then
      return { op = op, nf = 0, mop = 0, um = 0, w = WIDTH_F3[e], style = "unit" }
    end
    return nil
  end

  local ALU = {
    add = { 0, 0 },
    sub = { 0, 0x20 },
    sll = { 1, 0 },
    slt = { 2, 0 },
    sltu = { 3, 0 },
    ["xor"] = { 4, 0 },
    srl = { 5, 0 },
    sra = { 5, 0x20 },
    ["or"] = { 6, 0 },
    ["and"] = { 7, 0 },
    -- M extension (funct7 = 1)
    mul = { 0, 1 },
    mulh = { 1, 1 },
    mulhsu = { 2, 1 },
    mulhu = { 3, 1 },
    div = { 4, 1 },
    divu = { 5, 1 },
    rem = { 6, 1 },
    remu = { 7, 1 },
  }
  local ALUI = { addi = 0, slti = 2, sltiu = 3, xori = 4, ori = 6, andi = 7 }
  local BR = { beq = 0, bne = 1, blt = 4, bge = 5, bltu = 6, bgeu = 7 }

  -- gas accepts an immediate 3rd operand on these R-type mnemonics as the I-type
  -- alias (e.g. `sll gp,gp,1` == slli, `or gp,gp,1` == ori). riscv-tests uses it.
  local RTOIMM = {
    add = "addi",
    ["and"] = "andi",
    ["or"] = "ori",
    ["xor"] = "xori",
    sll = "slli",
    srl = "srli",
    sra = "srai",
    slt = "slti",
    sltu = "sltiu",
  }

  local function instr(m, rest)
    local o = operands(rest)
    if RTOIMM[m] and o[3] and not REG[(o[3]:gsub("%s", ""))] then
      m = RTOIMM[m]
    end
    if ALU[m] then
      local f3, f7 = ALU[m][1], ALU[m][2]
      local rd, a, b1 = reg(o[1]), reg(o[2]), reg(o[3])
      emit(function()
        return eR(0x33, f3, f7, rd, a, b1)
      end)
    elseif ALUI[m] then
      local f3 = ALUI[m]
      local rd, rs1 = reg(o[1]), reg(o[2])
      emit(function(s, w)
        return eI(0x13, f3, rd, rs1, signed(sext(evalexpr(o[3], s, w), 32)))
      end)
    elseif m == "slli" or m == "srli" or m == "srai" then
      local rd, rs1 = reg(o[1]), reg(o[2])
      local sh = band(evalexpr(o[3], sym, weak), 0x1F)
      local f3 = (m == "slli") and 1 or 5
      local hi = (m == "srai") and 0x400 or 0
      emit(function()
        return eI(0x13, f3, rd, rs1, hi + sh)
      end)
    elseif m == "lui" or m == "auipc" then
      local rd = reg(o[1])
      local op = (m == "lui") and 0x37 or 0x17
      emit(function(s, w)
        return eU(op, rd, band(evalexpr(o[2], s, w), 0xFFFFF))
      end)
    elseif m == "li" then
      li(reg(o[1]), evalexpr(o[2], sym, weak))
    elseif m == "la" or m == "lla" then -- both pc-relative in our flat image
      la(reg(o[1]), o[2])
    elseif m == "mv" then
      local rd, rs = reg(o[1]), reg(o[2])
      emit(function()
        return eI(0x13, 0, rd, rs, 0)
      end)
    elseif m == "nop" then
      emit(function()
        return eI(0x13, 0, 0, 0, 0)
      end)
    elseif BR[m] then
      local f3, rs1, rs2, tf = BR[m], reg(o[1]), reg(o[2]), targetfn(o[3])
      emit(function(_, _, _, here)
        return eB(0x63, f3, rs1, rs2, tf(here) - here)
      end)
    elseif m == "beqz" or m == "bnez" then
      local f3, rs1, tf = (m == "beqz") and 0 or 1, reg(o[1]), targetfn(o[2])
      emit(function(_, _, _, here)
        return eB(0x63, f3, rs1, 0, tf(here) - here)
      end)
    elseif m == "ble" or m == "bgt" or m == "bleu" or m == "bgtu" then
      -- a <= b is b >= a, a > b is b < a: same op with operands swapped
      local f3 = ({ ble = 5, bgt = 4, bleu = 7, bgtu = 6 })[m]
      local rs1, rs2, tf = reg(o[2]), reg(o[1]), targetfn(o[3])
      emit(function(_, _, _, here)
        return eB(0x63, f3, rs1, rs2, tf(here) - here)
      end)
    elseif m == "j" then
      local tf = targetfn(o[1])
      emit(function(_, _, _, here)
        return eJ(0x6F, 0, tf(here) - here)
      end)
    elseif m == "jal" then
      local rd, tf = (#o == 1) and 1 or reg(o[1]), targetfn(o[#o])
      emit(function(_, _, _, here)
        return eJ(0x6F, rd, tf(here) - here)
      end)
    elseif m == "jr" then
      local rs = reg(o[1])
      local off = o[2] and evalexpr(o[2], sym, weak) or 0
      emit(function()
        return eI(0x67, 0, 0, rs, off)
      end)
    elseif m == "jalr" then
      local rd, rs1, off
      if #o == 1 then -- jalr rs  ->  jalr ra, 0(rs)
        rd, rs1, off = 1, reg(o[1]), 0
      elseif #o == 2 and o[2]:find("%(") then -- jalr rd, off(rs1)
        local imm, r = parse_mem(o[2])
        rd, rs1, off = reg(o[1]), r, imm
      elseif #o == 2 then -- jalr rd, rs1
        rd, rs1, off = reg(o[1]), reg(o[2]), 0
      else -- jalr rd, rs1, imm
        rd, rs1, off = reg(o[1]), reg(o[2]), evalexpr(o[3], sym, weak)
      end
      emit(function()
        return eI(0x67, 0, rd, rs1, off)
      end)
    elseif m == "ret" then
      emit(function()
        return eI(0x67, 0, 0, 1, 0)
      end)
    elseif m == "lw" or m == "lh" or m == "lb" or m == "lhu" or m == "lbu" then
      local f3 = ({ lb = 0, lh = 1, lw = 2, lbu = 4, lhu = 5 })[m]
      local rd = reg(o[1])
      if o[2]:find("%(") then
        local off, rs1 = parse_mem(o[2])
        emit(function()
          return eI(0x03, f3, rd, rs1, off)
        end)
      else -- pseudo: l rd, symbol  (auipc rd, %pcrel_hi ; l rd, %pcrel_lo(rd))
        local base = lc
        local tf = targetfn(o[2])
        emit(function()
          local d = u32(tf(base) - base)
          local lo = signed(sext(band(d, 0xFFF), 12))
          return eU(0x17, rd, rsh(u32(d - lo), 12))
        end)
        emit(function()
          local d = u32(tf(base) - base)
          return eI(0x03, f3, rd, rd, signed(sext(band(d, 0xFFF), 12)))
        end)
      end
    elseif m == "sw" or m == "sh" or m == "sb" then
      local f3 = ({ sb = 0, sh = 1, sw = 2 })[m]
      if #o == 3 and not o[2]:find("%(") then -- pseudo: sw rs, symbol, rt
        local rs2, rt = reg(o[1]), reg(o[3])
        la(rt, o[2])
        emit(function()
          return eS(0x23, f3, rt, rs2, 0)
        end)
      else
        local rs2 = reg(o[1])
        local off, rs1 = parse_mem(o[2])
        emit(function()
          return eS(0x23, f3, rs1, rs2, off)
        end)
      end
    elseif m == "csrr" then
      local rd, c = reg(o[1]), csrnum(o[2])
      emit(function()
        return eI(0x73, 2, rd, 0, c)
      end)
    elseif m == "csrw" then
      local c, rs = csrnum(o[1]), reg(o[2])
      emit(function()
        return eI(0x73, 1, 0, rs, c)
      end)
    elseif m == "csrwi" then
      local c, zimm = csrnum(o[1]), band(evalexpr(o[2], sym, weak), 0x1F)
      emit(function()
        return eI(0x73, 5, 0, zimm, c)
      end)
    elseif m == "csrrw" or m == "csrrs" or m == "csrrc" then
      local f3 = ({ csrrw = 1, csrrs = 2, csrrc = 3 })[m]
      local rd, c, rs = reg(o[1]), csrnum(o[2]), reg(o[3])
      emit(function()
        return eI(0x73, f3, rd, rs, c)
      end)
    elseif m == "csrrwi" or m == "csrrsi" or m == "csrrci" then
      local f3 = ({ csrrwi = 5, csrrsi = 6, csrrci = 7 })[m]
      local rd, c, zimm = reg(o[1]), csrnum(o[2]), band(evalexpr(o[3], sym, weak), 0x1F)
      emit(function()
        return eI(0x73, f3, rd, zimm, c)
      end)
    elseif m == "csrs" or m == "csrc" then -- pseudo: csrr[sc] x0, csr, rs
      local f3 = m == "csrs" and 2 or 3
      local c, rs = csrnum(o[1]), reg(o[2])
      emit(function()
        return eI(0x73, f3, 0, rs, c)
      end)
    elseif m == "csrsi" or m == "csrci" then -- pseudo: csrr[sc]i x0, csr, imm
      local f3 = m == "csrsi" and 6 or 7
      local c, zimm = csrnum(o[1]), band(evalexpr(o[2], sym, weak), 0x1F)
      emit(function()
        return eI(0x73, f3, 0, zimm, c)
      end)
    elseif m == "fence" then
      emit(function()
        return 0x0FF0000F
      end)
    elseif m == "fence.i" then
      emit(function()
        return 0x0000100F
      end)
    elseif m == "ecall" or m == "scall" then
      emit(function()
        return 0x00000073
      end)
    elseif m == "ebreak" or m == "sbreak" then
      emit(function()
        return 0x00100073
      end)
    elseif m == "mret" then
      emit(function()
        return 0x30200073
      end)
    elseif m == "wfi" then -- no async interrupts in our model: a nop
      emit(function()
        return 0x10500073
      end)
    elseif m == "unimp" then
      emit(function()
        return 0xC0001073
      end)
    elseif m == "vsetvli" then
      local rd, rs1 = reg(o[1]), reg(o[2])
      local z = vtypebits({ table.unpack(o, 3) })
      emit(function()
        return eI(0x57, 7, rd, rs1, z)
      end)
    elseif m == "vsetivli" then
      local rd = reg(o[1])
      local uimm = band(evalexpr(o[2], sym, weak), 0x1F)
      local z = vtypebits({ table.unpack(o, 3) })
      emit(function()
        return eI(0x57, 7, rd, uimm, 0xC00 + z)
      end)
    elseif m == "vsetvl" then
      local rd, rs1, rs2 = reg(o[1]), reg(o[2]), reg(o[3])
      emit(function()
        return eR(0x57, 7, 0x40, rd, rs1, rs2)
      end)
    elseif vmemform(m) then
      local fm = vmemform(m)
      local vd = vreg(o[1])
      local _, rs1 = parse_mem(o[2])
      local r2, masked
      if fm.style == "stride" then
        r2 = reg(o[3])
        masked = o[4] == "v0.t"
      elseif fm.style == "index" then
        r2 = vreg(o[3])
        masked = o[4] == "v0.t"
      else
        r2 = fm.um
        masked = o[3] == "v0.t"
      end
      local vm = (masked and not fm.nomask) and 0 or 1
      emit(function()
        return eVmem(fm.op, fm.w, vm, rs1, r2, fm.mop, fm.nf, vd)
      end)
    elseif VF6[m:match("^(v%w+)%.")] and VSUFF[m:match("%.(v[vxi]m?)$")] then
      local f6, f3 = VF6[m:match("^(v%w+)%.")], VSUFF[m:match("%.(v[vxi]m?)$")]
      local vd, vs2 = vreg(o[1]), vreg(o[2])
      -- carry/merge forms name v0 as their final operand; masked forms say v0.t
      local vm = (m:sub(-1) == "m" or o[4] == "v0.t") and 0 or 1
      local vs1 -- register number or masked immediate, per operand category
      if f3 == 3 then
        vs1 = band(evalexpr(o[3], sym, weak), 0x1F)
      elseif f3 == 4 then
        vs1 = reg(o[3])
      else
        vs1 = vreg(o[3])
      end
      emit(function()
        return eV(f6, vm, vs2, vs1, f3, vd)
      end)
    elseif VMV[m] then
      local f3 = VMV[m]
      local vd = vreg(o[1])
      local vs1
      if f3 == 3 then
        vs1 = band(evalexpr(o[2], sym, weak), 0x1F)
      elseif f3 == 4 then
        vs1 = reg(o[2])
      else
        vs1 = vreg(o[2])
      end
      emit(function()
        return eV(0x17, 1, 0, vs1, f3, vd)
      end)
    elseif VEXT[m] then
      local code = VEXT[m]
      local vd, vs2 = vreg(o[1]), vreg(o[2])
      local vm = o[3] == "v0.t" and 0 or 1
      emit(function()
        return eV(0x12, vm, vs2, code, 2, vd)
      end)
    else
      error("unsupported instruction '" .. m .. "'")
    end
  end

  -- directives the flattened single-section image ignores (see header note).
  local NOOP_DIRECTIVE = {
    [".globl"] = true,
    [".global"] = true,
    [".section"] = true,
    [".data"] = true,
    [".text"] = true,
    [".pushsection"] = true,
    [".popsection"] = true,
    [".size"] = true,
    [".type"] = true,
    [".string"] = true,
    [".file"] = true,
    [".option"] = true,
  }

  local function directive(d, rest)
    if d == ".align" or d == ".p2align" then
      local a = 2 ^ tonumber(rest:match("^%d+"))
      local target = math.ceil(lc / a) * a
      -- pad whole words with nop so PC flowing through a .text gap stays legal;
      -- any sub-word remainder (only from .byte/.half data) is just skipped.
      while lc % 4 == 0 and lc + 4 <= target do
        emit(function()
          return 0x13 -- addi x0, x0, 0
        end)
      end
      lc = target
    elseif d == ".dword" or d == ".quad" or d == ".word" or d == ".half" or d == ".byte" then
      local n = ({ [".dword"] = 8, [".quad"] = 8, [".word"] = 4, [".half"] = 2, [".byte"] = 1 })[d]
      for e in (rest .. ","):gmatch("%s*(.-)%s*,") do -- comma-separated values
        -- 8-byte data: a plain hex literal wider than 32 bits keeps its real
        -- high word (riscv-vector-tests test data is .quad-packed); computed
        -- expressions stay u32 with a zero high word, which is all the
        -- riscv-tests fixtures ever put there.
        local hex = n == 8 and e:match("^0[xX](%x+)$")
        if hex and #hex > 8 then
          local lo, hi = tonumber(hex:sub(-8), 16), tonumber(hex:sub(1, -9), 16)
          emit_data(n, function()
            return lo, hi
          end)
        else
          emit_data(n, function(s, wk)
            return evalexpr(e, s, wk)
          end)
        end
      end
    elseif d == ".fill" then
      -- .fill repeat, size, value
      local rep, size, val = rest:match("^([^,]+),%s*([^,]+),%s*(.+)$")
      rep, size = evalexpr(rep, sym, weak), evalexpr(size, sym, weak)
      for _ = 1, rep do
        emit_data(size, function(s, wk)
          return evalexpr(val, s, wk)
        end)
      end
    elseif d == ".zero" or d == ".skip" then
      emit_data(evalexpr(rest:match("^[^,]+"), sym, weak), function()
        return 0
      end)
    elseif d == ".weak" then
      weak[rest:match("^[%w_%.]+")] = true
    elseif not NOOP_DIRECTIVE[d] then
      error("unknown directive '" .. d .. "'")
    end
  end

  local function do_stmt(t)
    while true do -- peel leading labels
      local lbl, rest = t:match("^([%w_%.%$]+):%s*(.*)$")
      if not lbl then
        break
      end
      if lbl:match("^%d+$") then
        locals[#locals + 1] = { num = tonumber(lbl), addr = lc }
      else
        sym[lbl] = lc
      end
      t = rest
    end
    if t == "" then
      return
    end
    local mnem, rest = t:match("^([%.%w_]+)%s*(.*)$")
    rest = rest or ""
    if capturing then
      if mnem == ".endm" then
        capturing = nil
      else
        table.insert(macros[capturing], t)
      end
      return
    end
    if reptcap then
      if mnem == ".endr" then
        local body, n = reptcap.body, reptcap.count
        reptcap = nil
        for _ = 1, n do
          for _, b in ipairs(body) do
            do_stmt(b)
          end
        end
      else
        table.insert(reptcap.body, t)
      end
      return
    end
    if mnem == ".rept" then
      reptcap = { count = evalexpr(rest, sym, weak), body = {} }
      return
    end
    if mnem == ".macro" then
      capturing = rest:match("^(%w+)")
      macros[capturing] = {}
      return
    end
    if macros[mnem] then
      for _, body in ipairs(macros[mnem]) do
        do_stmt(body)
      end
      return
    end
    if mnem:sub(1, 1) == "." then
      directive(mnem, rest)
    else
      instr(mnem, rest)
    end
  end

  -- statement stream: per line, strip comments, split on ';'
  local lineno = 0
  for line in (src .. "\n"):gmatch("(.-)\n") do
    lineno = lineno + 1
    curline = lineno
    line = line:gsub("#.*", "")
    for part in (line .. ";"):gmatch("(.-);") do
      local s = part:match("^%s*(.-)%s*$")
      if s ~= "" then
        do_stmt(s)
      end
    end
  end

  -- pass 2: encode instructions and unpack data blobs to little-endian bytes
  local words = {}
  for _, it in ipairs(items) do
    words[it.addr] = it.gen(sym, weak, locals, it.addr)
  end
  local bytes = {}
  for _, d in ipairs(data) do
    local lo, hi = d.gen(sym, weak)
    lo, hi = u32(lo), u32(hi or 0)
    for i = 0, d.n - 1 do
      bytes[d.addr + i] = band(rsh(i < 4 and lo or hi, (i % 4) * 8), 0xFF)
    end
  end
  return { words = words, bytes = bytes, symbols = sym, entry = RESET, lines = lines }
end

return M
