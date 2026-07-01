-- Pure status-face mapping (lib/overlay, ADR-0010 #35): Hart mode -> status token. No
-- engine; control.lua drives the LuaRendering object from these tokens. Prior art:
-- iocontroller_spec.
local Overlay = require("overlay")

describe("overlay_for", function()
  it("maps each mode to a distinct tint on the shared glyph", function()
    local seen = {}
    for _, mode in ipairs({ "stopped", "running", "paused", "halted:pass", "halted:fail" }) do
      local tok = Overlay.overlay_for(mode)
      assert.are.equal(Overlay.SPRITE, tok.sprite)
      local key = table.concat(tok.tint, ",")
      assert.is_nil(seen[key], mode .. " shares a tint") -- all five read differently
      seen[key] = true
    end
  end)

  it("halted:pass and halted:fail are visually distinct", function()
    assert.are_not.same(
      Overlay.overlay_for("halted:pass").tint,
      Overlay.overlay_for("halted:fail").tint
    )
  end)

  it("error reuses the fail token", function()
    assert.are.same(Overlay.overlay_for("halted:fail"), Overlay.overlay_for("error"))
  end)

  it("an unknown or absent mode returns the safe grey idle default", function()
    local default = Overlay.overlay_for("stopped")
    assert.are.same(default, Overlay.overlay_for("bogus-mode"))
    assert.are.same(default, Overlay.overlay_for(nil))
  end)
end)
