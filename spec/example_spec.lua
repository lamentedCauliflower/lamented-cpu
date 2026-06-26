-- ponytail: example busted spec — delete or replace with your own.
local example = require("example")

describe("example.add", function()
  it("adds two numbers", function()
    assert.are.equal(3, example.add(1, 2))
  end)
end)
