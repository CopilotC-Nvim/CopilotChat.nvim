local log = require('plenary.log')
local M = {}

--- Create class
--- @param fn function The class constructor
--- @return table
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

-- The CopilotChat.nvim is built using remote plugins.
-- This is the path to the rplugin.vim file.
-- Refer https://neovim.io/doc/user/remote_plugin.html#%3AUpdateRemotePlugins
-- @return string
function M.get_remote_plugins_path()
  local os = vim.loop.os_uname().sysname
  if os == 'Linux' or os == 'Darwin' then
    return '~/.local/share/nvim/rplugin.vim'
  else
    return '~/AppData/Local/nvim/rplugin.vim'
  end
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
