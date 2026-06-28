-- Control stage: bind the pure Hart core + Assembler to the in-world entity.
-- This file holds NO ISA logic (ADR-0001): it owns one Hart per placed
-- riscv-combinator, drives it one instruction per tick, and surfaces a GUI that
-- assembles player-written RISC-V assembly into a program image.
local asm = require("lib.asm")
local Hart = require("lib.hart")
local Mem = require("lib.mem")
local iocontroller = require("lib.iocontroller")
local SignalMap = require("lib.signalmap")

local NAME = "riscv-combinator"
local OUT = NAME .. "-output"
local GUI = "riscv-combinator-gui"

local DEFAULT_SRC = [[
# Sums 1..10 into a0, then halts (writes tohost via the test env's ecall path).
# Edit freely -- this is full RV32IM assembly.
_start:
  li   a0, 0
  li   t0, 1
  li   t1, 10
loop:
  add  a0, a0, t0
  addi t0, t0, 1
  ble  t0, t1, loop
  # signal done: store a0 to tohost so the runner reports "halted"
  la   t2, tohost
  sw   a0, 0(t2)
1:
  j    1b

.section .data
.align 6
.global tohost
tohost: .dword 0
]]

-- storage.cpus[unit_number] = { entity, source, status, running, hart, outproxy }
-- storage.viewing[player_index] = unit_number (which cpu's GUI is open)
-- storage.signalmap = the per-save Signal map (ADR-0006), shared by the Assembler
--   resolver and the Commit reverse lookup.

local function ensure_tables()
  storage.cpus = storage.cpus or {}
  storage.viewing = storage.viewing or {}
  storage.signalmap = storage.signalmap or SignalMap.new()
end

-- Save/load strips metatables; the core objects are plain state, so reattach the
-- Hart, Mem and Signal-map method tables to every persisted object.
local function bind_hart(h)
  setmetatable(h, Hart)
  setmetatable(h.mem, Mem)
end

script.on_init(function()
  ensure_tables()
end)

script.on_configuration_changed(function()
  ensure_tables()
end)

script.on_load(function()
  if storage.signalmap then
    setmetatable(storage.signalmap, SignalMap)
  end
  if storage.cpus then
    for _, cpu in pairs(storage.cpus) do
      if cpu.hart then
        bind_hart(cpu.hart)
      end
    end
  end
end)

----------------------------------------------------------------- circuit I/O glue
-- The pure controller (lib/iocontroller) does all the merge/snapshot/staging work;
-- these adapters are the only Factorio-touching part: read the real input network
-- into plain red/green {id=value} tables, and write the committed set onto the
-- hidden output combinator. ponytail: exercised in busted via a fake bridge (the
-- controller is pure); the live wire reads/writes are verified in-game, not by the
-- headless load-smoke, which only proves the prototypes and this file load.
local function read_input(cpu)
  local e = cpu.entity
  local function net(connector)
    local t = {}
    local cn = e.valid and e.get_circuit_network(connector)
    for _, s in pairs((cn and cn.signals) or {}) do
      local id = storage.signalmap:lookup_or_alloc(s.signal.type or "item", s.signal.name)
      t[id] = s.count
    end
    return t
  end
  return {
    red = net(defines.wire_connector_id.combinator_input_red),
    green = net(defines.wire_connector_id.combinator_input_green),
  }
end

-- Write the committed set onto the hidden output combinator in one assignment, so
-- the flush is atomic and latches until the next Commit. The set is already
-- resolved (type/name per entry) and unmapped ids were dropped by the controller.
local function write_output(cpu, set)
  local out = cpu.outproxy
  if not (out and out.valid) then
    return
  end
  local cb = out.get_or_create_control_behavior()
  local section = cb.get_section(1) or cb.add_section()
  local filters = {}
  for _, s in ipairs(set) do
    filters[#filters + 1] = {
      value = {
        type = (s.type == "virtual-signal") and "virtual" or s.type,
        name = s.name,
        quality = "normal",
        comparator = "=",
      },
      min = s.value,
    }
  end
  section.filters = filters
end

-- Service one doorbell between Hart steps (one instr/tick): Sample reads the live
-- wires into the snapshot; Commit drains staging onto the output combinator.
local function service_io(cpu)
  local d = cpu.hart.doorbell
  if not d then
    return
  end
  cpu.hart.doorbell = nil
  if d.off == iocontroller.SAMPLE then
    iocontroller.sample(cpu.hart.mem, read_input(cpu), d.value)
  elseif d.off == iocontroller.COMMIT then
    write_output(cpu, iocontroller.commit(cpu.hart.mem, storage.signalmap))
  end
end

----------------------------------------------------------------- entity lifecycle
-- Place the hidden output combinator on top of the entity and wire it to the
-- entity's output side, so its committed signals appear on the output wire only.
local function make_outproxy(e)
  local out = e.surface.create_entity({
    name = OUT,
    position = e.position,
    force = e.force,
    create_build_effect_smoke = false,
  })
  if not out then
    return nil
  end
  out.destructible = false
  local function wire(from, to)
    e.get_wire_connector(from, true).connect_to(out.get_wire_connector(to, true))
  end
  wire(defines.wire_connector_id.combinator_output_red, defines.wire_connector_id.circuit_red)
  wire(defines.wire_connector_id.combinator_output_green, defines.wire_connector_id.circuit_green)
  return out
end

local function on_built(event)
  local e = event.entity or event.created_entity
  if not (e and e.valid and e.name == NAME) then
    return
  end
  ensure_tables()
  storage.cpus[e.unit_number] = {
    entity = e,
    outproxy = make_outproxy(e),
    source = DEFAULT_SRC,
    status = "idle",
    running = false,
  }
end

local function on_removed(event)
  local e = event.entity
  if e and e.unit_number and storage.cpus then
    local cpu = storage.cpus[e.unit_number]
    if cpu and cpu.outproxy and cpu.outproxy.valid then
      cpu.outproxy.destroy()
    end
    storage.cpus[e.unit_number] = nil
  end
end

local built = {
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
}
for _, ev in pairs(built) do
  script.on_event(ev, on_built, { { filter = "name", name = NAME } })
end
local removed = {
  defines.events.on_player_mined_entity,
  defines.events.on_robot_mined_entity,
  defines.events.on_entity_died,
  defines.events.script_raised_destroy,
}
for _, ev in pairs(removed) do
  script.on_event(ev, on_removed, { { filter = "name", name = NAME } })
end

------------------------------------------------------------------------------ gui
local function refresh_status(unit)
  local cpu = storage.cpus[unit]
  if not cpu then
    return
  end
  for pidx, u in pairs(storage.viewing) do
    if u == unit then
      local p = game.get_player(pidx)
      local frame = p and p.gui.screen[GUI]
      if frame and frame.valid then
        frame.status.caption = cpu.status
      end
    end
  end
end

local function open_gui(player, unit, cpu)
  if player.gui.screen[GUI] then
    player.gui.screen[GUI].destroy()
  end
  local frame = player.gui.screen.add({
    type = "frame",
    name = GUI,
    direction = "vertical",
    caption = "RISC-V Combinator",
  })
  frame.auto_center = true
  local box = frame.add({ type = "text-box", name = "source", text = cpu.source or "" })
  box.style.width = 520
  box.style.height = 360
  local row = frame.add({ type = "flow", name = "buttons", direction = "horizontal" })
  row.add({ type = "button", name = "riscv_run", caption = "Assemble & Run" })
  row.add({ type = "button", name = "riscv_stop", caption = "Stop" })
  frame.add({ type = "label", name = "status", caption = cpu.status or "" })
  storage.viewing[player.index] = unit
  player.opened = frame
end

script.on_event(defines.events.on_gui_opened, function(event)
  local e = event.entity
  if not (e and e.valid and e.name == NAME) then
    return
  end
  ensure_tables()
  local cpu = storage.cpus[e.unit_number]
  if cpu then
    open_gui(game.get_player(event.player_index), e.unit_number, cpu)
  end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  if event.element and event.element.valid and event.element.name == GUI then
    storage.viewing[event.player_index] = nil
    event.element.destroy()
  end
end)

script.on_event(defines.events.on_gui_click, function(event)
  local el = event.element
  if not (el and el.valid and (el.name == "riscv_run" or el.name == "riscv_stop")) then
    return
  end
  local unit = storage.viewing[event.player_index]
  local cpu = unit and storage.cpus[unit]
  if not cpu then
    return
  end
  local frame = game.get_player(event.player_index).gui.screen[GUI]
  if el.name == "riscv_run" then
    cpu.source = frame.source.text
    local resolver = function(typ, name)
      return storage.signalmap:lookup_or_alloc(typ, name)
    end
    local ok, image = pcall(asm.assemble, cpu.source, resolver)
    if not ok then
      cpu.running = false
      cpu.status = "assemble error: " .. tostring(image)
    else
      local h = Hart.new(Mem.new())
      h.io_base = iocontroller.BASE
      h:load(image)
      cpu.hart = h
      cpu.running = true
      cpu.status = "running"
      write_output(cpu, {}) -- Assemble & Run resets the output to a clean slate
    end
  else -- riscv_stop
    cpu.running = false
    cpu.status = "stopped"
  end
  frame.status.caption = cpu.status
end)

--------------------------------------------------------------- one instr per tick
script.on_event(defines.events.on_tick, function()
  if not storage.cpus then
    return
  end
  for unit, cpu in pairs(storage.cpus) do
    if cpu.running and cpu.hart then
      local ok, err = pcall(cpu.hart.step, cpu.hart)
      if ok and cpu.hart.doorbell then
        ok, err = pcall(service_io, cpu) -- Sample reads wires / Commit drives output
      end
      if not ok then
        cpu.running = false
        cpu.status = "runtime error: " .. tostring(err)
        refresh_status(unit)
      elseif cpu.hart.tohost ~= nil then
        cpu.running = false
        local th = cpu.hart.tohost
        cpu.status = (th == 1) and "halted: pass" or ("halted: tohost=0x%08x"):format(th)
        refresh_status(unit)
      end
    end
  end
end)
