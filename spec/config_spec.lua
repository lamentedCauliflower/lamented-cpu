-- Portable configuration (ADR-0009): serialize a cpu's source + master-enable to
-- blueprint tags and apply it back, the shared helper behind blueprint / paste / clone
-- (#21 / #23 / #24). Pure: no engine. A cpu record is built with Inspector.new.
local Config = require("config")
local Inspector = require("inspector")

describe("Config serialize/parse", function()
  it("to_tags is a versioned {v, source, enabled} table", function()
    local cpu = Inspector.new("li a0, 1\n")
    cpu.enabled = false
    assert.are.same({ v = 1, source = "li a0, 1\n", enabled = false }, Config.to_tags(cpu))
  end)

  it("from_tags round-trips to_tags", function()
    local cpu = Inspector.new("nop\n")
    assert.are.same({ source = "nop\n", enabled = true }, Config.from_tags(Config.to_tags(cpu)))
  end)

  it("from_tags rejects absent / wrong-version / non-table tags", function()
    assert.is_nil(Config.from_tags(nil)) -- hand-placed: no tags -> caller seeds DEFAULT_SRC
    assert.is_nil(Config.from_tags({ v = 999, source = "x" })) -- unknown format
    assert.is_nil(Config.from_tags("not a table"))
  end)
end)

describe("Config.apply", function()
  it("copies source + enable and forces the target stopped, dropping live state", function()
    local st = Inspector.new("old\n")
    st.mode, st.dirty, st.hart, st.lines = "running", false, { pc = 42 }, {} -- a live run
    Config.apply(st, { source = "new\n", enabled = false })
    assert.are.equal("new\n", st.source)
    assert.is_false(st.enabled)
    assert.are.equal("stopped", st.mode) -- running target reset (ADR-0009)
    assert.is_true(st.dirty) -- reassembles from the new source on next Run
    assert.is_nil(st.hart) -- no live register/memory/pc state carried
    assert.is_nil(st.lines)
  end)

  it("defaults master-enable On when the config omits it", function()
    local st = Inspector.new("")
    Config.apply(st, { source = "x\n" })
    assert.is_true(st.enabled)
  end)

  it("blueprint round-trip: cpu -> tags -> config -> fresh cpu", function()
    local src = Inspector.new("program\n")
    src.enabled = false
    local dst = Inspector.new("")
    Config.apply(dst, Config.from_tags(Config.to_tags(src)))
    assert.are.equal("program\n", dst.source)
    assert.is_false(dst.enabled)
    assert.are.equal("stopped", dst.mode) -- built copy starts stopped
  end)
end)
