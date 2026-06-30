-- Control stage: bind the pure Hart core + Assembler to the in-world entity.
-- This file holds NO ISA logic (ADR-0001): it owns one Hart per placed
-- riscv-combinator, drives it one instruction per tick, and surfaces a GUI that
-- assembles player-written RISC-V assembly into a program image.
local Hart = require("lib.hart")
local Mem = require("lib.mem")
local iocontroller = require("lib.iocontroller")
local iobridge = require("lib.iobridge")
local SignalMap = require("lib.signalmap")
local Inspector = require("lib.inspector")
local Manual = require("lib.manual")

-- The Manual (ADR-0008): expose the Informatron client interface now, at load time
-- (remote.add_interface and require are both load-only). No-op if Informatron is
-- not installed.
Manual.register_informatron(require("lib.manual.content"))

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
-- The pure controller (lib/iocontroller) does the merge/snapshot/staging; the engine-
-- touching reads/writes live in lib/iobridge so they can be driven by a real placed
-- entity in the in-game black-box test (instrument-control.lua) and mocked in busted.
-- The live wire reads/writes are verified there, not by the headless load-smoke.

-- Service one doorbell between Hart steps (one instr/tick): Sample reads the live
-- wires into the snapshot; Commit drains staging onto the output combinator.
local function service_io(cpu)
  local d = cpu.hart.doorbell
  if not d then
    return
  end
  cpu.hart.doorbell = nil
  if d.off == iocontroller.SAMPLE then
    iocontroller.sample(cpu.hart.mem, iobridge.read_input(cpu.entity, storage.signalmap), d.value)
  elseif d.off == iocontroller.COMMIT then
    iobridge.write_output(cpu.outproxy, iocontroller.commit(cpu.hart.mem, storage.signalmap))
  end
end

-- Drain a doorbell after a Hart step in ANY transport mode. Run calls this each tick;
-- Step calls it too, so a Sample/Commit issued by a single stepped instruction still
-- reaches the wires (otherwise stepping the I/O example never samples). I/O faults park
-- the cpu in error.
local function service_doorbell(cpu)
  if cpu.hart and cpu.hart.doorbell then
    local ok, err = pcall(service_io, cpu)
    if not ok then
      cpu.mode, cpu.status = "error", "io error: " .. tostring(err)
    end
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

-- Automation/test seam: drive a combinator's Hart by unit_number without the GUI, so
-- an external caller (the in-game black-box test, or any automation mod) can load a
-- program and run it, then observe the result purely on the circuit wires. Only acts
-- on a combinator this mod owns; a no-op otherwise.
remote.add_interface("lamented-cpu-debug", {
  -- load `source` into the combinator at `unit` and start running it; returns true if
  -- it assembled and entered the running state.
  load = function(unit, source)
    local cpu = storage.cpus and storage.cpus[unit]
    if not cpu then
      return false
    end
    cpu.source, cpu.dirty = source, true
    Inspector.run(cpu, resolver())
    return cpu.mode == "running"
  end,
  -- inspect the Hart at `unit`: transport mode/status and the register file (x0..x31).
  peek = function(unit)
    local cpu = storage.cpus and storage.cpus[unit]
    if not cpu then
      return nil
    end
    return { mode = cpu.mode, status = cpu.status, x = cpu.hart and cpu.hart.x }
  end,
})

-- fcpu-style gutter: ONE label per source line in a vertical flow beside the text-box
-- (a single multi-line label collapses -- Factorio labels are single-line). The
-- text-box is sized to fit every line so it never scrolls on its own; gutter + box
-- co-scroll inside the shared scroll-pane, so the numbers can't desync. The PC's line
-- gets a coloured marker, and Run auto-scrolls to it.
-- ponytail: LINE_H is the text-box's per-line height in px (fcpu's tuned value for the
-- default UI scale). If the numbers drift from the code in-engine, nudge LINE_H and the
-- gutter top_padding -- only the full client can show the alignment, not the load-smoke.
local LINE_H = 20

local function fill_code(codepane, cpu)
  local editor = codepane.editor
  local gutter, box = editor.gutter, editor.source
  gutter.clear()
  local n = 0
  for _ in (cpu.source .. "\n"):gmatch("(.-)\n") do
    n = n + 1
  end
  local cur = Inspector.current_line(cpu)
  for i = 1, n do
    local cap = (i == cur) and ("[color=80,160,255]" .. i .. "▶[/color]") or tostring(i)
    local lbl = gutter.add({ type = "label", name = "g" .. i, caption = cap })
    lbl.style.height = LINE_H
    lbl.style.width = 40
    lbl.style.horizontal_align = "right"
  end
  box.read_only = (cpu.mode == "running")
  box.style.height = math.max(LINE_H + 8, n * LINE_H + 8) -- fit all lines: no inner scroll
  if cpu.mode == "running" and cur and gutter["g" .. cur] then
    codepane.scroll_to_element(gutter["g" .. cur], "top-third")
  end
end

-- render the register rows into the left scroll-pane (#18). ponytail: clear+rebuild
-- each refresh -- fine for open GUIs at the #20 throttle; switch to in-place caption
-- updates if it churns. Monospace/right-align is a style ceiling; hex is fixed-width.
-- a changed value is highlighted for this refresh ("flash = changed since last
-- refresh"). ponytail: a static recolour, not a timed fade -- a fade would need an
-- on_tick style tween; the recolour reads fine at the ~10 Hz run cadence.
local HL = "[color=255,230,120]"
local function valcap(value, hot)
  return hot and (HL .. value .. "[/color]") or value
end

local function fill_registers(pane, cpu)
  pane.clear()
  if not cpu.hart then
    pane.add({ type = "label", caption = "(not assembled)" })
    return
  end
  local rows = Inspector.registers(cpu.hart)
  local changed = Inspector.diff(cpu.prev_regs, rows)
  cpu.prev_regs = rows
  local t = pane.add({ type = "table", name = "t", column_count = 2 })
  for i, row in ipairs(rows) do
    t.add({ type = "label", caption = row.label })
    t.add({ type = "label", caption = valcap(row.value, changed[i]) })
  end
end

local MEM_ROWS = 16 -- ponytail: the fixed window IS the virtualization (Factorio has none)

local function fill_memory(pane, cpu)
  pane.clear()
  if not cpu.hart then
    pane.add({ type = "label", caption = "(not assembled)" })
    return
  end
  local base = cpu.mem_base or 0x80000000
  local rows = Inspector.memory_window(cpu.hart.mem, base, MEM_ROWS)
  local changed = Inspector.diff(cpu.prev_mem, rows)
  cpu.prev_mem = rows
  local t = pane.add({ type = "table", name = "t", column_count = 2 })
  for i, row in ipairs(rows) do
    t.add({ type = "label", caption = row.addr })
    t.add({ type = "label", caption = valcap(row.value, changed[i]) })
  end
end

-- The Pause button doubles as Stop: while paused, pressing it resets to stopped
-- (the next Run reassembles) instead of pausing an already-paused Hart.
local function pause_caption(cpu)
  return cpu.mode == "paused" and "Stop" or "Pause"
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

  -- left: register viewer (Inspector 3/5)
  local left = body.add({
    type = "frame",
    name = "left",
    style = "inside_shallow_frame",
    direction = "vertical",
  })
  left.style.padding = 8
  local rhead = left.add({ type = "table", column_count = 2 })
  rhead.add({ type = "label", caption = "Register" })
  rhead.add({ type = "label", caption = "Value" })
  local regs = left.add({ type = "scroll-pane", name = "regs" })
  regs.style.maximal_height = 360
  fill_registers(regs, cpu)

  -- centre: control panel
  local center = body.add({
    type = "frame",
    name = "center",
    style = "inside_shallow_frame",
    direction = "vertical",
  })
  center.style.padding = 8
  local transport = center.add({ type = "flow", name = "transport", direction = "horizontal" })
  transport.add({ type = "button", name = "riscv_run", caption = "Run" })
  transport.add({ type = "button", name = "riscv_pause", caption = pause_caption(cpu) })
  transport.add({ type = "button", name = "riscv_step", caption = "Step" })
  transport.add({
    type = "switch",
    name = "riscv_enable",
    left_label_caption = "Off",
    right_label_caption = "On",
    switch_state = cpu.enabled and "right" or "left",
  })
  -- Manual button (#29): only when a doc-mod backend is installed to open into.
  if Manual.available() then
    transport.add({ type = "button", name = "riscv_manual", caption = "Manual" })
  end
  center.add({ type = "label", caption = "Commands" })
  local codepane = center.add({ type = "scroll-pane", name = "codepane" })
  codepane.style.maximal_height = 360
  codepane.style.width = 540
  local editor = codepane.add({ type = "flow", name = "editor", direction = "horizontal" })
  local gutter = editor.add({ type = "flow", name = "gutter", direction = "vertical" })
  gutter.style.vertical_spacing = 0
  gutter.style.top_padding = 4
  local box = editor.add({ type = "text-box", name = "source", text = cpu.source or "" })
  box.word_wrap = false
  box.style.width = 480
  fill_code(codepane, cpu)
  center.add({ type = "label", name = "status", caption = cpu.status or "" })

  -- right: memory browser (Inspector 4/5)
  local right = body.add({
    type = "frame",
    name = "right",
    style = "inside_shallow_frame",
    direction = "vertical",
  })
  right.style.padding = 8
  local nav = right.add({ type = "flow", name = "nav", direction = "horizontal" })
  nav.add({
    type = "drop-down",
    name = "riscv_region",
    items = { "Program", "I/O", "Stack", "PC" },
    selected_index = 1,
  })
  nav.add({ type = "textfield", name = "riscv_addr" })
  nav.add({ type = "button", name = "riscv_memup", caption = "Up" })
  nav.add({ type = "button", name = "riscv_memdn", caption = "Down" })
  local mhead = right.add({ type = "table", column_count = 2 })
  mhead.add({ type = "label", caption = "Address" })
  mhead.add({ type = "label", caption = "Val." })
  local mempane = right.add({ type = "scroll-pane", name = "mem" })
  mempane.style.maximal_height = 360
  fill_memory(mempane, cpu)

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
        fill_code(c.codepane, cpu)
        c.status.caption = cpu.status
        c.transport.riscv_enable.switch_state = cpu.enabled and "right" or "left"
        c.transport.riscv_pause.caption = pause_caption(cpu)
        fill_registers(frame.body.left.regs, cpu)
        fill_memory(frame.body.right.mem, cpu)
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
  -- Manual button (#29): open the in-game Manual (Informatron).
  if el.name == "riscv_manual" then
    local player = game.get_player(event.player_index)
    if player then
      Manual.open(player)
    end
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
      iobridge.write_output(cpu.outproxy, {})
      cpu.prev_regs, cpu.prev_mem = nil, nil -- post-reset baseline: no whole-file flash
    end
    Inspector.run(cpu, resolver())
  elseif el.name == "riscv_step" then
    if reassembles then
      iobridge.write_output(cpu.outproxy, {})
      cpu.prev_regs, cpu.prev_mem = nil, nil -- post-reset baseline: no whole-file flash
    end
    Inspector.step(cpu, resolver())
    service_doorbell(cpu) -- a stepped Sample/Commit still reaches the wires
  elseif el.name == "riscv_pause" then
    if cpu.mode == "paused" then
      Inspector.stop(cpu) -- the paused Pause button acts as Stop (reset)
    else
      Inspector.pause(cpu)
    end
  elseif el.name == "riscv_memup" then
    cpu.mem_base = math.max(0, (cpu.mem_base or 0x80000000) - MEM_ROWS * 4)
    cpu.prev_mem = nil
  elseif el.name == "riscv_memdn" then
    cpu.mem_base = (cpu.mem_base or 0x80000000) + MEM_ROWS * 4
    cpu.prev_mem = nil
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

-- memory region preset drop-down: jump the window to program / I/O / stack / pc.
local REGION = { "program", "io", "stack", "pc" }
script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  local el = event.element
  if not (el and el.valid and el.name == "riscv_region") then
    return
  end
  local unit = storage.viewing[event.player_index]
  local cpu = unit and storage.cpus[unit]
  if cpu then
    cpu.mem_base = Inspector.region_base(cpu.hart, REGION[el.selected_index] or "program")
    cpu.prev_mem = nil
    refresh(unit)
  end
end)

script.on_event(defines.events.on_gui_text_changed, function(event)
  local el = event.element
  if not (el and el.valid and (el.name == "source" or el.name == "riscv_addr")) then
    return
  end
  local unit = storage.viewing[event.player_index]
  local cpu = unit and storage.cpus[unit]
  if not cpu then
    return
  end
  if el.name == "source" then
    Inspector.edit(cpu, el.text)
  else -- riscv_addr: jump to a typed hex address (word-aligned); ignore garbage
    local a = tonumber((el.text:gsub("^0[xX]", "")), 16)
    if a then
      cpu.mem_base = a - (a % 4)
      cpu.prev_mem = nil
    end
  end
  refresh(unit)
end)

--------------------------------------------------------------- one instr per tick
script.on_event(defines.events.on_tick, function()
  if not storage.cpus then
    return
  end
  for unit, cpu in pairs(storage.cpus) do
    if cpu.enabled and cpu.mode == "running" and cpu.hart then
      local was = cpu.mode
      Inspector.tick(cpu)
      service_doorbell(cpu) -- Sample reads wires / Commit drives output
      -- ~10 Hz while running; immediate on a mode change (halt/error) so the final
      -- state shows at once. Step/Pause/buttons refresh immediately in their handlers.
      if cpu.mode ~= was or game.tick % 6 == 0 then
        refresh(unit)
      end
    end
  end
end)
