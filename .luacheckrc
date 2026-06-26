-- luacheck config for the Factorio mod.
-- Factorio 2.0 runs stock Lua 5.2.
std = "lua52"
cache = true
max_line_length = 120

-- Engine globals the mod writes to (handlers, persistent state, registrations).
globals = {
  "data", "script", "storage", "global", "remote", "commands", "rendering",
}

-- Engine globals the mod only reads.
read_globals = {
  "game", "defines", "settings", "prototypes", "mods", "log", "util",
  "table", "table_size", "serpent", "entity", "__DebugAdapter", "__Profiler",
}

-- busted specs use describe/it/assert; keep lint strict on mod code only.
-- .factorio/ holds the dev sandbox (incl. a symlink back to the repo root),
-- so it must never be walked.
exclude_files = { "spec/**.lua", ".factorio/**" }
