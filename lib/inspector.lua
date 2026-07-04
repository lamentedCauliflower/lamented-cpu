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
    enabled = true, -- default On (master enable); idle until Run
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

-- Stop: leave the run and return to the idle/stopped state. Drops the Hart entirely
-- so the views blank back to "(not assembled)"; the next Run reassembles from source.
-- A full reset of execution, not a resumable pause.
function M.stop(st)
  st.mode, st.status, st.dirty = "stopped", "idle", true
  st.hart, st.lines = nil, nil
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

-- memory view-model for the right column (#19): n word rows from base, addresses and
-- values as 8-digit hex; unwritten memory reads 0 (the Mem is sparse).
function M.memory_window(mem, base, n)
  local rows = {}
  for i = 0, n - 1 do
    local a = base + i * 4
    rows[#rows + 1] = { addr = hex(a), value = hex(mem:r32(a)) }
  end
  return rows
end

-- resolve a navigation preset to a base address: io is the fixed device base; stack
-- and pc follow the live Hart; program (and the fallback) is the reset/load address.
function M.region_base(hart, region)
  if region == "io" then
    return iocontroller.BASE
  elseif hart and region == "stack" then
    return hart.x[2]
  elseif hart and region == "pc" then
    return hart.pc
  end
  return 0x80000000
end

-- vector pane view-model (#42): the readout line and the v0..v31 rows, split by the
-- live vtype SEW. Display layer only -- element extraction mirrors the Hart's layout
-- (VLEN=128, 4 little-endian u32 words per register) without reaching into its
-- private helpers, same as the ABI/CSR duplication above.
local VSTART, VL, VTYPE = 0x008, 0xC20, 0xC21
local VILL = 0x80000000
local LMUL_NAMES = { [0] = "m1", "m2", "m4", "m8", nil, "mf8", "mf4", "mf2" }

-- decoded vtype in vsetvli-argument form ("e32m1,ta,ma"), or "vill"
local function vtype_decode(vt)
  if bit32.band(vt, VILL) ~= 0 then
    return "vill"
  end
  local sew = bit32.lshift(8, bit32.band(bit32.rshift(vt, 3), 7))
  local lmul = LMUL_NAMES[bit32.band(vt, 7)] or "m?"
  local ta = bit32.band(vt, 0x40) ~= 0 and "ta" or "tu"
  local ma = bit32.band(vt, 0x80) ~= 0 and "ma" or "mu"
  return ("e%d%s,%s,%s"):format(sew, lmul, ta, ma)
end

function M.vector_readout(hart)
  local csr = hart.csr
  return ("vl=%d  vtype=%s  vstart=%d"):format(
    csr[VL] or 0,
    vtype_decode(csr[VTYPE] or VILL),
    csr[VSTART] or 0
  )
end

-- one row per vector register, elements as fixed-width hex cells at the live
-- SEW (element 0 leftmost). Under vill there is no SEW, so fall back to the
-- raw 32-bit word view.
function M.vector_rows(hart)
  local vt = hart.csr[VTYPE] or VILL
  local sew = 32
  if bit32.band(vt, VILL) == 0 then
    sew = bit32.lshift(8, bit32.band(bit32.rshift(vt, 3), 7))
  end
  local fmt = ("%%0%dx"):format(sew / 4)
  local rows = {}
  for r = 0, 31 do
    local reg = hart.v and hart.v[r] or { 0, 0, 0, 0 }
    local cells = {}
    for e = 0, 128 / sew - 1 do
      local byte = e * (sew / 8)
      local val = reg[math.floor(byte / 4) + 1] or 0
      if sew < 32 then
        val = bit32.band(bit32.rshift(val, (byte % 4) * 8), sew == 8 and 0xFF or 0xFFFF)
      end
      cells[e + 1] = fmt:format(val)
    end
    rows[r + 1] = { label = "v" .. r, cells = cells }
  end
  return rows
end

-- changed-cell diff for the highlight (#20): which rows of `cur` differ in value from
-- `prev` (writes only). A nil prev is the post-reset/post-nav baseline -- nothing
-- flashes. Rows are compared by index, so the adapter clears prev on navigation.
function M.diff(prev, cur)
  local changed = {}
  if not prev then
    return changed
  end
  for i, row in ipairs(cur) do
    local p = prev[i]
    if p and p.value ~= row.value then
      changed[i] = true
    end
  end
  return changed
end

return M
