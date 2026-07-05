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

-- Vector stores vs the controller (#41): an element store landing in the
-- watched trigger-register window (STATUS/SAMPLE/COMMIT/reserved, BASE+0x00..
-- 0x0F) must trap with the store access-fault cause instead of recording a
-- doorbell; the data regions (Query, Snapshot, Staging) stay plain memory for
-- vector access. Reachable in-game only: io_base is nil under conformance.
describe("vector stores and the controller window", function()
  -- assemble with the controller armed and run to the end of the listing (a
  -- trap redirects to mtvec=0, which is outside it, so a fault also stops)
  local function armed_run(src)
    local image = asm.assemble(src)
    local hart = Hart.new(Mem.new())
    hart.io_base = io.BASE
    hart:load(image)
    for _ = 1, 100 do
      if not image.words[hart.pc] then
        break
      end
      hart:step()
    end
    return hart, image
  end

  it("a vse32 into the trigger window traps, no doorbell", function()
    local hart = armed_run([[
      li t0, 0x10000000
      vsetvli t1, x0, e32, m1, tu, mu
      vmv.v.i v1, 1
      vse32.v v1, (t0)      # spans STATUS..COMMIT: element store must fault
    ]])
    assert.are.equal(7, hart.csr[0x342]) -- mcause: store/AMO access fault
    assert.are.equal(0x10000000, hart.csr[0x343]) -- mtval: faulting address
    assert.is_nil(hart.doorbell)
  end)

  it("a masked vse8 whose only active element hits the window also traps", function()
    local hart = armed_run([[
      li t0, 0x10000004     # SAMPLE
      li t2, 0x100          # mask: only element 8 active -> address t0+8
      vsetvli t1, x0, e8, m1, tu, mu
      vmv.v.i v1, 3
      vsetvli t1, x0, e32, m1, tu, mu
      vmv.v.x v0, t2        # low word of v0 = 0x100: element 8 only
      vsetvli t1, x0, e8, m1, tu, mu
      vse8.v v1, (t0), v0.t
    ]])
    assert.are.equal(7, hart.csr[0x342])
    assert.are.equal(0x1000000c, hart.csr[0x343]) -- SAMPLE+8 = BASE+0xC
    assert.is_nil(hart.doorbell)
  end)

  it("vector loads over the window never fault, and data regions are plain memory", function()
    local hart, image = armed_run([[
      li s0, 0x10000800     # STAGING
      la a0, vals
      vsetvli t1, x0, e32, m1, tu, mu
      vle32.v v1, (a0)
      vse32.v v1, (s0)      # bulk staging fill: the intended fast path
      li t0, 0x10000000
      vle32.v v2, (t0)      # loads over the trigger window are fine
      la a1, out
      vse32.v v2, (a1)
    vals: .word 5, 6, 7, 8
    out:  .word 0, 0, 0, 0
    ]])
    assert.are.equal(0, hart.csr[0x342] or 0) -- no trap
    assert.is_nil(hart.doorbell) -- data-region stores ring nothing
    assert.are.equal(5, hart.mem:r32(0x10000800))
    assert.are.equal(8, hart.mem:r32(0x1000080c))
    assert.are.equal(0, hart.mem:r32(image.symbols.out)) -- window reads as 0
  end)

  it("scalar doorbells are unchanged", function()
    local hart = armed_run([[
      li t0, 0x10000000
      li t1, 1
      sw t1, 4(t0)          # SAMPLE: records a doorbell, no trap
    ]])
    assert.are.equal(0, hart.csr[0x342] or 0)
    assert.are.same({ off = 4, value = 1 }, hart.doorbell)
  end)
end)
