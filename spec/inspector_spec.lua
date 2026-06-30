-- Pure Inspector core: the Enable x Transport state machine + lifecycle
-- (Inspector 2/5). Driven directly, no engine, no resolver (tag-free sources).
local Inspector = require("inspector")

-- increments a0 forever (never halts): for run/pause/step transitions
local COUNT = "li a0, 0\nloop:\n  addi a0, a0, 1\n  j loop\n"

-- writes tohost = 1 then spins: for halt detection (li, la=2, sw = 4 instructions)
local HALT = [[
  li a0, 1
  la t0, tohost
  sw a0, 0(t0)
loop:
  j loop
.section .data
.align 6
tohost: .dword 0
]]

describe("Inspector transport", function()
  it("defaults to On but stopped, and dirty", function()
    local st = Inspector.new(COUNT)
    assert.are.equal("stopped", st.mode)
    assert.is_true(st.dirty)
    assert.is_true(st.enabled) -- On by default; idle until Run
  end)

  it("transport is inert while Off", function()
    local st = Inspector.new(COUNT)
    Inspector.enable(st, false)
    Inspector.run(st) -- Off => no-op
    assert.are.equal("stopped", st.mode)
    assert.is_nil(st.hart)
  end)

  it("Run from stopped assembles, resets, and runs", function()
    local st = Inspector.new(COUNT)
    Inspector.enable(st, true)
    Inspector.run(st)
    assert.are.equal("running", st.mode)
    assert.is_false(st.dirty)
    assert.are.equal(0x80000000, st.hart.pc) -- at entry, not yet stepped
  end)

  it("Step executes exactly one instruction and parks paused", function()
    local st = Inspector.new(COUNT)
    Inspector.enable(st, true)
    Inspector.step(st) -- assemble+reset, then run `li a0, 0`
    assert.are.equal("paused", st.mode)
    assert.are.equal(0x80000004, st.hart.pc)
    assert.are.equal(0, st.hart.x[10]) -- a0
    Inspector.step(st) -- `addi a0, a0, 1`
    assert.are.equal(1, st.hart.x[10])
  end)

  it("Run from a clean pause resumes the same Hart (no reassemble)", function()
    local st = Inspector.new(COUNT)
    Inspector.enable(st, true)
    Inspector.run(st)
    local h = st.hart
    Inspector.pause(st)
    assert.are.equal("paused", st.mode)
    Inspector.run(st)
    assert.are.equal("running", st.mode)
    assert.are.equal(h, st.hart) -- same instance: resumed, not rebuilt
  end)

  it("Stop from paused returns to stopped and forces a reassemble", function()
    local st = Inspector.new(COUNT)
    Inspector.enable(st, true)
    Inspector.run(st)
    local h = st.hart
    Inspector.pause(st)
    Inspector.stop(st)
    assert.are.equal("stopped", st.mode)
    assert.is_true(st.dirty)
    Inspector.run(st)
    assert.are.equal("running", st.mode)
    assert.are_not.equal(h, st.hart) -- Stop forced a fresh assemble, not a resume
  end)

  it("editing stales the Hart so the next Run reassembles", function()
    local st = Inspector.new(COUNT)
    Inspector.enable(st, true)
    Inspector.run(st)
    local h = st.hart
    Inspector.pause(st)
    Inspector.edit(st, COUNT .. "  nop\n")
    assert.is_true(st.dirty)
    Inspector.run(st)
    assert.are_not.equal(h, st.hart) -- rebuilt from edited source
  end)

  it("Off parks a running Hart in paused and holds it there", function()
    local st = Inspector.new(COUNT)
    Inspector.enable(st, true)
    Inspector.run(st)
    Inspector.enable(st, false)
    assert.are.equal("paused", st.mode)
    assert.is_false(st.enabled)
    Inspector.enable(st, true) -- back On: stays paused, not auto-running
    assert.are.equal("paused", st.mode)
  end)

  it("detects a tohost halt and reports pass", function()
    local st = Inspector.new(HALT)
    Inspector.enable(st, true)
    Inspector.run(st)
    for _ = 1, 10 do
      if st.mode ~= "running" then
        break
      end
      Inspector.tick(st)
    end
    assert.are.equal("halted", st.mode)
    assert.are.equal("halted: pass", st.status)
  end)

  it("an assemble error parks in error and keeps the prior Hart", function()
    local st = Inspector.new(COUNT)
    Inspector.enable(st, true)
    Inspector.run(st)
    local h = st.hart
    Inspector.pause(st)
    Inspector.edit(st, "this is not assembly !!!\n")
    Inspector.run(st)
    assert.are.equal("error", st.mode)
    assert.is_truthy(st.status:find("assemble error"))
    assert.are.equal(h, st.hart) -- untouched on failure
  end)
end)

describe("Inspector register view-model", function()
  local Hart = require("hart")
  local Mem = require("mem")

  it("labels x0..x31 by ABI + number, then pc and CSRs, in hex", function()
    local h = Hart.new(Mem.new())
    h.x[10] = 0x2a -- a0 = 42
    h.pc = 0x80000004
    h.csr[0x342] = 7 -- mcause
    local r = Inspector.registers(h)
    assert.are.same({ label = "zero (x0)", value = "0x00000000" }, r[1]) -- x0 constant
    assert.are.same({ label = "a0 (x10)", value = "0x0000002a" }, r[11])
    assert.are.same({ label = "pc", value = "0x80000004" }, r[33])
    assert.are.same({ label = "mcause", value = "0x00000007" }, r[37])
  end)
end)

describe("Inspector memory view-model", function()
  local Hart = require("hart")
  local Mem = require("mem")

  it("windows n word rows from base; unwritten reads 0", function()
    local mem = Mem.new()
    mem:w32(0x80000000, 0xdeadbeef)
    mem:w32(0x80000008, 0x2a)
    local w = Inspector.memory_window(mem, 0x80000000, 4)
    assert.are.same({ addr = "0x80000000", value = "0xdeadbeef" }, w[1])
    assert.are.same({ addr = "0x80000004", value = "0x00000000" }, w[2]) -- unwritten
    assert.are.same({ addr = "0x80000008", value = "0x0000002a" }, w[3])
    assert.are.same({ addr = "0x8000000c", value = "0x00000000" }, w[4])
  end)

  it("resolves region presets to base addresses", function()
    local h = Hart.new(Mem.new())
    h.x[2] = 0x90000000 -- sp
    h.pc = 0x80000010
    assert.are.equal(0x80000000, Inspector.region_base(h, "program"))
    assert.are.equal(0x10000000, Inspector.region_base(h, "io"))
    assert.are.equal(0x90000000, Inspector.region_base(h, "stack"))
    assert.are.equal(0x80000010, Inspector.region_base(h, "pc"))
  end)
end)

describe("Inspector changed-cell diff", function()
  it("flags only value changes; baseline and no-change flash nothing", function()
    local prev = { { label = "a", value = "0x1" }, { label = "b", value = "0x2" } }
    local cur = { { label = "a", value = "0x1" }, { label = "b", value = "0x9" } }
    assert.are.same({ [2] = true }, Inspector.diff(prev, cur)) -- only b changed
    assert.are.same({}, Inspector.diff(nil, cur)) -- baseline: nothing
    assert.are.same({}, Inspector.diff(cur, cur)) -- identical: nothing
  end)
end)
