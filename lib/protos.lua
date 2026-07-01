-- Pure prototype builder (ADR-0010): returns the recipe, technology and item-field
-- overrides for the RISC-V Combinator as plain tables, with NO dependency on engine
-- globals (no data.raw, no data:extend, no mods). data.lua is the thin adapter that
-- deep-copies the base prototypes it reuses, calls build(), merges the item overrides
-- and hands the result to data:extend -- the same pure-core / adapter split as config
-- vs control and iocontroller vs iobridge. Driven directly in spec/protos_spec.lua.
--
-- Gating branches on opts.space_age; the adapter passes mods["space-age"] ~= nil. Only
-- the vanilla branch exists here (#32); the Space-Age branch is #33.
local M = {}

M.NAME = "riscv-combinator"

-- Placeholder tech icon: reuse the base advanced-combinators tech art -- a prerequisite,
-- so guaranteed present -- until real art ships. ADR-0010 tracks custom art as debt.
local TECH_ICON = "__base__/graphics/technology/advanced-combinators.png"
local TECH_ICON_SIZE = 256

function M.build(opts)
  local name = M.NAME
  local _ = opts -- ponytail: vanilla-only for now; #33 adds `if opts.space_age then`.

  -- enabled = false: not craftable from the start; the technology below unlocks it.
  local recipe = {
    type = "recipe",
    name = name,
    enabled = false,
    categories = { "crafting" }, -- 2.1 merged `category` into the `categories` list
    ingredients = {
      { type = "item", name = "selector-combinator", amount = 5 },
      { type = "item", name = "processing-unit", amount = 2 },
    },
    results = { { type = "item", name = name, amount = 1 } },
  }

  local technology = {
    type = "technology",
    name = name,
    icon = TECH_ICON,
    icon_size = TECH_ICON_SIZE,
    effects = { { type = "unlock-recipe", recipe = name } },
    -- `processing-unit` is the 2.1 blue-circuit tech (was advanced-electronics-2 in 1.1).
    prerequisites = { "advanced-combinators", "processing-unit" },
    unit = {
      count = 100,
      ingredients = {
        { "automation-science-pack", 1 }, -- red
        { "logistic-science-pack", 1 }, -- green
        { "chemical-science-pack", 1 }, -- blue
      },
      time = 30,
    },
  }

  -- Item field overrides merged onto the deep-copied base item by the adapter: a small
  -- stack, and a rocket weight tuned so one full stack fills a rocket
  -- (default_rocket_lift_weight / weight = 1000000 / 100000 = 10).
  local item = { stack_size = 10, weight = 100000 }

  return { recipe = recipe, technology = technology, item = item }
end

return M
