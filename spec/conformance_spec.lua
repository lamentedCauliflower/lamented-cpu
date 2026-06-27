-- riscv-tests conformance: assemble each allowlisted .s, run the Hart to halt,
-- assert tohost == 1 (ADR-0004). The allowlist grows as later slices implement
-- more instructions, keeping the gate green every slice.
local asm = require("asm")
local Mem = require("mem")
local Hart = require("hart")

local FIXTURES = "spec/fixtures/riscv-tests/"

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
}

local function read(path)
  local f = assert(io.open(path, "r"), "missing fixture: " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

describe("riscv-tests conformance", function()
  for _, name in ipairs(ALLOW) do
    it(name .. " passes", function()
      local image = asm.assemble(read(FIXTURES .. name .. ".s"))
      local hart = Hart.new(Mem.new())
      hart:load(image)
      local r = hart:run({ max_steps = 200000 })
      assert.is_truthy(r.tohost, "no tohost write within step budget (hung?)")
      local testnum = math.floor((r.tohost or 0) / 2)
      assert.are.equal(1, r.tohost, "failed at test #" .. testnum)
    end)
  end
end)
