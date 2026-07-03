-- The Wiki mirror (CONTEXT.md): the second renderer ADR-0008 anticipated. Walks the
-- same block-list IR the Informatron adapter consumes and emits one GitHub-wiki
-- Markdown page per chapter, plus _Sidebar (chapter order; the wiki alphabetizes
-- otherwise) and _Footer. Pure Lua, no engine APIs -- run by scripts/render-wiki.lua
-- and the busted spec; CI publishes the output, so the wiki is a build artifact and
-- never hand-edited.
local ir = require("lib.manual")

local M = {}

-- Markdown has no LocalisedString. The IR allows them anywhere a string goes
-- (ADR-0008); if content ever migrates to locale keys, this renderer needs a
-- resolver first -- fail loudly, not with a rendered "table: 0x...".
local function plain(text)
  if type(text) ~= "string" then
    error(
      "Wiki mirror needs plain strings, got " .. type(text) .. " (LocalisedString? see ADR-0008)",
      0
    )
  end
  return text
end

-- IR text is plain prose, not Markdown: neutralise everything GFM could interpret
-- (emphasis, links, pipes, inline HTML). Backslash before ASCII punctuation is
-- always a literal escape in GFM, so over-escaping is safe.
local function escape(text)
  return (plain(text):gsub("([\\`*_%[%]<>|#])", "\\%1"))
end

-- One escaped table cell: pipe rows cannot hold newlines.
local function cell(text)
  local s = escape(text)
  if s:find("\n", 1, true) then
    error("table cell contains a newline: " .. s, 0)
  end
  return s
end

local function fence(text)
  local s = plain(text)
  if s:find("```", 1, true) then
    error("code block contains a fence", 0)
  end
  if s:sub(-1) ~= "\n" then
    s = s .. "\n"
  end
  return "```asm\n" .. s .. "```"
end

local function grid(b)
  local headers, rows = ir._as_grid(b)
  local hs = {}
  for i, h in ipairs(headers) do
    hs[i] = cell(h)
  end
  local out = { "| " .. table.concat(hs, " | ") .. " |", "|" .. (" --- |"):rep(#headers) }
  for _, r in ipairs(rows) do
    local cs = {}
    for i = 1, #headers do
      cs[i] = cell(r[i])
    end
    out[#out + 1] = "| " .. table.concat(cs, " | ") .. " |"
  end
  return table.concat(out, "\n")
end

local function block_md(b)
  if b.kind == "heading" then
    return ("#"):rep(b.level) .. " " .. escape(b.text)
  elseif b.kind == "para" then
    return escape(b.text)
  elseif b.kind == "code" then
    return fence(b.text)
  else
    return grid(b)
  end
end

-- Invisible when rendered; the first thing anyone opening the wiki editor sees.
local GENERATED =
  "<!-- Generated from lib/manual/content.lua — do not edit; CI overwrites this page. -->"

function M.render_chapter(ch)
  local parts = { GENERATED }
  for _, b in ipairs(ch.blocks) do
    parts[#parts + 1] = block_md(b)
  end
  return table.concat(parts, "\n\n") .. "\n"
end

-- GitHub shows the filename (dashes read as spaces) as the page title, so derive it
-- from the chapter title. Filenames only approximate titles ("Circuit I/O" ->
-- "Circuit-I-O"); the body h1 keeps the faithful one. The first chapter is the wiki
-- Home page, exactly as it is the Informatron root page.
function M.page_name(chs, i)
  if i == 1 then
    return "Home"
  end
  return (plain(chs[i].title):gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""))
end

function M.render_sidebar(chs)
  local lines = { "### Manual", "" }
  for i, ch in ipairs(chs) do
    lines[#lines + 1] = ("- [%s](%s)"):format(escape(ch.title), M.page_name(chs, i))
  end
  return table.concat(lines, "\n") .. "\n"
end

function M.render_footer(sha)
  return (
    "*This wiki mirrors the in-game Manual, generated from `lib/manual/content.lua`"
    .. " at `%s`. Do not edit — the next publish overwrites it.*\n"
  ):format(plain(sha))
end

-- The whole wiki as { filename = content }. `sha` stamps the footer with the
-- source commit (CI passes GITHUB_SHA).
function M.render_all(chs, sha)
  local files = {}
  for i, ch in ipairs(chs) do
    local name = M.page_name(chs, i) .. ".md"
    if files[name] then
      error("duplicate wiki page name: " .. name, 0)
    end
    files[name] = M.render_chapter(ch)
  end
  files["_Sidebar.md"] = M.render_sidebar(chs)
  files["_Footer.md"] = M.render_footer(sha)
  return files
end

return M
