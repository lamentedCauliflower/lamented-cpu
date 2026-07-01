-- Data stage: the RISC-V Combinator entity + item + hidden output combinator, plus the
-- recipe and technology that gate it (ADR-0010). Thin adapter: it deep-copies the base
-- prototypes it reuses (entity graphics, sounds, connection points), then calls the pure
-- builder (lib/protos) for the branch-dependent recipe / technology / item overrides and
-- data:extends the lot -- the gating branch follows mods["space-age"] (#33).
local Protos = require("lib.protos")
local Overlay = require("lib.overlay") -- pure: only the status-sprite name at data stage

local NAME = Protos.NAME
local OUT = NAME .. "-output"

-- Branch-dependent prototype data from the pure builder. Vanilla vs Space Age is chosen
-- once here (#33); the entity geometry (below) is branch-independent.
local built = Protos.build({ space_age = mods["space-age"] ~= nil })

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

-- 3x2 custom body (ADR-0010, #34): drop the borrowed 1x2 decider silhouette. Geometry --
-- the footprint plus the two-sided input/output split -- is pure in lib/protos; the
-- placeholder art and wire attach points are engine-facing and live here.
local geo = built.entity
entity.tile_width = geo.tile_width
entity.tile_height = geo.tile_height
entity.collision_box = geo.collision_box
entity.selection_box = geo.selection_box
entity.input_connection_bounding_box = geo.input_connection_bounding_box
entity.output_connection_bounding_box = geo.output_connection_bounding_box
entity.fast_replaceable_group = nil -- no longer a drop-in for the 1x2 decider

-- Flat placeholder sprite (ADR-0010 tracks Blender art as debt), authored at 32 px/tile
-- so scale 1 maps 1:1 to tiles. N/S share the 3-wide body, E/W the 2-wide; the shadow is
-- the same image redrawn with draw_as_shadow, so there is no separate shadow asset.
local GFX = "__lamented-cpu__/graphics/entity/"
local function body4(file, w, h)
  return {
    layers = {
      { filename = GFX .. file, width = w, height = h, priority = "high" },
      {
        filename = GFX .. file,
        width = w,
        height = h,
        shift = { 0.3, 0.2 },
        draw_as_shadow = true,
      },
    },
  }
end
entity.sprites = {
  north = body4("riscv-combinator-h.png", 96, 64),
  south = body4("riscv-combinator-h.png", 96, 64),
  east = body4("riscv-combinator-v.png", 64, 96),
  west = body4("riscv-combinator-v.png", 64, 96),
}

-- Per-direction wire attach points (array order N, E, S, W), computed by rotating a
-- north-orientation base set out to the 3x2 edges. ponytail: a first calibration pass --
-- the exact offsets need the full client to verify (the load-smoke can't render wires);
-- nudge the base red/green offsets when tuning against the real art. Two-sidedness itself
-- is guaranteed by the connection bounding boxes above, not by these visual points.
local function rot(x, y, k)
  for _ = 1, k do
    x, y = -y, x -- 90 deg clockwise in screen coords (y down)
  end
  return { x, y }
end
local function conn_points(rx, ry, gx, gy)
  local out = {}
  for k = 0, 3 do
    local r, g = rot(rx, ry, k), rot(gx, gy, k)
    out[k + 1] = {
      wire = { red = r, green = g },
      shadow = { red = { r[1] + 0.2, r[2] + 0.3 }, green = { g[1] + 0.2, g[2] + 0.3 } },
    }
  end
  return out
end
entity.input_connection_points = conn_points(-0.4, 1.0, 0.4, 1.0) -- input side: bottom
entity.output_connection_points = conn_points(-0.4, -1.0, 0.4, -1.0) -- output side: top

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

-- Item field overrides from the builder (stack_size, weight -> rocket capacity).
for k, v in pairs(built.item) do
  item[k] = v -- see lib/protos
end

-- Status-face glyph (#35): one sprite the control stage draws over the entity face and
-- recolours per Hart mode (lib/overlay). Flat placeholder disc; per-state art is debt.
local status_sprite = {
  type = "sprite",
  name = Overlay.SPRITE,
  filename = "__lamented-cpu__/graphics/status/riscv-status.png",
  width = 32,
  height = 32,
  flags = { "gui-icon" },
}

data:extend({ entity, out, item, built.recipe, built.technology, status_sprite })
