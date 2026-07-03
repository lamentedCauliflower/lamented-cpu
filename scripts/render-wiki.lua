-- Render the Wiki mirror (CONTEXT.md) to a directory of GitHub-wiki Markdown files.
-- Run from the repo root:  lua scripts/render-wiki.lua [outdir]   (default build/wiki)
-- CI (.github/workflows/wiki.yml) publishes the result to lamented-cpu.wiki.git.
local content = require("lib.manual.content")
local md = require("lib.manual.markdown")

local outdir = ... or "build/wiki"
local sha = os.getenv("GITHUB_SHA") or "local"
assert(os.execute("mkdir -p '" .. outdir .. "'"), "mkdir failed: " .. outdir)

local files = md.render_all(content, sha)
local names = {}
for name in pairs(files) do
  names[#names + 1] = name
end
table.sort(names)
for _, name in ipairs(names) do
  local f = assert(io.open(outdir .. "/" .. name, "w"))
  f:write(files[name])
  f:close()
end
print(("wrote %d wiki pages to %s"):format(#names, outdir))
