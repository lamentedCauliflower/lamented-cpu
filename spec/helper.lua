-- ponytail: minimal engine-global stubs for busted.
-- Specs target pure modules; only stub what you actually touch. Auto-loaded
-- via the busted `helper` key in .busted. Returns nothing; sets globals.
local function stub()
  return setmetatable({}, {
    __index = function(t, k)
      local v = setmetatable({}, getmetatable(t))
      rawset(t, k, v)
      return v
    end,
    __call = function()
      return setmetatable({}, getmetatable(t))
    end,
  })
end

storage = storage or stub()
script = script
  or {
    on_init = function() end,
    on_load = function() end,
    on_configuration_changed = function() end,
  }
defines = defines or stub()
data = data or { extend = function() end }
