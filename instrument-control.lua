-- In-game test pass. Runs ONLY under `factorio --instrument-mod lamented-cpu`
-- (the modtest gate adds that flag); never in normal play. It covers what the busted
-- suite cannot: the mod's code executing in Factorio's own Lua 5.2 VM, and the live
-- in-world path -- placing a RISC-V Combinator and running a program on its Hart.
-- Any failure calls error(), so the headless run exits non-zero and the gate fails.
local asm = require("lib.asm")
local Hart = require("lib.hart")
local Mem = require("lib.mem")
local io = require("lib.iocontroller")
local SignalMap = require("lib.signalmap")
local Config = require("lib.config")
local content = require("lib.manual.content")

local function fail(msg)
  error("[in-game test] " .. msg, 0)
end
local function check(cond, msg)
  if not cond then
    fail(msg)
  end
end

local function build(src)
  local h = Hart.new(Mem.new())
  h:load(asm.assemble(src))
  return h
end

-- step until a tohost halt, a runtime fault (snippets run off their end), or `max`.
local function drive(h, max, service)
  for _ = 1, max do
    local ok = pcall(h.step, h)
    if service then
      service(h)
    end
    if not ok or h.tohost ~= nil then
      break
    end
  end
end

----------------------------------------------------------- 1) examples in the real VM
-- The same execution checks as spec/manual_examples_spec.lua, but run inside the
-- engine's Lua, proving the Manual's programs behave identically on the real hart.
local function run_example_checks()
  local EX = {}
  for _, ch in ipairs(content) do
    if ch.id == "examples" then
      for _, b in ipairs(ch.blocks) do
        if b.kind == "code" then
          EX[#EX + 1] = b.text
        end
      end
    end
  end
  check(#EX == 4, "expected 4 example programs, got " .. #EX)

  local sum = build(EX[1])
  drive(sum, 100)
  check(sum.x[10] == 55, "sum example: a0 = " .. sum.x[10] .. ", want 55")

  local frame = build(EX[2])
  frame.x[10] = 7
  drive(frame, 100)
  check(frame.x[10] == 14, "frame example: a0 = " .. frame.x[10] .. ", want 14")

  local sm = SignalMap.new()
  local id = sm:lookup_or_alloc("item", "iron-plate")
  local input = { red = { [id] = 21 }, green = {} }
  local committed
  local function service(h)
    local d = h.doorbell
    if not d then
      return
    end
    h.doorbell = nil
    if d.off == io.SAMPLE then
      io.sample(h.mem, input, d.value)
    elseif d.off == io.COMMIT then
      committed = io.commit(h.mem, sm)
    end
  end
  local ioh = build(EX[3])
  ioh.io_base = io.BASE
  drive(ioh, 100, service)
  check(committed and #committed == 1, "io example: nothing committed")
  check(
    committed[1].value == 42,
    "io example: committed " .. tostring(committed[1].value) .. ", want 42"
  )

  local trap = build(EX[4])
  drive(trap, 100)
  check(
    trap.csr[0x342] == 11,
    "trap example: mcause = " .. tostring(trap.csr[0x342]) .. ", want 11"
  )
end

run_example_checks() -- runs at instrument-control parse time, in the engine VM

----------------------------------------------------- 2) the live in-world entity path
-- A halting sum program: a0 = 1+..+10 = 55, then a tohost write stops the Hart.
local HALT_SRC = [[
  li   a0, 0
  li   t0, 1
  li   t1, 10
loop:
  add  a0, a0, t0
  addi t0, t0, 1
  ble  t0, t1, loop
  la   t2, tohost
  sw   a0, 0(t2)
1:
  j    1b
.section .data
.align 6
tohost: .dword 0
]]

local RED_IN = defines.wire_connector_id.combinator_input_red
local RED_OUT = defines.wire_connector_id.combinator_output_red
local CC_RED = defines.wire_connector_id.circuit_red
local DEBUG = "lamented-cpu-debug" -- control.lua's automation remote

-- the Manual's read-compute-commit example (3rd code block of the Examples chapter).
local function io_example_src()
  for _, ch in ipairs(content) do
    if ch.id == "examples" then
      local n = 0
      for _, b in ipairs(ch.blocks) do
        if b.kind == "code" then
          n = n + 1
          if n == 3 then
            return b.text
          end
        end
      end
    end
  end
end

local function set_cc(entity, name, count)
  local cb = entity.get_or_create_control_behavior()
  local sec = cb.get_section(1) or cb.add_section()
  sec.filters = {
    { value = { type = "item", name = name, quality = "normal", comparator = "=" }, min = count },
  }
end

-- place a RISC-V Combinator and fire control.lua's on_built (which registers its Hart).
local function place(surface, center)
  local pos = surface.find_non_colliding_position("riscv-combinator", center, 64, 1) or center
  local e = surface.create_entity({ name = "riscv-combinator", position = pos, force = "player" })
  check(e and e.valid, "could not place a RISC-V Combinator")
  script.raise_script_built({ entity = e })
  return e
end

-- a constant combinator feeding `count` of `name` into the combinator's red input.
local function wire_feeder(surface, e, name, count)
  local at = { e.position.x + 2, e.position.y }
  local fpos = surface.find_non_colliding_position("constant-combinator", at, 64, 1)
  local feeder =
    surface.create_entity({ name = "constant-combinator", position = fpos, force = "player" })
  check(feeder and feeder.valid, "io: could not place feeder combinator")
  set_cc(feeder, name, count)
  feeder.get_wire_connector(CC_RED, true).connect_to(e.get_wire_connector(RED_IN, true))
end

local function out_signal(e, name)
  local cn = e.get_circuit_network(RED_OUT)
  return cn and cn.get_signal({ type = "item", name = name, quality = "normal" })
end

-- a distinct program whose only job is to be recognizable after a blueprint round-trip.
local BP_SRC = "# blueprint-roundtrip-marker\nli a0, 7\n"

-- Blueprint round-trip (black box, ADR-0009 / #21): a RISC-V Combinator built from a
-- blueprint must reassemble the SAME source, start stopped, and get a fresh hidden output
-- combinator. The player-capture handler (on_player_setup_blueprint) cannot fire in a
-- headless run -- no player, and its mapping is an engine-made lazy value -- so the test
-- drives the two halves it CAN reach for real, observing only through the mod's remote +
-- the world:
--   * the tag write the handler relies on: set_blueprint_entity_tags on a real blueprint
--     stack, read back off the blueprint entity;
--   * the build path: a ghost carrying that tag, revived, which fires on_built with
--     event.tags exactly as a robot/hand build of a blueprinted ghost does.
local function run_blueprint_check(surface)
  -- write the config into a real blueprint stack the way the capture handler would, and
  -- confirm it persists on the blueprint entity (the engine hands this back as event.tags).
  local inv = game.create_inventory(1)
  inv[1].set_stack("blueprint")
  inv[1].set_blueprint_entities({
    { entity_number = 1, name = "riscv-combinator", position = { 0, 0 } },
  })
  inv[1].set_blueprint_entity_tags(1, Config.to_tags({ source = BP_SRC, enabled = true }))
  local tags = inv[1].get_blueprint_entities()[1].tags
  inv.destroy()
  check(tags and tags.source == BP_SRC, "bp: set_blueprint_entity_tags did not persist the config")

  -- build a copy: a ghost carrying those tags, revived, fires on_built with event.tags.
  local before = surface.count_entities_filtered({ name = "riscv-combinator-output" })
  local pos = surface.find_non_colliding_position("riscv-combinator", { 40, 0 }, 64, 1)
  local ghost = surface.create_entity({
    name = "entity-ghost",
    inner_name = "riscv-combinator",
    position = pos,
    force = "player",
    tags = tags,
  })
  check(ghost and ghost.valid, "bp: could not create a tagged ghost")
  local _, b = ghost.revive({ raise_revive = true })
  check(b and b.valid and b.name == "riscv-combinator", "bp: ghost did not revive")

  -- the rebuilt copy gets its own fresh hidden output combinator...
  local after = surface.count_entities_filtered({ name = "riscv-combinator-output" })
  check(
    after == before + 1,
    "bp: output combinator not recreated (" .. before .. " -> " .. after .. ")"
  )
  -- ...and the source survived, starting stopped so it reassembles on the next Run.
  local p = remote.call(DEBUG, "peek", b.unit_number)
  check(p and p.source == BP_SRC, "bp: source did not round-trip through the blueprint")
  check(
    p.mode == "stopped",
    "bp: rebuilt copy should start stopped, got " .. tostring(p and p.mode)
  )
end

-- Black box: the test only places entities, wires them, asks the mod (via its
-- automation remote) to load+run a program, and observes the circuit wires / register
-- file. ALL execution -- assemble, step, Sample/Commit, the live wire reads and writes
-- -- happens inside the real mod (control.lua's on_tick + service_io), never
-- reimplemented here. Two combinators run at once:
--   * halt: load on a bare combinator, watch `peek` until it halts with a0 = 55.
--   * circuit I/O: feed iron-plate=21 on the input wire, run the read-compute-commit
--     example, and watch iron-plate=42 appear on the output wire.
local t0, e_halt, e_io, halt_ok, io_ok
script.on_nth_tick(1, function(ev)
  if not t0 then
    local surface = game.surfaces[1]
    e_halt = place(surface, { 0, 0 })
    check(remote.call(DEBUG, "load", e_halt.unit_number, HALT_SRC), "halt: load failed")
    e_io = place(surface, { 20, 0 })
    wire_feeder(surface, e_io, "iron-plate", 21)
    check(remote.call(DEBUG, "load", e_io.unit_number, io_example_src()), "io: load failed")
    run_blueprint_check(surface) -- synchronous: builds a tagged blueprint copy and asserts
    t0 = ev.tick
    return
  end

  if not halt_ok then
    local p = remote.call(DEBUG, "peek", e_halt.unit_number)
    if p and p.mode == "halted" then
      check(p.x[10] == 55, "halt: a0 = " .. tostring(p.x[10]) .. ", want 55")
      halt_ok = true
    end
  end
  if not io_ok and out_signal(e_io, "iron-plate") == 42 then
    io_ok = true -- the doubled signal reached the output wire
  end

  if halt_ok and io_ok then
    script.on_nth_tick(1, nil)
    log(
      "[in-game test] PASSED: example programs + black-box halt + black-box circuit I/O"
        .. " + blueprint round-trip"
    )
  elseif ev.tick > t0 + 80 then
    check(false, "in-game timeout: halt_ok=" .. tostring(halt_ok) .. " io_ok=" .. tostring(io_ok))
  end
end)
