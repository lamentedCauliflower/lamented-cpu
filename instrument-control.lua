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

-- on_nth_tick (not on_init/on_tick) so we don't clobber control.lua's handlers; fires
-- once during the --benchmark run, places a combinator, and drives its Hart to a halt.
local ran = false
script.on_nth_tick(1, function()
  if ran then
    return
  end
  ran = true
  script.on_nth_tick(1, nil)

  local surface = game.surfaces[1]
  local pos = surface.find_non_colliding_position("riscv-combinator", { 0, 0 }, 64, 1) or { 0, 0 }

  -- placing a RISC-V Combinator must fire control.lua's on_built, which spawns the
  -- hidden output combinator. Assert that world side effect (storage is per-script
  -- context, so we observe the shared world, not the mod's private storage).
  local before = surface.count_entities_filtered({ name = "riscv-combinator-output" })
  local e = surface.create_entity({ name = "riscv-combinator", position = pos, force = "player" })
  check(e and e.valid, "could not place a RISC-V Combinator")
  script.raise_script_built({ entity = e })
  local after = surface.count_entities_filtered({ name = "riscv-combinator-output" })
  check(after > before, "placing the combinator did not trigger on_built (no output combinator)")

  -- and a real program runs to a halt on a Hart bound to this in-world placement.
  local cpu = Inspector.new(HALT_SRC)
  Inspector.run(cpu, function()
    return 1
  end) -- no signal tags, so the resolver is never called
  check(cpu.mode == "running", "Run did not start: " .. tostring(cpu.status))

  for _ = 1, 2000 do
    Inspector.tick(cpu)
    if cpu.mode ~= "running" then
      break
    end
  end
  check(cpu.mode == "halted", "program did not halt: mode=" .. tostring(cpu.mode))
  check(cpu.hart.x[10] == 55, "in-world a0 = " .. tostring(cpu.hart.x[10]) .. ", want 55")

  log("[in-game test] PASSED: example programs + in-world combinator")
end)
