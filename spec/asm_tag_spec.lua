-- Assembler rich-text tag hardening (#14): accept item/fluid/virtual-signal,
-- map virtual-signal -> SignalID type virtual, reject other types and a quality
-- clause, and make a resolved tag a plain integer usable in any expression. Pure
-- assembler, no engine.
local asm = require("asm")

-- resolver stub: returns a fixed id and records the (type, name) it was handed.
local function stub(id)
  local calls = {}
  return function(typ, name)
    calls[#calls + 1] = { typ, name }
    return id or 7
  end, calls
end

describe("assembler rich-text tags", function()
  it("resolves item / fluid / virtual-signal via the injected resolver", function()
    local r, calls = stub()
    local out =
      asm.resolve_tags("a [item=iron-plate] b [fluid=water] c [virtual-signal=signal-A]", r)
    assert.are.equal("a 7 b 7 c 7", out)
    assert.are.same(
      { { "item", "iron-plate" }, { "fluid", "water" }, { "virtual", "signal-A" } },
      calls
    )
  end)

  it("maps virtual-signal to SignalID type virtual", function()
    local r, calls = stub()
    asm.resolve_tags("[virtual-signal=signal-D]", r)
    assert.are.same({ { "virtual", "signal-D" } }, calls)
  end)

  it("rejects other 2.0 signal types with a clear error", function()
    local r = stub()
    for _, t in ipairs({ "recipe", "entity", "space-location", "asteroid-chunk", "quality" }) do
      assert.has_error(function()
        asm.resolve_tags("[" .. t .. "=x]", r)
      end)
    end
  end)

  it("rejects a quality clause", function()
    local r = stub()
    assert.has_error(function()
      asm.resolve_tags("[item=iron-plate,quality=uncommon]", r)
    end)
  end)

  it("a resolved tag is a plain integer usable in any expression position", function()
    local r = stub(5) -- every tag -> 5
    local image =
      asm.assemble("li a0, [item=copper-plate] + 1\n.word [virtual-signal=signal-A]\n", r)
    -- li a0, 6  ->  addi a0, x0, 6  (fits in 12 bits, single instruction)
    assert.are.equal(0x00600513, image.words[0x80000000])
    -- .word 5 emitted little-endian at the next address
    assert.are.equal(5, image.bytes[0x80000004])
    assert.are.equal(0, image.bytes[0x80000005])
  end)

  it("a tag resolves inside a branch comparison target expression", function()
    local r = stub(0) -- signal id 0
    -- beq a0, x0, _start + [virtual-signal=signal-A]  -> offset folds with the id
    local image = asm.assemble("_start:\n  beq a0, zero, _start + [virtual-signal=signal-A]\n", r)
    assert.is_truthy(image.words[0x80000000]) -- assembled without error
  end)
end)
