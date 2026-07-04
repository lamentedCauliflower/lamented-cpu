-- riscv-tests conformance: assemble each allowlisted .s, run the Hart to halt,
-- assert tohost == 1 (ADR-0004). The allowlist grows as later slices implement
-- more instructions, keeping the gate green every slice.
local asm = require("asm")
local Mem = require("mem")
local Hart = require("hart")

local FIXTURES = "spec/fixtures/riscv-tests/"
local VFIXTURES = "spec/fixtures/riscv-vector-tests/"

-- ponytail: the allowlist grows one slice at a time. Slices #5-#6 add the
-- load/store and control-flow fixtures; #9 adds rv32um (M extension).
local ALLOW = {
  -- #3 walking skeleton + #4 RV32I ALU (reg-reg, reg-imm, lui, auipc)
  "rv32ui-p-simple",
  "rv32ui-p-add",
  "rv32ui-p-addi",
  "rv32ui-p-sub",
  "rv32ui-p-and",
  "rv32ui-p-andi",
  "rv32ui-p-or",
  "rv32ui-p-ori",
  "rv32ui-p-xor",
  "rv32ui-p-xori",
  "rv32ui-p-sll",
  "rv32ui-p-slli",
  "rv32ui-p-srl",
  "rv32ui-p-srli",
  "rv32ui-p-sra",
  "rv32ui-p-srai",
  "rv32ui-p-slt",
  "rv32ui-p-slti",
  "rv32ui-p-sltu",
  "rv32ui-p-sltiu",
  "rv32ui-p-lui",
  "rv32ui-p-auipc",
  -- #5 RV32I load/store (misaligned handled in-hardware, not trapped)
  "rv32ui-p-lb",
  "rv32ui-p-lbu",
  "rv32ui-p-lh",
  "rv32ui-p-lhu",
  "rv32ui-p-lw",
  "rv32ui-p-sb",
  "rv32ui-p-sh",
  "rv32ui-p-sw",
  "rv32ui-p-ld_st",
  "rv32ui-p-st_ld",
  "rv32ui-p-ma_data",
  -- #6 RV32I control flow (branches + jumps); fence_i is a nop for one hart
  "rv32ui-p-beq",
  "rv32ui-p-bne",
  "rv32ui-p-blt",
  "rv32ui-p-bge",
  "rv32ui-p-bltu",
  "rv32ui-p-bgeu",
  "rv32ui-p-jal",
  "rv32ui-p-jalr",
  "rv32ui-p-fence_i",
  -- #9 M extension
  "rv32um-p-mul",
  "rv32um-p-mulh",
  "rv32um-p-mulhsu",
  "rv32um-p-mulhu",
  "rv32um-p-div",
  "rv32um-p-divu",
  "rv32um-p-rem",
  "rv32um-p-remu",
  -- #7 M-mode CSR/trap core: mret, mstatus/MPP, illegal trap, misa/mhartid.
  -- The misalign-trap variants (ma_addr, *-misaligned) conflict with the
  -- already-green rv32ui ma_data, and pmpaddr/breakpoint/instret_overflow/
  -- zicntr need out-of-scope extensions -- both groups stay descoped.
  "rv32mi-p-csr",
  "rv32mi-p-mcsr",
  "rv32mi-p-scall",
  "rv32mi-p-sbreak",
  "rv32mi-p-shamt",
}

-- Zve32x conformance: riscv-vector-tests fixtures (ADR-0012), same pipeline,
-- separate allowlist -- it grows per instruction family until the full zve32x
-- preset is green (#37..#47; the ship gate lives in #47).
local VALLOW = {
  -- #37 walking skeleton
  "vadd_vv-0",
  "vadd_vv-1",
}

local function read(path)
  local f = assert(io.open(path, "r"), "missing fixture: " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

local function conformance(dir, name, max_steps)
  local image = asm.assemble(read(dir .. name .. ".s"))
  local hart = Hart.new(Mem.new())
  hart:load(image)
  local r = hart:run({ max_steps = max_steps })
  assert.is_truthy(r.tohost, "no tohost write within step budget (hung?)")
  local testnum = math.floor((r.tohost or 0) / 2)
  assert.are.equal(1, r.tohost, "failed at test #" .. testnum)
end

describe("riscv-tests conformance", function()
  for _, name in ipairs(ALLOW) do
    it(name .. " passes", function()
      conformance(FIXTURES, name, 200000)
    end)
  end
end)

describe("riscv-vector-tests conformance", function()
  for _, name in ipairs(VALLOW) do
    it(name .. " passes", function()
      conformance(VFIXTURES, name, 2000000)
    end)
  end
end)
