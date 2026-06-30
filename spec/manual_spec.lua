-- The Manual's pure core (ADR-0008): IR -> Informatron menu. The GUI rendering and
-- the live remote registration are only exercisable in the full client; here we pin
-- the engine-free shape the adapter is built from.
local ir = require("lib.manual")
local content = require("lib.manual.content")

describe("Manual IR", function()
  it("exercises every block kind across the shipped chapters", function()
    local seen = {}
    for _, ch in ipairs(content) do
      for _, b in ipairs(ch.blocks) do
        seen[b.kind] = true
      end
    end
    for _, kind in ipairs({ "heading", "para", "table", "rows", "code" }) do
      assert.is_true(seen[kind], "no " .. kind .. " block in any chapter")
    end
  end)

  it("flattens a structured-row block to headers + cell matrix", function()
    local regs = content[2] -- Register Reference
    local rowblock
    for _, b in ipairs(regs.blocks) do
      if b.kind == "rows" then
        rowblock = b
      end
    end
    local headers, cells = ir._as_grid(rowblock)
    assert.are.same({ "Register", "ABI", "Saver", "Role" }, headers)
    assert.are.equal("x0", cells[1][1])
    assert.are.equal("zero", cells[1][2])
    assert.are.equal(32, #cells) -- x0..x31
  end)
end)

describe("Informatron adapter", function()
  it("lists subpages but not the root chapter", function()
    local menu = ir.informatron_menu(content)
    local n = 0
    for _ in pairs(menu) do
      n = n + 1
    end
    assert.are.equal(#content - 1, n) -- root (Overview) is the interface page, not a menu entry
    assert.is_truthy(menu["registers"])
    assert.is_nil(menu["overview"])
  end)
end)
