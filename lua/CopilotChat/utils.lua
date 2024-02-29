local log = require('plenary.log')
local M = {}

--- Create class
---@param fn function The class constructor
---@return table
function M.class(fn)
  local out = {}
  out.__index = out
  setmetatable(out, {
    __call = function(cls, ...)
      return cls.new(...)
    end,
  })

  function out.new(...)
    local self = setmetatable({}, out)
    fn(self, ...)
    return self
  end
  return out
end

--- Get the log file path
---@return string
function M.get_log_file_path()
  return log.logfile
end

--- Check if the current version of neovim is stable
---@return boolean
function M.is_stable()
  return vim.fn.has('nvim-0.10.0') == 0
end

return M
