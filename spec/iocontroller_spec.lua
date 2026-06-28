-- Pure Circuit-network controller (lib/iocontroller): Sample colour/merge/overflow
-- semantics (#12), driven directly on a plain Mem with fake wire tables -- no Hart,
-- no engine.
local Mem = require("mem")
local io = require("iocontroller")

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
