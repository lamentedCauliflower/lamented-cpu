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

  it("unit is red/green/blue science only -- no electromagnetic pack off Fulgora", function()
    assert.are.same({
      { "automation-science-pack", 1 },
      { "logistic-science-pack", 1 },
      { "chemical-science-pack", 1 },
    }, out.technology.unit.ingredients)
  end)
end)

describe("space age build", function()
  local out = Protos.build({ space_age = true })

  it("recipe is electromagnetic-plant-only (electromagnetics category)", function()
    assert.are.same({ "electromagnetics" }, out.recipe.categories)
    assert.is_false(out.recipe.enabled)
  end)

  it("recipe consumes 3x selector + 2x supercapacitor + 3x processing-unit", function()
    assert.are.same({
      { type = "item", name = "selector-combinator", amount = 3 },
      { type = "item", name = "supercapacitor", amount = 2 },
      { type = "item", name = "processing-unit", amount = 3 },
    }, out.recipe.ingredients)
  end)

  it("technology is Fulgora-gated via the electromagnetic-plant prerequisite", function()
    assert.are.same({ "electromagnetic-plant" }, out.technology.prerequisites)
  end)

  it("unit adds the electromagnetic science pack", function()
    assert.are.same({
      { "automation-science-pack", 1 },
      { "logistic-science-pack", 1 },
      { "chemical-science-pack", 1 },
      { "electromagnetic-science-pack", 1 },
    }, out.technology.unit.ingredients)
  end)
end)
