-- The Manual (ADR-0008): one chaptered RISC-V reference authored as a neutral
-- block-list IR and rendered through Informatron. This file is the IR + the
-- adapter; the chapter content lives in lib/manual/content.lua.
--
-- A chapter = { id, title, blocks }. A block is one of five kinds:
--   heading {level, text} | para {text} | code {text} |
--   table {headers, rows}  (rows = list of cell-string lists) |
--   rows  {columns, items} (structured: columns={{key,header}}, items=records)
-- `rows` is `table` with machine-readable payload kept on each item, so the #25
-- coverage test can assemble every documented mnemonic from the same source the
-- Manual renders. Both block kinds render identically (a grid); see as_grid.
--
-- A string anywhere a caption goes may be a LocalisedString, so per-page locale
-- migration stays possible later (ADR-0008) without touching the adapters.
local M = {}

------------------------------------------------------------------- IR constructors
function M.h1(text)
  return { kind = "heading", level = 1, text = text }
end
function M.h2(text)
  return { kind = "heading", level = 2, text = text }
end
function M.p(text)
  return { kind = "para", text = text }
end
function M.code(text)
  return { kind = "code", text = text }
end
function M.table(headers, rows)
  return { kind = "table", headers = headers, rows = rows }
end
-- columns = { {key=, header=}, ... }; items = list of records (extra fields kept)
function M.rows(columns, items)
  return { kind = "rows", columns = columns, items = items }
end

-- a table/rows block -> headers list + cell-string matrix, the shape the renderer
-- uses. For `rows` the cells are pulled from each item by column key.
local function as_grid(b)
  if b.kind == "table" then
    return b.headers, b.rows
  end
  local headers, keys = {}, {}
  for _, c in ipairs(b.columns) do
    headers[#headers + 1] = c.header
    keys[#keys + 1] = c.key
  end
  local rows = {}
  for _, it in ipairs(b.items) do
    local r = {}
    for i, k in ipairs(keys) do
      r[i] = it[k]
    end
    rows[#rows + 1] = r
  end
  return headers, rows
end
M._as_grid = as_grid -- exposed for the spec

local function chapters()
  return require("lib.manual.content")
end
M.chapters = chapters

----------------------------------------------------------------- Informatron adapter
local IF = "lamented-cpu" -- interface name == root page_name (the Overview chapter)

-- map every chapter to its Informatron page name: the first chapter is the root
-- (page_name == interface name); the rest are menu subpages keyed by their id.
local function pages(chs)
  local by_page = {}
  for i, ch in ipairs(chs) do
    by_page[(i == 1) and IF or ch.id] = ch
  end
  return by_page
end

-- Pure: the menu table { subpage_id = depth }. The root is reached as the interface
-- page itself, so it is deliberately absent here. Tested directly.
function M.informatron_menu(chs)
  local menu = {}
  for i, ch in ipairs(chs or chapters()) do
    if i > 1 then
      menu[ch.id] = 1 -- depth 1 = top-level entry
    end
  end
  return menu
end

-- Build one IR block into an Informatron page element (a LuaGuiElement flow).
-- ponytail: wrapping/style are only visible in the full client, not the load-smoke;
-- nudge maximal_width / styles there if a chapter reads cramped.
local function info_block(element, b)
  if b.kind == "heading" then
    element.add({
      type = "label",
      caption = b.text,
      style = b.level == 1 and "heading_1_label" or "heading_2_label",
    })
  elseif b.kind == "para" then
    local l = element.add({ type = "label", caption = b.text })
    l.style.single_line = false
    l.style.maximal_width = 580
  elseif b.kind == "code" then
    local tb = element.add({ type = "text-box", text = b.text }) -- selectable = copyable
    tb.read_only = true
    tb.style.maximal_width = 580
    tb.style.minimal_height = 72
  else
    local headers, rows = as_grid(b)
    local t = element.add({
      type = "table",
      column_count = #headers,
      draw_horizontal_lines = true,
    })
    for _, h in ipairs(headers) do
      t.add({ type = "label", caption = h, style = "heading_2_label" })
    end
    for _, r in ipairs(rows) do
      for _, cell in ipairs(r) do
        t.add({ type = "label", caption = cell })
      end
    end
  end
end

-- Register the Informatron client interface. Must run from the control.lua main
-- chunk (remote.add_interface is load-only). No-op when Informatron is absent so
-- the interface is never even exposed (ADR-0008). Informatron itself scans for
-- this interface and calls back at view time.
function M.register_informatron()
  if not remote.interfaces["informatron"] then
    return
  end
  remote.add_interface(IF, {
    informatron_menu = function()
      return M.informatron_menu()
    end,
    informatron_page_content = function(data)
      local ch = pages(chapters())[data.page_name]
      if ch then
        for _, b in ipairs(ch.blocks) do
          info_block(data.element, b)
        end
      end
    end,
    -- give the menu/title readable captions from the chapter title, so content can
    -- stay inline (no locale .cfg, ADR-0008). Harmless if Informatron ignores them.
    informatron_menu_caption_override = function(data)
      local ch = pages(chapters())[data.page_name]
      return ch and ch.title or nil
    end,
    informatron_title_caption_override = function(data)
      local ch = pages(chapters())[data.page_name]
      return ch and ch.title or nil
    end,
  })
end

------------------------------------------------------------------- open (Inspector)
-- The Inspector's Manual button (#29): present only when Informatron is installed.
function M.available()
  return remote.interfaces["informatron"] ~= nil
end

-- Open the Manual for a player. Informatron is the only backend with an open remote;
-- guarded so a missing or older Informatron never errors.
function M.open(player)
  local inf = remote.interfaces["informatron"]
  if inf and inf.informatron_open_to_page then
    remote.call("informatron", "informatron_open_to_page", {
      player_index = player.index,
      interface = IF,
      page_name = IF, -- the root page (Overview)
    })
  end
end

return M
