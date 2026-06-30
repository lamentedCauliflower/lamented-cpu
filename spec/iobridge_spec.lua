-- lib/iobridge: the engine-facing half of Circuit I/O, driven here with a fake
-- entity. The real-wire path is the in-game black-box test (instrument-control.lua);
-- this pins the read/write logic fast, without the engine.
local iobridge = require("iobridge")
local SignalMap = require("signalmap")

describe("iobridge.read_input", function()
  it("maps each input signal to its Signal-map id, per colour", function()
    local red = defines.wire_connector_id.combinator_input_red
    local entity = {
      valid = true,
      get_circuit_network = function(connector)
        if connector == red then
          return { signals = { { signal = { type = "item", name = "iron-plate" }, count = 7 } } }
        end
        return nil -- green: nothing wired
      end,
    }
    local sm = SignalMap.new()
    local input = iobridge.read_input(entity, sm)
    local id = sm:lookup_or_alloc("item", "iron-plate") -- the id read_input allocated
    assert.are.equal(7, input.red[id])
    assert.are.same({}, input.green)
  end)
end)

describe("iobridge.write_output", function()
  it("writes the committed set as constant-combinator filters", function()
    local section = {}
    local outproxy = {
      valid = true,
      get_or_create_control_behavior = function()
        return {
          get_section = function()
            return nil
          end,
          add_section = function()
            return section
          end,
        }
      end,
    }
    iobridge.write_output(outproxy, { { type = "item", name = "copper-plate", value = 42 } })
    assert.are.equal(1, #section.filters)
    assert.are.equal("copper-plate", section.filters[1].value.name)
    assert.are.equal(42, section.filters[1].min)
  end)

  it("is a no-op on a missing or invalid output combinator", function()
    assert.has_no.errors(function()
      iobridge.write_output(nil, { { type = "item", name = "x", value = 1 } })
      iobridge.write_output({ valid = false }, {})
    end)
  end)
end)
