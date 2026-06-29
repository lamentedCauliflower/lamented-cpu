-- addr -> source-line map for the Inspector gutter (ADR-0007, Inspector 1/5).
local asm = require("asm")

describe("assembler source-line map", function()
  it("maps every address of a multi-instruction pseudo-op to its one source line", function()
    -- line 1 label, line 2 `li` (lui+addi -> 2 instrs), line 3 nop
    local img = asm.assemble("_start:\n  li a0, 0x12345\n  nop\n")
    assert.are.equal(2, img.lines[0x80000000]) -- lui  (li, line 2)
    assert.are.equal(2, img.lines[0x80000004]) -- addi (li, line 2)
    assert.are.equal(3, img.lines[0x80000008]) -- nop  (line 3)
  end)

  it("counts blank and comment lines so numbering matches the editor", function()
    local img = asm.assemble("_start:\n  nop\n# comment\n\n  nop\n")
    assert.are.equal(2, img.lines[0x80000000]) -- first nop, line 2
    assert.are.equal(5, img.lines[0x80000004]) -- second nop, line 5
  end)

  it("still returns the conformance shape (words present, source-map additive)", function()
    local img = asm.assemble("_start:\n  li a0, 7\n")
    assert.is_truthy(img.words)
    assert.is_truthy(img.lines)
  end)
end)
