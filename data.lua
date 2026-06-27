-- Data stage: the RISC-V Combinator entity + item.
-- ponytail: clone the base constant-combinator so we reuse its graphics, build
-- sounds and circuit-connection points -- the mod ships no binary assets. We
-- only change identity and clear the native circuit behaviour (the program runs
-- in control.lua, not via vanilla combinator logic).
local NAME = "riscv-combinator"

local entity = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
entity.name = NAME
entity.minable.result = NAME

local item = table.deepcopy(data.raw["item"]["constant-combinator"])
item.name = NAME
item.place_result = NAME
item.order = "c[combinators]-z[" .. NAME .. "]"

local recipe = {
  type = "recipe",
  name = NAME,
  enabled = true,
  ingredients = {
    { type = "item", name = "copper-cable", amount = 5 },
    { type = "item", name = "electronic-circuit", amount = 2 },
  },
  results = { { type = "item", name = NAME, amount = 1 } },
}

data:extend({ entity, item, recipe })
