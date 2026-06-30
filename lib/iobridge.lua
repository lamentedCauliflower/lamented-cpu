-- Circuit-network bridge: the only Factorio-touching half of Circuit I/O. The pure
-- controller (lib/iocontroller) does the merge/snapshot/staging; this reads the live
-- input wires into plain {id=value} tables and writes a committed set onto a hidden
-- output combinator. Kept out of control.lua so it can be driven by a real placed
-- entity in the in-game black-box test (instrument-control.lua) and mocked in busted.
local M = {}

-- Read the entity's input network into { red = {id=value}, green = {id=value} }, each
-- signal mapped to its append-only Signal-map id (ADR-0006). A disconnected colour is
-- an empty table.
function M.read_input(entity, signalmap)
  local function net(connector)
    local t = {}
    local cn = entity.valid and entity.get_circuit_network(connector)
    for _, s in pairs((cn and cn.signals) or {}) do
      local id = signalmap:lookup_or_alloc(s.signal.type or "item", s.signal.name)
      t[id] = s.count
    end
    return t
  end
  return {
    red = net(defines.wire_connector_id.combinator_input_red),
    green = net(defines.wire_connector_id.combinator_input_green),
  }
end

-- Write the committed set onto the hidden output combinator in one assignment, so the
-- flush is atomic and latches until the next Commit. The set is already resolved
-- (type/name per entry) with unmapped ids dropped by the controller.
function M.write_output(outproxy, set)
  if not (outproxy and outproxy.valid) then
    return
  end
  local cb = outproxy.get_or_create_control_behavior()
  local section = cb.get_section(1) or cb.add_section()
  local filters = {}
  for _, s in ipairs(set) do
    filters[#filters + 1] = {
      value = { type = s.type, name = s.name, quality = "normal", comparator = "=" },
      min = s.value,
    }
  end
  section.filters = filters
end

return M
