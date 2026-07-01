-- Data stage: the RISC-V Combinator entity + item + hidden output combinator, plus the
-- recipe and technology that gate it (ADR-0010). Thin adapter: it deep-copies the base
-- prototypes it reuses (entity graphics, sounds, connection points), then calls the pure
-- builder (lib/protos) for the branch-dependent recipe / technology / item overrides and
-- data:extends the lot -- the gating branch follows mods["space-age"] (#33).
local Protos = require("lib.protos")

local NAME = Protos.NAME
local OUT = NAME .. "-output"

-- Visible entity: two-sided (separate input/output connectors) so sources wire to
-- the input side and consumers to the output side -- a Commit can never feed back
-- into the next Sample (ADR-0005). Cloned from the decider-combinator for its two
-- connectors; its native decision logic stays inert (we never set a condition) and
-- the committed signals ride the hidden output combinator instead.
local entity = table.deepcopy(data.raw["decider-combinator"]["decider-combinator"])
entity.name = NAME
entity.minable.result = NAME
-- Point Factoriopedia at the in-game Manual (ADR-0008), the real reference; this
-- blurb is only the pointer, since Factoriopedia can't hold chaptered prose.
entity.factoriopedia_description = {
  "",
  "Hosts one RISC-V Hart (RV32IM_Zicsr, machine mode). Open the in-game Manual "
    .. "(Informatron) for the full assembly reference.",
}

-- Hidden output combinator: a script-controlled constant-combinator wired to the
-- visible entity's output side. Commit rewrites its signals; it alone drives the
-- output wire. Off-grid, co-located, and not interactable on its own.
local out = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
out.name = OUT
out.minable = nil
out.selectable_in_game = false
out.collision_mask = { layers = {} }
out.flags = {
  "placeable-off-grid",
  "not-on-map",
  "not-deconstructable",
  "not-blueprintable",
  "hide-alt-info",
}

local item = table.deepcopy(data.raw["item"]["constant-combinator"])
item.name = NAME
item.place_result = NAME
item.order = "c[combinators]-z[" .. NAME .. "]"

-- Branch-dependent recipe / technology / item overrides from the pure builder. Vanilla
-- vs Space Age is chosen once here (#33); everything else is engine-free in lib/protos.
local built = Protos.build({ space_age = mods["space-age"] ~= nil })
for k, v in pairs(built.item) do
  item[k] = v -- stack_size, weight (rocket capacity) -- see lib/protos
end

data:extend({ entity, out, item, built.recipe, built.technology })
