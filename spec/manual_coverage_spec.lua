-- Coverage gate (#25, ADR-0008): every mnemonic the Manual documents must actually
-- assemble, so the reference can never claim what the Assembler rejects. One-
-- directional: it does not check the reverse (an accepted mnemonic may be left
-- undocumented). Each documented instruction/pseudo row carries a concrete `ex`
-- one-liner; we assemble it wrapped in numeric labels so any 1f/1b target resolves.
local asm = require("asm")
local content = require("lib.manual.content")

describe("Manual mnemonic coverage", function()
  local n = 0
  for _, ch in ipairs(content) do
    for _, b in ipairs(ch.blocks) do
      if b.kind == "rows" then
        for _, item in ipairs(b.items) do
          if item.mnemonic then
            n = n + 1
            it("assembles documented `" .. item.mnemonic .. "` (" .. item.kind .. ")", function()
              assert.is_truthy(item.ex, item.mnemonic .. " has no example to assemble")
              assert.has_no.errors(function()
                asm.assemble("1:\n  " .. item.ex .. "\n1:\n")
              end)
            end)
          end
        end
      end
    end
  end

  it("documents a non-trivial instruction set", function()
    assert.is_true(n >= 250, "expected RV32IM_Zicsr plus the Zve32x chapter, saw " .. n)
  end)
end)
