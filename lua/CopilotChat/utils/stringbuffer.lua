local ok, jit_buffer = pcall(require, 'string.buffer')

---@class StringBuffer
---@field put fun(self:StringBuffer, s:string)
---@field set fun(self:StringBuffer, s:string)
---@field tostring fun(self:StringBuffer):string

--- Create a string buffer for efficient string concatenation
---@return StringBuffer
local function stringbuffer()
  if ok and jit_buffer then
    return {
      _buf = jit_buffer.new(),
      put = function(self, s)
        self._buf:put(s)
      end,
      set = function(self, s)
        self._buf:set(s)
      end,
      tostring = function(self)
        return self._buf:tostring()
      end,
    }
  end

  return {
    _buf = { '' },
    put = function(self, s)
      table.insert(self._buf, s)
      for i = #self._buf - 1, 1, -1 do
        if #self._buf[i] > #self._buf[i + 1] then
          break
        end
        self._buf[i] = self._buf[i] .. table.remove(self._buf)
      end
    end,
    set = function(self, s)
      self._buf = { s }
    end,
    tostring = function(self)
      return table.concat(self._buf)
    end,
  }
end

return stringbuffer
