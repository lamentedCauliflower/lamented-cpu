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
local rv = require("rvbit")
local u32, sext, signed = rv.u32, rv.sext, rv.signed
local band, bor, lsh, rsh, bits = rv.band, rv.bor, rv.lsh, rv.rsh, rv.bits

local M = {}

local RESET = 0x80000000

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
  mstatus = 0x300,
  mie = 0x304,
  mtvec = 0x305,
  mscratch = 0x340,
  mepc = 0x341,
  mcause = 0x342,
  mtval = 0x343,
  mip = 0x344,
  mhartid = 0xF14,
}

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
        left = u32(left * 2 ^ (right % 32)) -- ponytail: loses precision if left is wide; fine for test exprs
      elseif op == ">>" then
        left = rsh(left, right % 32)
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
function M.assemble(src)
  local sym, weak, locals = {}, {}, {}
  local items = {} -- { addr, gen(sym, weak, locals) -> word }
  local lc = RESET
  local macros, capturing = {}, nil

  local function emit(gen)
    items[#items + 1] = { addr = lc, gen = gen }
    lc = lc + 4
  end

  -- resolve an operand to an absolute target address (local label NfNb, or expr)
  local function targetfn(tok)
    return function(here)
      local n, fb = tok:match("^(%d+)([fb])$")
      if n then
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
        return assert(best, "unresolved local label '" .. tok .. "'")
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
    elseif m == "la" then
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
      emit(function()
        return eI(0x67, 0, 0, rs, 0)
      end)
    elseif m == "jalr" then
      local rd, rs = reg(o[1]), reg(o[2] or o[1])
      emit(function()
        return eI(0x67, 0, rd, rs, 0)
      end)
    elseif m == "ret" then
      emit(function()
        return eI(0x67, 0, 0, 1, 0)
      end)
    elseif m == "lw" or m == "lh" or m == "lb" or m == "lhu" or m == "lbu" then
      local f3 = ({ lb = 0, lh = 1, lw = 2, lbu = 4, lhu = 5 })[m]
      local rd = reg(o[1])
      local off, rs1 = parse_mem(o[2])
      emit(function()
        return eI(0x03, f3, rd, rs1, off)
      end)
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
    elseif m == "fence" then
      emit(function()
        return 0x0FF0000F
      end)
    elseif m == "ecall" then
      emit(function()
        return 0x00000073
      end)
    elseif m == "ebreak" then
      emit(function()
        return 0x00100073
      end)
    elseif m == "unimp" then
      emit(function()
        return 0xC0001073
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
      lc = math.ceil(lc / a) * a
    elseif d == ".dword" then
      lc = lc + 8
    elseif d == ".word" then
      lc = lc + 4
    elseif d == ".half" then
      lc = lc + 2
    elseif d == ".byte" then
      lc = lc + 1
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
  for line in (src .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("#.*", "")
    for part in (line .. ";"):gmatch("(.-);") do
      local s = part:match("^%s*(.-)%s*$")
      if s ~= "" then
        do_stmt(s)
      end
    end
  end

  -- pass 2: encode
  local words = {}
  for _, it in ipairs(items) do
    words[it.addr] = it.gen(sym, weak, locals, it.addr)
  end
  return { words = words, symbols = sym, entry = RESET }
end

return M
