-- The portable configuration of a RISC-V Combinator (ADR-0009): its assembly source
-- and master-enable, and nothing else. This is the ONLY state that survives a
-- blueprint, a settings-paste, or a clone -- never the live Hart image (registers,
-- pc, CSRs, memory, run mode), whose memory holds per-save Signal-map IDs (ADR-0006)
-- that would be garbage in another save. Programs are portable as source, not images
-- (ADR-0004), so a frozen image could not travel in a blueprint even if we wanted it.
--
-- Pure (ADR-0001): this module serializes/parses plain tables and copies two fields
-- between cpu records. control.lua is the adapter that writes blueprint tags in
-- on_player_setup_blueprint, reads event.tags on build, and calls apply on
-- settings-paste and clone. Shared serialize/apply helper for issues #21 / #23 / #24.
local Inspector = require("lib.inspector")

local M = {}

-- Tag-table schema version. Bump when the shape changes and branch in from_tags so
-- blueprints saved by older versions keep loading.
M.VERSION = 1

-- serialize a cpu record's configuration into a versioned blueprint-tag table, written
-- into each combinator's blueprint entity tags in on_player_setup_blueprint.
function M.to_tags(cpu)
  return { v = M.VERSION, source = cpu.source, enabled = cpu.enabled }
end

-- parse blueprint tags (the entity's event.tags on build) back into a {source, enabled}
-- config, or nil if absent / wrong version / malformed. nil tells the caller to seed the
-- tutorial DEFAULT_SRC -- a hand-placed combinator carries no tags.
function M.from_tags(tags)
  if type(tags) ~= "table" or tags.v ~= M.VERSION then
    return nil
  end
  return { source = tags.source, enabled = tags.enabled }
end

-- apply a {source, enabled} config onto an existing cpu record (settings-paste and
-- clone target it), then force the cpu stopped + dirty so it reassembles from the new
-- source on the next Run. Never copies live execution state (ADR-0009): a running
-- target is reset, mirroring how the editor blocks edits while running. A missing
-- enabled defaults On (the master-enable default). A cpu record is itself a valid
-- config (it has .source and .enabled), so callers pass the source cpu directly.
function M.apply(cpu, cfg)
  cpu.source = cfg.source or ""
  cpu.enabled = cfg.enabled ~= false
  Inspector.stop(cpu) -- mode=stopped, status=idle, dirty=true, hart/lines dropped
end

return M
