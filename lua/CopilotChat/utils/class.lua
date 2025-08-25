---@class Class
---@field new fun(...):table
---@field init fun(self, ...)

--- Create class
---@param fn function The class constructor
---@param parent table? The parent class
---@return Class
local function class(fn, parent)
  local out = {}
  out.__index = out

  local mt = {
    __call = function(cls, ...)
      return cls.new(...)
    end,
  }

  if parent then
    mt.__index = parent
  end

  setmetatable(out, mt)

  function out.new(...)
    local self = setmetatable({}, out)
    fn(self, ...)
    return self
  end

  function out.init(self, ...)
    fn(self, ...)
  end

  return out
end

return class
