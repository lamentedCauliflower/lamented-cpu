-- Pure Inspector core (Inspector 2/5): the Enable x Transport state machine and
-- the lazy-assemble / reset lifecycle for one Hart. Engine-free (ADR-0001) -- it
-- mutates a plain state table and calls the pure asm/Hart/Mem modules directly;
-- control.lua is the adapter (builds the GUI, services doorbells, passes the real
-- signal resolver). The same state table is the in-game cpu record, so the adapter
-- calls these functions on it directly; tests build one with M.new.
--
-- state = { enabled, mode, dirty, source, status, hart, lines }
--   mode: "stopped" | "running" | "paused" | "halted" | "error"
local asm = require("lib.asm")
local Hart = require("lib.hart")
local Mem = require("lib.mem")
local iocontroller = require("lib.iocontroller")

local M = {}

function M.new(source)
  return {
    enabled = false,
    mode = "stopped",
    dirty = true,
    source = source or "",
    status = "idle",
    hart = nil,
    lines = nil,
  }
end

-- assemble the current source and build a fresh Hart at the entry point. A failed
-- assemble leaves the prior Hart and latched output untouched (the adapter does not
-- clear the output on error) and parks in "error". Returns true on success.
local function assemble_reset(st, resolver)
  local ok, image = pcall(asm.assemble, st.source, resolver)
  if not ok then
    st.mode, st.status = "error", "assemble error: " .. tostring(image)
    return false
  end
  local h = Hart.new(Mem.new())
  h.io_base = iocontroller.BASE
  h:load(image)
  st.hart, st.lines, st.dirty = h, image.lines, false
  return true
end

-- a clean paused Hart we can resume without reassembling
local function resumable(st)
  return st.mode == "paused" and not st.dirty and st.hart ~= nil
end

-- advance exactly one instruction; detect halt (tohost write) / runtime error. The
-- adapter services any I/O doorbell between ticks. Mode-agnostic so both Run (called
-- each game tick) and Step (called once) share it.
function M.tick(st)
  local hart = st.hart
  local ok, err = pcall(hart.step, hart)
  if not ok then
    st.mode, st.status = "error", "runtime error: " .. tostring(err)
  elseif hart.tohost ~= nil then
    st.mode = "halted"
    st.status = (hart.tohost == 1) and "halted: pass"
      or ("halted: tohost=0x%08x"):format(hart.tohost)
  end
end

-- transport requires the master enable (the 2-axis model): Off gates everything.
function M.run(st, resolver)
  if not st.enabled then
    return
  end
  if not resumable(st) and not assemble_reset(st, resolver) then
    return
  end
  st.mode, st.status = "running", "running"
end

function M.step(st, resolver)
  if not st.enabled then
    return
  end
  if not resumable(st) and not assemble_reset(st, resolver) then
    return
  end
  M.tick(st)
  if st.mode ~= "halted" and st.mode ~= "error" then
    st.mode, st.status = "paused", "paused"
  end
end

function M.pause(st)
  if st.mode == "running" then
    st.mode, st.status = "paused", "paused"
  end
end

-- editing is only allowed when not running (the editor is read-only while running);
-- it stales the loaded Hart so the next Run/Step reassembles.
function M.edit(st, text)
  if st.mode == "running" then
    return
  end
  st.source, st.dirty = text, true
end

-- master power. Off holds state + the latched output; a running Hart parks paused so
-- turning it back On leaves it paused (resume is a deliberate Run), not auto-running.
function M.enable(st, on)
  st.enabled = on
  if not on and st.mode == "running" then
    st.mode, st.status = "paused", "paused"
  end
end

-- the line the gutter marks: the source line of the current PC, or nil if the PC has
-- no mapped line (e.g. inside reset/data) or no program is loaded.
function M.current_line(st)
  return st.hart and st.lines and st.lines[st.hart.pc] or nil
end

-- register view-model for the Inspector's left column (#18): x0..x31 by ABI name +
-- number, then pc, then the CSRs the Hart implements, values as 8-digit hex (x0 is
-- the hardwired constant zero). ponytail: ABI/CSR names are duplicated from asm.lua's
-- private tables -- this is the read-only display layer, not the encoder.
local ABI = {
  "zero",
  "ra",
  "sp",
  "gp",
  "tp",
  "t0",
  "t1",
  "t2",
  "s0",
  "s1",
  "a0",
  "a1",
  "a2",
  "a3",
  "a4",
  "a5",
  "a6",
  "a7",
  "s2",
  "s3",
  "s4",
  "s5",
  "s6",
  "s7",
  "s8",
  "s9",
  "s10",
  "s11",
  "t3",
  "t4",
  "t5",
  "t6",
}
local CSRS = {
  { "misa", 0x301 },
  { "mtvec", 0x305 },
  { "mepc", 0x341 },
  { "mcause", 0x342 },
  { "mtval", 0x343 },
}

local function hex(v)
  return ("0x%08x"):format(v)
end

function M.registers(hart)
  local rows = {}
  for i = 0, 31 do
    rows[#rows + 1] = { label = ABI[i + 1] .. " (x" .. i .. ")", value = hex(hart.x[i]) }
  end
  rows[#rows + 1] = { label = "pc", value = hex(hart.pc) }
  for _, c in ipairs(CSRS) do
    rows[#rows + 1] = { label = c[1], value = hex(hart.csr[c[2]] or 0) }
  end
  return rows
end

return M
