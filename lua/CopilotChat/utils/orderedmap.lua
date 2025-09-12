---@class OrderedMap<K, V>
---@field set fun(self:OrderedMap, key:any, value:any)
---@field get fun(self:OrderedMap, key:any):any
---@field remove fun(self:OrderedMap, key:any)
---@field keys fun(self:OrderedMap):table
---@field values fun(self:OrderedMap):table

--- Create ordered map
---@generic K, V
---@return OrderedMap<K, V>
local function orderedmap()
  return {
    _keys = {},
    _data = {},
    set = function(self, key, value)
      if not self._data[key] then
        table.insert(self._keys, key)
      end
      self._data[key] = value
    end,

    get = function(self, key)
      return self._data[key]
    end,

    remove = function(self, key)
      if self._data[key] then
        self._data[key] = nil
        for i, k in ipairs(self._keys) do
          if k == key then
            table.remove(self._keys, i)
            break
          end
        end
      end
    end,

    keys = function(self)
      return self._keys
    end,

    values = function(self)
      local result = {}
      for _, key in ipairs(self._keys) do
        table.insert(result, self._data[key])
      end
      return result
    end,
  }
end

return orderedmap
