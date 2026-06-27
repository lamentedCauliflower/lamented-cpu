-- riscv-tests conformance: assemble each allowlisted .s, run the Hart to halt,
-- assert tohost == 1 (ADR-0004). The allowlist grows as later slices implement
-- more instructions, keeping the gate green every slice.
local asm = require("asm")
local Mem = require("mem")
local Hart = require("hart")

local FIXTURES = "spec/fixtures/riscv-tests/"

-- ponytail: start at the single simplest test. Slices #3-#6 extend this list.
local ALLOW = {
  "rv32ui-p-add",
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
