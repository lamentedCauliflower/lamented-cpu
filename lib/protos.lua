-- Pure prototype builder (ADR-0010): returns the recipe, technology and item-field
-- overrides for the RISC-V Combinator as plain tables, with NO dependency on engine
-- globals (no data.raw, no data:extend, no mods). data.lua is the thin adapter that
-- deep-copies the base prototypes it reuses, calls build(), merges the item overrides
-- and hands the result to data:extend -- the same pure-core / adapter split as config
-- vs control and iocontroller vs iobridge. Driven directly in spec/protos_spec.lua.
--
-- Gating branches on opts.space_age; the adapter passes mods["space-age"] ~= nil.
-- Vanilla unlocks after combinators + blue circuits; Space Age is electromagnetic-plant-
-- only and Fulgora-gated (ADR-0010).
local M = {}

M.NAME = "riscv-combinator"

-- Placeholder tech icon: reuse the base advanced-combinators tech art -- a prerequisite,
-- so guaranteed present -- until real art ships. ADR-0010 tracks custom art as debt.
local TECH_ICON = "__base__/graphics/technology/advanced-combinators.png"
local TECH_ICON_SIZE = 256

function M.build(opts)
  local name = M.NAME
  local sa = (opts and opts.space_age) or false

  -- Everything that differs between vanilla and Space Age. Space Age makes the
  -- combinator electromagnetic-plant-only and Fulgora-gated (ADR-0010): the
  -- `electromagnetic-plant` tech chains off `holmium-processing` and itself unlocks
  -- supercapacitor, so the ingredient is craftable by the time this tech lands.
  local branch = sa
      and {
        category = "electromagnetics", -- crafted only in the electromagnetic plant
        ingredients = {
          { type = "item", name = "selector-combinator", amount = 3 },
          { type = "item", name = "supercapacitor", amount = 2 },
          { type = "item", name = "processing-unit", amount = 3 },
        },
        prerequisites = { "electromagnetic-plant" },
        science = { "electromagnetic-science-pack", 1 }, -- extra unit pack on Fulgora
      }
    or {
      category = "crafting",
      ingredients = {
        { type = "item", name = "selector-combinator", amount = 5 },
        { type = "item", name = "processing-unit", amount = 2 },
      },
      -- `processing-unit` is the 2.1 blue-circuit tech (was advanced-electronics-2 in 1.1).
      prerequisites = { "advanced-combinators", "processing-unit" },
      science = nil,
    }

  local unit_ingredients = {
    { "automation-science-pack", 1 }, -- red
    { "logistic-science-pack", 1 }, -- green
    { "chemical-science-pack", 1 }, -- blue
  }
  if branch.science then
    unit_ingredients[#unit_ingredients + 1] = branch.science
  end

  -- enabled = false: not craftable from the start; the technology below unlocks it.
  local recipe = {
    type = "recipe",
    name = name,
    enabled = false,
    categories = { branch.category }, -- 2.1 merged `category` into the `categories` list
    ingredients = branch.ingredients,
    results = { { type = "item", name = name, amount = 1 } },
  }

  local technology = {
    type = "technology",
    name = name,
    icon = TECH_ICON,
    icon_size = TECH_ICON_SIZE,
    effects = { { type = "unlock-recipe", recipe = name } },
    prerequisites = branch.prerequisites,
    unit = { count = 100, ingredients = unit_ingredients, time = 30 },
  }

  -- Item field overrides merged onto the deep-copied base item by the adapter: a small
  -- stack, and a rocket weight tuned so one full stack fills a rocket
  -- (default_rocket_lift_weight / weight = 1000000 / 100000 = 10).
  local item = { stack_size = 10, weight = 100000 }

  return { recipe = recipe, technology = technology, item = item }
end

return M
