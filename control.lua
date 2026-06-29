-- Control stage: bind the pure Hart core + Assembler to the in-world entity.
-- This file holds NO ISA logic (ADR-0001): it owns one Hart per placed
-- riscv-combinator, drives it one instruction per tick, and surfaces a GUI that
-- assembles player-written RISC-V assembly into a program image.
local Hart = require("lib.hart")
local Mem = require("lib.mem")
local iocontroller = require("lib.iocontroller")
local SignalMap = require("lib.signalmap")
local Inspector = require("lib.inspector")

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

-- storage.cpus[unit_number] = an Inspector state table (lib/inspector) plus the
--   engine handles entity + outproxy. The Inspector functions read/write the state
--   fields (enabled, mode, dirty, source, status, hart, lines); the adapter owns
--   entity/outproxy.
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
    -- s.type is already a SignalID type ("item"/"fluid"/"virtual"): the resolver
    -- normalises virtual-signal->virtual and the input path uses Factorio's type.
    filters[#filters + 1] = {
      value = { type = s.type, name = s.name, quality = "normal", comparator = "=" },
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
  local cpu = Inspector.new(DEFAULT_SRC)
  cpu.entity = e
  cpu.outproxy = make_outproxy(e)
  storage.cpus[e.unit_number] = cpu
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
-- The Inspector window: three columns -- registers | control panel | memory. This
-- slice (#17) is the walking skeleton: the side columns are placeholders (#18 fills
-- registers, #19 memory). The centre is the live control panel -- transport + master
-- enable + the source editor with a line-number gutter marking the executing line.
local function resolver()
  return function(typ, name)
    return storage.signalmap:lookup_or_alloc(typ, name)
  end
end

-- gutter text: one line number per source line, the current PC's line marked ">".
-- ponytail: a single label tracks the text-box only if both share a fixed line
-- height; add an fcpu-style monospace text-box style in data.lua and scroll_to the
-- marked line for autoscroll when tuning in-engine (verifiable only in the client).
local function gutter_text(cpu)
  local cur = Inspector.current_line(cpu)
  local out, i = {}, 0
  for _ in (cpu.source .. "\n"):gmatch("(.-)\n") do
    i = i + 1
    out[i] = (i == cur) and (i .. ">") or tostring(i)
  end
  return table.concat(out, "\n")
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
  local body = frame.add({ type = "flow", name = "body", direction = "horizontal" })

  -- left: register viewer placeholder (Inspector 3/5)
  local left = body.add({
    type = "frame",
    name = "left",
    style = "inside_shallow_frame",
    direction = "vertical",
  })
  left.add({ type = "label", caption = "Registers" })

  -- centre: control panel
  local center = body.add({
    type = "frame",
    name = "center",
    style = "inside_shallow_frame",
    direction = "vertical",
  })
  local transport = center.add({ type = "flow", name = "transport", direction = "horizontal" })
  transport.add({ type = "button", name = "riscv_run", caption = "Run" })
  transport.add({ type = "button", name = "riscv_pause", caption = "Pause" })
  transport.add({ type = "button", name = "riscv_step", caption = "Step" })
  transport.add({
    type = "switch",
    name = "riscv_enable",
    left_label_caption = "Off",
    right_label_caption = "On",
    switch_state = cpu.enabled and "right" or "left",
  })
  center.add({ type = "label", caption = "Commands" })
  local code = center.add({ type = "flow", name = "code", direction = "horizontal" })
  code.add({ type = "label", name = "gutter", caption = gutter_text(cpu) })
  local box = code.add({ type = "text-box", name = "source", text = cpu.source or "" })
  box.read_only = (cpu.mode == "running")
  box.style.width = 480
  box.style.height = 360
  center.add({ type = "label", name = "status", caption = cpu.status or "" })

  -- right: memory browser placeholder (Inspector 4/5)
  local right = body.add({
    type = "frame",
    name = "right",
    style = "inside_shallow_frame",
    direction = "vertical",
  })
  right.add({ type = "label", caption = "Mem. Browser" })

  storage.viewing[player.index] = unit
  player.opened = frame
end

-- push live state into every open view of this unit: gutter marker, read-only,
-- status, switch. Never writes the source text (would fight the typist).
local function refresh(unit)
  local cpu = storage.cpus[unit]
  if not cpu then
    return
  end
  for pidx, u in pairs(storage.viewing) do
    if u == unit then
      local p = game.get_player(pidx)
      local frame = p and p.gui.screen[GUI]
      if frame and frame.valid then
        local c = frame.body.center
        c.code.gutter.caption = gutter_text(cpu)
        c.code.source.read_only = (cpu.mode == "running")
        c.status.caption = cpu.status
        c.transport.riscv_enable.switch_state = cpu.enabled and "right" or "left"
      end
    end
  end
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

-- transport: Run / Pause / Step drive the Inspector core. A run/step that reassembles
-- resets the latched output to a clean slate first (ADR-0005).
script.on_event(defines.events.on_gui_click, function(event)
  local el = event.element
  if not (el and el.valid) then
    return
  end
  local unit = storage.viewing[event.player_index]
  local cpu = unit and storage.cpus[unit]
  if not cpu then
    return
  end
  local reassembles = not (cpu.mode == "paused" and not cpu.dirty and cpu.hart)
  if el.name == "riscv_run" then
    if reassembles then
      write_output(cpu, {})
    end
    Inspector.run(cpu, resolver())
  elseif el.name == "riscv_step" then
    if reassembles then
      write_output(cpu, {})
    end
    Inspector.step(cpu, resolver())
  elseif el.name == "riscv_pause" then
    Inspector.pause(cpu)
  else
    return
  end
  refresh(unit)
end)

script.on_event(defines.events.on_gui_switch_state_changed, function(event)
  local el = event.element
  if not (el and el.valid and el.name == "riscv_enable") then
    return
  end
  local unit = storage.viewing[event.player_index]
  local cpu = unit and storage.cpus[unit]
  if cpu then
    Inspector.enable(cpu, el.switch_state == "right")
    refresh(unit)
  end
end)

script.on_event(defines.events.on_gui_text_changed, function(event)
  local el = event.element
  if not (el and el.valid and el.name == "source") then
    return
  end
  local unit = storage.viewing[event.player_index]
  local cpu = unit and storage.cpus[unit]
  if cpu then
    Inspector.edit(cpu, el.text)
    refresh(unit)
  end
end)

--------------------------------------------------------------- one instr per tick
script.on_event(defines.events.on_tick, function()
  if not storage.cpus then
    return
  end
  for unit, cpu in pairs(storage.cpus) do
    if cpu.enabled and cpu.mode == "running" and cpu.hart then
      Inspector.tick(cpu)
      if cpu.hart.doorbell then
        local ok, err = pcall(service_io, cpu) -- Sample reads wires / Commit drives output
        if not ok then
          cpu.mode, cpu.status = "error", "io error: " .. tostring(err)
        end
      end
      refresh(unit) -- ponytail: refresh every running tick; #20 throttles to ~10 Hz
    end
  end
end)
