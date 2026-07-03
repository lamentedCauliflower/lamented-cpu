-- The Wiki mirror (CONTEXT.md): the Markdown renderer over the Manual IR. Pins the
-- page mapping (first chapter = Home, title-derived filenames), the GFM escaping the
-- content actually needs (pipes in instruction cells), and the plain-string guard.
local md = require("lib.manual.markdown")
local content = require("lib.manual.content")

describe("Wiki mirror", function()
  local files = md.render_all(content, "abc1234")

  it("maps the first chapter to Home and the rest to title-derived pages", function()
    assert.are.equal("Home", md.page_name(content, 1))
    for i, ch in ipairs(content) do
      if ch.id == "circuit-io" then
        assert.are.equal("Circuit-I-O", md.page_name(content, i)) -- "/" sanitised
      end
      if ch.id == "memory-model" then
        assert.are.equal("Memory-Execution-Model", md.page_name(content, i)) -- "&" sanitised
      end
    end
  end)

  it("emits one page per chapter plus sidebar and footer", function()
    local n = 0
    for _ in pairs(files) do
      n = n + 1
    end
    assert.are.equal(#content + 2, n)
    assert.is_truthy(files["Home.md"])
    assert.is_truthy(files["_Sidebar.md"])
    assert.is_truthy(files["_Footer.md"])
  end)

  it("derives wiki-safe filenames for every chapter", function()
    for i = 2, #content do
      assert.is_truthy(md.page_name(content, i):match("^[%w%-]+$"))
    end
  end)

  it("stamps every chapter page as generated", function()
    for name, body in pairs(files) do
      if not name:match("^_") then
        assert.is_truthy(body:find("do not edit", 1, true), name .. " missing generated stamp")
      end
    end
  end)

  it("escapes GFM pipes inside table cells", function()
    -- lib/manual/content.lua documents `or` as "rd = rs1 | rs2"; unescaped, the pipe
    -- would split the Markdown table cell.
    assert.is_truthy(files["Instruction-Set.md"]:find("rd = rs1 \\| rs2", 1, true))
  end)

  it("renders code blocks as fenced asm", function()
    assert.is_truthy(files["Home.md"]:find("```asm\n", 1, true))
  end)

  it("renders grids as pipe tables with a separator matching the header count", function()
    local ch -- the Register Reference: one `rows` block, 4 columns
    for _, c in ipairs(content) do
      if c.id == "registers" then
        ch = c
      end
    end
    local page = md.render_chapter(ch)
    assert.is_truthy(page:find("\n| --- | --- | --- | --- |\n", 1, true))
  end)

  it("keeps the sidebar in chapter order with links matching the filenames", function()
    local sidebar = files["_Sidebar.md"]
    local last = 0
    for i, ch in ipairs(content) do
      local link = ("(%s)"):format(md.page_name(content, i))
      local at = sidebar:find(link, 1, true)
      assert.is_truthy(at, ch.title .. " missing from sidebar")
      assert.is_true(at > last, ch.title .. " out of order in sidebar")
      last = at
    end
  end)

  it("rejects a LocalisedString where Markdown needs a plain string", function()
    local ch =
      { id = "x", title = "X", blocks = { { kind = "para", text = { "some.locale.key" } } } }
    assert.has_error(function()
      md.render_chapter(ch)
    end)
  end)
end)
