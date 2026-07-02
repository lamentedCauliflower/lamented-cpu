-- Pure status-face mapping (ADR-0010, #35): a Hart mode -> a status token (sprite + tint)
-- for the entity-face overlay. Engine-free -- control.lua is the adapter that drives the
-- LuaRendering object from these tokens (create on appear, re-point on transition, destroy
-- on removal). Driven directly in spec/overlay_spec.lua. Prior art: iocontroller.
--
-- The native decider operation symbol can't be reused: our decision logic is inert
-- (ADR-0005), so the game has no Hart state to draw. One placeholder glyph is tinted per
-- mode instead; real per-state art is debt (ADR-0010).
local M = {}

-- The `sprite` prototype name the adapter draws (defined in data.lua) and reused here so
-- the token is complete. One glyph, recoloured per mode.
M.SPRITE = "riscv-combinator-status"

-- halted:pass (green) and halted:fail (red) are deliberately distinct; error reuses the
-- fail red; an unknown/absent mode falls back to the grey idle default (safe, never nil).
local RUNNING = { 0.30, 0.60, 1.00 } -- blue: stepping instructions
local STOPPED = { 0.55, 0.55, 0.55 } -- grey: idle
local PAUSED = { 0.95, 0.75, 0.15 } -- amber: held
local PASS = { 0.25, 0.90, 0.35 } -- green: halted clean (tohost == 1)
local FAIL = { 0.90, 0.25, 0.25 } -- red: halted non-zero / runtime error
local DEFAULT = STOPPED

local TINT = {
  stopped = STOPPED,
  running = RUNNING,
  paused = PAUSED,
  ["halted:pass"] = PASS,
  ["halted:fail"] = FAIL,
  error = FAIL,
}

-- mode -> { sprite, tint }. `mode` is the extended key the adapter derives (a bare
-- "halted" is split into "halted:pass"/"halted:fail" by the tohost result).
function M.overlay_for(mode)
  return { sprite = M.SPRITE, tint = TINT[mode] or DEFAULT }
end

return M
