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
local Inspector = require("lib.inspector")
local iobridge = require("lib.iobridge")
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

-- A halting sum program placed on a real combinator (no wires) -- proves on_built
-- builds a Hart that runs in-world.
local function run_halt_test(surface)
  local pos = surface.find_non_colliding_position("riscv-combinator", { 0, 0 }, 64, 1) or { 0, 0 }
  local before = surface.count_entities_filtered({ name = "riscv-combinator-output" })
  local e = surface.create_entity({ name = "riscv-combinator", position = pos, force = "player" })
  check(e and e.valid, "could not place a RISC-V Combinator")
  script.raise_script_built({ entity = e }) -- fire control.lua's on_built
  check(
    surface.count_entities_filtered({ name = "riscv-combinator-output" }) > before,
    "placing the combinator did not trigger on_built (no output combinator)"
  )
  local cpu = Inspector.new(HALT_SRC)
  Inspector.run(cpu, function()
    return 1
  end)
  for _ = 1, 2000 do
    Inspector.tick(cpu)
    if cpu.mode ~= "running" then
      break
    end
  end
  check(cpu.mode == "halted", "halt program did not halt: " .. tostring(cpu.mode))
  check(cpu.hart.x[10] == 55, "in-world a0 = " .. tostring(cpu.hart.x[10]) .. ", want 55")
end

-- Black-box Circuit I/O: feed [item=iron-plate]=21 on the input wire, run the Manual's
-- read-compute-commit example through the REAL bridge against a real combinator, and
-- read the doubled signal back off the output wire. Spans ticks because the circuit
-- network needs a tick to propagate a placement/commit.
local iostate

local function io_setup(surface)
  local pos = surface.find_non_colliding_position("riscv-combinator", { 20, 0 }, 64, 1) or { 20, 0 }
  local e = surface.create_entity({ name = "riscv-combinator", position = pos, force = "player" })
  check(e and e.valid, "io: could not place combinator")
  script.raise_script_built({ entity = e })
  local outproxy =
    surface.find_entities_filtered({ name = "riscv-combinator-output", position = e.position })[1]
  check(outproxy and outproxy.valid, "io: on_built did not create the output combinator")
  local fpos =
    surface.find_non_colliding_position("constant-combinator", { pos.x + 2, pos.y }, 64, 1)
  local feeder =
    surface.create_entity({ name = "constant-combinator", position = fpos, force = "player" })
  check(feeder and feeder.valid, "io: could not place feeder combinator")
  set_cc(feeder, "iron-plate", 21)
  -- wire feeder -> combinator input (same call shape as control.lua's make_outproxy).
  feeder.get_wire_connector(CC_RED, true).connect_to(e.get_wire_connector(RED_IN, true))
  iostate = { e = e, outproxy = outproxy, sm = SignalMap.new() }
end

local function io_run()
  local st = iostate
  local h = build(io_example_src())
  h.io_base = io.BASE
  drive(h, 200, function(hh)
    local d = hh.doorbell
    if not d then
      return
    end
    hh.doorbell = nil
    if d.off == io.SAMPLE then
      io.sample(hh.mem, iobridge.read_input(st.e, st.sm), d.value)
    elseif d.off == io.COMMIT then
      iobridge.write_output(st.outproxy, io.commit(hh.mem, st.sm))
    end
  end)
end

local function io_assert()
  local cn = iostate.e.get_circuit_network(RED_OUT)
  local got = cn and cn.get_signal({ type = "item", name = "iron-plate", quality = "normal" })
  check(
    got == 42,
    "I/O black-box: output wire iron-plate = " .. tostring(got) .. ", want 42 (21 doubled)"
  )
end

-- on_nth_tick (not on_init/on_tick, which would clobber control.lua's handlers): a
-- tick-gated state machine so placement and commit can propagate on the wires.
local t0
script.on_nth_tick(1, function(ev)
  if not t0 then
    local surface = game.surfaces[1]
    run_halt_test(surface)
    io_setup(surface)
    t0 = ev.tick
  elseif ev.tick == t0 + 2 then
    io_run() -- input network is live: SAMPLE reads it, COMMIT writes the outproxy
  elseif ev.tick >= t0 + 4 then
    io_assert() -- output network has propagated the committed signal
    script.on_nth_tick(1, nil)
    log("[in-game test] PASSED: example programs + in-world combinator + circuit I/O")
  end
end)
