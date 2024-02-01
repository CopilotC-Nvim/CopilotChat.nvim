local M = {}

local log = require('CopilotChat.vlog')

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
