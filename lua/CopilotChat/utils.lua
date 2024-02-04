local M = {}

local log = require('CopilotChat.vlog')

--- Get the log file path
---@return string
M.get_log_file_path = function()
  return log.get_log_file()
end

-- The CopilotChat.nvim is built using remote plugins.
-- This is the path to the rplugin.vim file.
-- Refer https://neovim.io/doc/user/remote_plugin.html#%3AUpdateRemotePlugins
-- @return string
M.get_remote_plugins_path = function()
  local os = vim.loop.os_uname().sysname
  if os == 'Linux' or os == 'Darwin' then
    return '~/.local/share/nvim/rplugin.vim'
  else
    return '~/AppData/Local/nvim/rplugin.vim'
  end
end

--- Create custom command
---@param cmd string The command name
---@param func function The function to execute
---@param opt table The options
M.create_cmd = function(cmd, func, opt)
  opt = vim.tbl_extend('force', { desc = 'CopilotChat.nvim ' .. cmd }, opt or {})
  vim.api.nvim_create_user_command(cmd, func, opt)
end

--- Log info
---@vararg any
M.log_info = function(...)
  -- Only save log when debug is on
  if not _COPILOT_CHAT_GLOBAL_CONFIG.debug then
    return
  end

  log.info(...)
end

--- Log error
---@vararg any
M.log_error = function(...)
  -- Only save log when debug is on
  if not _COPILOT_CHAT_GLOBAL_CONFIG.debug then
    return
  end

  log.error(...)
end

return M
