-- Examples gate (#28, ADR-0008): the Manual's worked programs are real, runnable
-- assembly. Beyond assembling cleanly, each one is executed on a Hart and asserted
-- to do what the chapter says it does -- so a broken example can't ship.
local asm = require("asm")
local Hart = require("hart")
local Mem = require("mem")
local io = require("iocontroller")
local SignalMap = require("signalmap")
local content = require("lib.manual.content")

-- assemble source and build a loaded Hart at the entry point.
local function build(src)
  local h = Hart.new(Mem.new())
  h:load(asm.assemble(src))
  return h
end

-- Step up to `max` instructions, stopping on a tohost halt or a runtime error. The
-- snippets are fragments: once their work is done they run off the end into unmapped
-- memory and fault, which is expected -- we assert the state they leave behind.
-- `service` (optional) runs after each step to drain an I/O doorbell, like control.lua.
local function drive(h, max, service)
  for _ = 1, max do
    local ok = pcall(h.step, h)
    if service then
      service(h)
    end
    if not ok or h.tohost ~= nil then
      break
    end
  end
end

-- the Examples chapter's code blocks, in authored order: 1 sum, 2 frame, 3 io, 4 trap.
local EX = {}
for _, ch in ipairs(content) do
  if ch.id == "examples" then
    for _, b in ipairs(ch.blocks) do
      if b.kind == "code" then
        EX[#EX + 1] = b.text
      end
    end
  end
end

describe("Manual example programs", function()
  it("ships the four worked programs", function()
    assert.are.equal(4, #EX)
  end)

  it("sum: leaves 1+2+...+10 = 55 in a0", function()
    local h = build(EX[1])
    drive(h, 100)
    assert.are.equal(55, h.x[10]) -- a0
  end)

  it("stack frame: preserves the argument across the call (a0 = a0 + s0)", function()
    local h = build(EX[2])
    h.x[10] = 7 -- a0: the incoming argument
    drive(h, 100)
    assert.are.equal(14, h.x[10]) -- mv s0,a0 then add a0,a0,s0 -> 7 + 7
  end)

  it("read-compute-commit: doubles the sampled signal and commits it", function()
    local sm = SignalMap.new()
    local id = sm:lookup_or_alloc("item", "iron-plate")
    local input = { red = { [id] = 21 }, green = {} }
    local committed
    local function service(h)
      local d = h.doorbell
      if not d then
        return
      end
      h.doorbell = nil
      if d.off == io.SAMPLE then
        io.sample(h.mem, input, d.value)
      elseif d.off == io.COMMIT then
        committed = io.commit(h.mem, sm)
      end
    end

    local h = build(EX[3])
    h.io_base = io.BASE
    drive(h, 100, service)

    assert.is_truthy(committed)
    assert.are.equal(1, #committed)
    assert.are.equal(id, committed[1].id)
    assert.are.equal(42, committed[1].value) -- 21 doubled
  end)

  it("trap handler: an ecall reaches the handler with mcause = machine ecall", function()
    local h = build(EX[4])
    drive(h, 100)
    assert.are.equal(11, h.csr[0x342]) -- mcause = environment call from M-mode
    assert.are.equal(11, h.x[6]) -- handler read it: csrr t1, mcause
  end)
end)

-- belt and braces: every code block anywhere in the Manual still assembles, so a new
-- snippet in any chapter can't rot even if it isn't executed above.
describe("Manual code blocks", function()
  for _, ch in ipairs(content) do
    for _, b in ipairs(ch.blocks) do
      if b.kind == "code" then
        it("assembles the snippet in " .. ch.id, function()
          assert.has_no.errors(function()
            asm.assemble(b.text)
          end)
        end)
      end
    end
  end
end)
