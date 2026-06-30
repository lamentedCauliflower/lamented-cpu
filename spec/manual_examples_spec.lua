-- Examples gate (#28, ADR-0008): every code block the Manual prints is real
-- assembly that assembles cleanly, so no worked example can rot. Covers the
-- Examples chapter's four programs and every other inline snippet.
local asm = require("asm")
local content = require("lib.manual.content")

describe("Manual code examples", function()
  for _, ch in ipairs(content) do
    for _, b in ipairs(ch.blocks) do
      if b.kind == "code" then
        it("assembles the snippet in " .. ch.id, function()
          assert.has_no.errors(function()
            asm.assemble(b.text)
          end)
        end)
      end
    end
  end

  it("ships at least four worked example programs", function()
    local examples
    for _, ch in ipairs(content) do
      if ch.id == "examples" then
        examples = ch
      end
    end
    assert.is_truthy(examples)
    local n = 0
    for _, b in ipairs(examples.blocks) do
      if b.kind == "code" then
        n = n + 1
      end
    end
    assert.is_true(n >= 4, "expected >= 4 example programs, saw " .. n)
  end)
end)
