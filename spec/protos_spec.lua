-- Pure prototype builder (lib/protos, ADR-0010): the branch-dependent recipe, technology
-- and item overrides that gate the RISC-V Combinator, built as plain tables with no
-- engine. data.lua is the adapter. Prior art: config_spec, iocontroller_spec.
local Protos = require("protos")

describe("vanilla build", function()
  local out = Protos.build({ space_age = false })

  it("recipe is a locked crafting recipe unlocked by the technology", function()
    assert.are.same({ "crafting" }, out.recipe.categories) -- 2.1 `categories` list
    assert.is_false(out.recipe.enabled) -- not craftable until researched
    assert.are.same(
      { { type = "item", name = "riscv-combinator", amount = 1 } },
      out.recipe.results
    )
  end)

  it("recipe consumes 5x selector-combinator + 2x processing-unit", function()
    assert.are.same({
      { type = "item", name = "selector-combinator", amount = 5 },
      { type = "item", name = "processing-unit", amount = 2 },
    }, out.recipe.ingredients)
  end)

  it("technology has the vanilla prerequisites and unlocks the recipe", function()
    assert.are.same({ "advanced-combinators", "processing-unit" }, out.technology.prerequisites)
    assert.are.same(
      { { type = "unlock-recipe", recipe = "riscv-combinator" } },
      out.technology.effects
    )
  end)

  it("item stacks to 10 and weighs 100000 (one full stack per rocket)", function()
    assert.are.equal(10, out.item.stack_size)
    assert.are.equal(100000, out.item.weight)
  end)
end)
