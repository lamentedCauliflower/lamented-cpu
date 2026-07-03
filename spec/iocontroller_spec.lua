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
    -- 1 -> 5+3=8, 2 -> 1 (red only), 3 -> 9 (green only); largest value first
    assert.are.equal(3, n)
    assert.are.same({ { id = 3, value = 9 }, { id = 1, value = 8 }, { id = 2, value = 1 } }, p)
  end)

  it("pairs come descending by signed value, negatives after positives", function()
    local mem = Mem.new()
    io.sample(mem, { red = { [1] = 5, [2] = -2000000, [3] = 80 } }, 1)
    local _, p = read_snapshot(mem)
    assert.are.same({ 3, 1, 2 }, { p[1].id, p[2].id, p[3].id })
    assert.are.equal(0xFFE17B80, p[3].value) -- -2000000 as the stored word
  end)

  it("equal values tie-break ascending by id", function()
    local mem = Mem.new()
    io.sample(mem, { red = { [30] = 7, [10] = 7, [20] = 7 } }, 1)
    local _, p = read_snapshot(mem)
    assert.are.same({ 10, 20, 30 }, { p[1].id, p[2].id, p[3].id })
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
    assert.are.equal(300, p[1].id) -- kept the largest-value entries
    assert.are.equal(45, p[256].id) -- 300 down to 45; 44..1 dropped
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

-- Query sample (SAMPLE doorbell bit2, ADR-0011): Q1..Q16 hold ids the program
-- owns; the snapshot block answers them positionally with echoed-id pairs.
local function write_queries(mem, ids)
  for i, id in ipairs(ids) do
    mem:w32(io.BASE + io.QUERY + (i - 1) * 4, id)
  end
end

local function read_pair(mem, n)
  local at = io.BASE + io.SNAPSHOT + 4 + (n - 1) * 8
  return mem:r32(at), mem:r32(at + 4)
end

describe("controller Query sample", function()
  it("answers Qn into pair n, echoing the id; word0 counts hits", function()
    local mem = Mem.new()
    write_queries(mem, { 7, 0, 0, 0, 37 }) -- Q1 = 7, Q5 = 37, gaps unused
    io.sample(mem, { red = { [7] = 80, [12] = 5 } }, 5) -- query | red
    assert.are.equal(1, mem:r32(io.BASE + io.SNAPSHOT)) -- 7 hit, 37 missed
    local id, v = read_pair(mem, 1)
    assert.are.same({ 7, 80 }, { id, v })
    id, v = read_pair(mem, 5)
    assert.are.same({ 37, 0 }, { id, v }) -- miss: id echoed, value 0
    id, v = read_pair(mem, 2)
    assert.are.same({ 0, 0 }, { id, v }) -- unused slot
  end)

  it("Query registers persist across Samples", function()
    local mem = Mem.new()
    write_queries(mem, { 7 })
    io.sample(mem, { red = { [7] = 1 } }, 5)
    io.sample(mem, { red = { [7] = 2 } }, 5) -- no rewrite of Q1
    local _, v = read_pair(mem, 1)
    assert.are.equal(2, v)
  end)

  it("colour bits still pick the wires", function()
    local mem = Mem.new()
    write_queries(mem, { 7 })
    io.sample(mem, { red = { [7] = 80 }, green = { [7] = 9 } }, 6) -- query | green
    local _, v = read_pair(mem, 1)
    assert.are.equal(9, v)
  end)

  it("a red/green zero-sum is a hit with value 0, not a miss", function()
    local mem = Mem.new()
    write_queries(mem, { 7 })
    io.sample(mem, { red = { [7] = 5 }, green = { [7] = -5 } }, 7) -- query | both
    assert.are.equal(1, mem:r32(io.BASE + io.SNAPSHOT)) -- present on the wires
    local _, v = read_pair(mem, 1)
    assert.are.equal(0, v)
  end)

  it("clears a previous full sample's overflow bit (it never truncates)", function()
    local mem = Mem.new()
    local red = {}
    for id = 1, 300 do
      red[id] = id
    end
    io.sample(mem, { red = red }, 1) -- overflow -> bit0 set
    write_queries(mem, { 7 })
    io.sample(mem, { red = { [7] = 1 } }, 5)
    assert.are.equal(0, status(mem) % 2)
  end)

  it("writes exactly 16 pairs; the snapshot tail keeps the last full sample", function()
    local mem = Mem.new()
    local red = {}
    for id = 1, 20 do
      red[id] = id
    end
    io.sample(mem, { red = red }, 1) -- pairs 17..20 land past the query window
    local keep_id, keep_v = read_pair(mem, 17)
    write_queries(mem, { 7 })
    io.sample(mem, { red = { [7] = 1 } }, 5)
    local id, v = read_pair(mem, 17)
    assert.are.same({ keep_id, keep_v }, { id, v }) -- stale but untouched
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
