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
  it("starts stopped, dirty, disabled; transport is inert until enabled", function()
    local st = Inspector.new(COUNT)
    assert.are.equal("stopped", st.mode)
    assert.is_true(st.dirty)
    assert.is_false(st.enabled)
    Inspector.run(st) -- disabled => no-op
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
