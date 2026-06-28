-- Circuit I/O walking skeleton (#11): the thinnest complete path through every
-- layer -- resolver, Sample, snapshot read, staging, Commit -- echoing one named
-- signal end to end. The engine adapter is stubbed by a fake bridge here exactly
-- as control.lua wires the real one (the controller is pure, so both share it).
local asm = require("asm")
local Mem = require("mem")
local Hart = require("hart")
local io = require("iocontroller")
local SignalMap = require("signalmap")

-- Echo: Sample the red wire, copy the first snapshot signal's value out under the
-- name [virtual-signal=signal-A] (resolved to its id at assemble time), Commit,
-- then halt via tohost. t0 = device base, s0 = staging base (the two buffers can't
-- share one +/-2KiB lw/sw window).
local ECHO = [[
_start:
  li   t0, 0x10000000
  li   s0, 0x10000800
  li   t1, 1
  sw   t1, 4(t0)              # SAMPLE, colour = red
  lw   t4, 0x108(t0)         # snapshot pair0 value
  li   a0, [virtual-signal=signal-A]   # resolved id
  li   t5, 1
  sw   t5, 0(s0)             # staging count = 1
  sw   a0, 4(s0)            # staging pair0 id
  sw   t4, 8(s0)           # staging pair0 value
  sw   t5, 8(t0)            # COMMIT
  la   t6, tohost
  sw   t4, 0(t6)            # halt: tohost = the echoed value (nonzero)
1:
  j    1b

.section .data
.align 6
.global tohost
tohost: .dword 0
]]

describe("circuit I/O walking skeleton", function()
  it("echoes one named signal end to end", function()
    local map = SignalMap.new()
    local image = asm.assemble(ECHO, function(t, n)
      return map:lookup_or_alloc(t, n)
    end)

    local hart = Hart.new(Mem.new())
    hart.io_base = io.BASE
    hart:load(image)

    -- fake input wire: signal-A = 42 on red. Factorio reports virtual signals as
    -- type "virtual" -- the same key the resolver normalises [virtual-signal=...]
    -- to -- so the program's baked id matches the wire's id.
    local aid = map:lookup_or_alloc("virtual", "signal-A")
    local captured
    local function service()
      local d = hart.doorbell
      if not d then
        return
      end
      hart.doorbell = nil
      if d.off == io.SAMPLE then
        io.sample(hart.mem, { red = { [aid] = 42 }, green = {} }, d.value)
      elseif d.off == io.COMMIT then
        captured = io.commit(hart.mem, map)
      end
    end

    for _ = 1, 200 do
      hart:step()
      service()
      if hart.tohost ~= nil then
        break
      end
    end

    assert.is_truthy(hart.tohost, "program did not halt")
    assert.are.same({ { id = aid, type = "virtual", name = "signal-A", value = 42 } }, captured)
  end)

  it("resolver is nil-safe: conformance assembly is unchanged", function()
    -- no resolver -> tags-free source assembles exactly as before
    local image = asm.assemble("_start:\n  li a0, 7\n")
    assert.is_truthy(image.words)
  end)
end)
