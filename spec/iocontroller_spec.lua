-- Pure Circuit-network controller (lib/iocontroller): Sample colour/merge/overflow
-- semantics (#12), driven directly on a plain Mem with fake wire tables -- no Hart,
-- no engine.
local Mem = require("mem")
local io = require("iocontroller")
local SignalMap = require("signalmap")

local function read_snapshot(mem)
  local n = mem:r32(io.BASE + io.SNAPSHOT)
  local pairs_ = {}
  for i = 1, n do
    local at = io.BASE + io.SNAPSHOT + 4 + (i - 1) * 8
    pairs_[#pairs_ + 1] = { id = mem:r32(at), value = mem:r32(at + 4) }
  end
  return n, pairs_
end

local function status(mem)
  return mem:r32(io.BASE + io.STATUS)
end

describe("controller Sample", function()
  it("colour 1 selects red only", function()
    local mem = Mem.new()
    io.sample(mem, { red = { [1] = 5 }, green = { [2] = 9 } }, 1)
    local n, p = read_snapshot(mem)
    assert.are.equal(1, n)
    assert.are.same({ { id = 1, value = 5 } }, p)
  end)

  it("colour 2 selects green only", function()
    local mem = Mem.new()
    io.sample(mem, { red = { [1] = 5 }, green = { [2] = 9 } }, 2)
    local _, p = read_snapshot(mem)
    assert.are.same({ { id = 2, value = 9 } }, p)
  end)

  it("colour 3 sums same-id values across red+green", function()
    local mem = Mem.new()
    io.sample(mem, { red = { [1] = 5, [2] = 1 }, green = { [1] = 3, [3] = 9 } }, 3)
    local n, p = read_snapshot(mem)
    -- ids sorted: 1 -> 5+3=8, 2 -> 1 (red only), 3 -> 9 (green only)
    assert.are.equal(3, n)
    assert.are.same({ { id = 1, value = 8 }, { id = 2, value = 1 }, { id = 3, value = 9 } }, p)
  end)

  it("snapshot is iterable and a specific resolved id is findable", function()
    local mem = Mem.new()
    io.sample(mem, { red = { [10] = 100, [20] = 200, [30] = 300 } }, 1)
    local n, p = read_snapshot(mem)
    local found
    for i = 1, n do -- exactly what a program does: scan for its id
      if p[i].id == 20 then
        found = p[i].value
      end
    end
    assert.are.equal(200, found)
  end)

  it("merged value wraps at 32 bits like the native network", function()
    local mem = Mem.new()
    io.sample(mem, { red = { [1] = 0x7FFFFFFF }, green = { [1] = 1 } }, 3)
    local _, p = read_snapshot(mem)
    assert.are.equal(0x80000000, p[1].value) -- 0x7FFFFFFF + 1, unsigned word
  end)

  it("no overflow leaves STATUS bit0 clear", function()
    local mem = Mem.new()
    io.sample(mem, { red = { [1] = 1 } }, 1)
    assert.are.equal(0, status(mem) % 2)
  end)

  it("more than 256 signals truncates and sets the overflow bit", function()
    local mem = Mem.new()
    local red = {}
    for id = 1, 300 do
      red[id] = id
    end
    io.sample(mem, { red = red }, 1)
    local n, p = read_snapshot(mem)
    assert.are.equal(256, n) -- count capped
    assert.are.equal(1, status(mem) % 2) -- overflow bit set
    assert.are.equal(1, p[1].id) -- kept the lowest-id entries
    assert.are.equal(256, p[256].id)
  end)

  it("a fresh non-overflowing Sample clears a previously-set overflow bit", function()
    local mem = Mem.new()
    local red = {}
    for id = 1, 300 do
      red[id] = id
    end
    io.sample(mem, { red = red }, 1) -- overflow
    io.sample(mem, { red = { [1] = 1 } }, 1) -- fits
    assert.are.equal(0, status(mem) % 2)
  end)
end)

local function write_staging(mem, list)
  mem:w32(io.BASE + io.STAGING, #list)
  for i, p in ipairs(list) do
    local at = io.BASE + io.STAGING + 4 + (i - 1) * 8
    mem:w32(at, p.id)
    mem:w32(at + 4, p.value)
  end
end

describe("controller Commit", function()
  local map, a, b, c
  before_each(function()
    map = SignalMap.new()
    a = map:lookup_or_alloc("item", "iron-plate")
    b = map:lookup_or_alloc("virtual-signal", "signal-A")
    c = map:lookup_or_alloc("fluid", "water")
  end)

  it("flushes the whole multi-signal staging set atomically, in order", function()
    local mem = Mem.new()
    write_staging(mem, { { id = a, value = 10 }, { id = b, value = 20 }, { id = c, value = 30 } })
    local set = io.commit(mem, map)
    assert.are.same({
      { id = a, type = "item", name = "iron-plate", value = 10 },
      { id = b, type = "virtual-signal", name = "signal-A", value = 20 },
      { id = c, type = "fluid", name = "water", value = 30 },
    }, set)
  end)

  it("signs values", function()
    local mem = Mem.new()
    write_staging(mem, { { id = a, value = 0xFFFFFFFF } })
    assert.are.equal(-1, io.commit(mem, map)[1].value)
  end)

  it("drops a staged id absent from the reverse map and sets STATUS bit1", function()
    local mem = Mem.new()
    write_staging(mem, { { id = a, value = 1 }, { id = 9999, value = 2 } })
    local set = io.commit(mem, map)
    assert.are.equal(1, #set) -- the unmapped id is gone
    assert.are.equal(a, set[1].id)
    assert.are.equal(1, math.floor(status(mem) / 2) % 2) -- bit1 set
  end)

  it("a clean Commit clears a previously-set drop bit", function()
    local mem = Mem.new()
    write_staging(mem, { { id = 9999, value = 2 } })
    io.commit(mem, map) -- drops -> bit1 set
    write_staging(mem, { { id = a, value = 1 } })
    io.commit(mem, map) -- clean
    assert.are.equal(0, math.floor(status(mem) / 2) % 2)
  end)

  it("Commit leaves the Sample overflow bit untouched", function()
    local mem = Mem.new()
    local red = {}
    for id = 1, 300 do
      red[id] = id
    end
    io.sample(mem, { red = red }, 1) -- sets overflow bit0
    write_staging(mem, { { id = a, value = 1 } })
    io.commit(mem, map)
    assert.are.equal(1, status(mem) % 2) -- overflow bit0 still set
  end)

  it("an empty staging Commits an empty set (the reset path's output)", function()
    local mem = Mem.new()
    assert.are.same({}, io.commit(mem, map))
  end)
end)
