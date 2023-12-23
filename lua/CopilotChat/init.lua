-- Define a module table
local M = {}

-- Set up the plugin
M.setup = function()
  vim.notify(
    "Please run ':UpdateRemotePlugins' and restart Neovim to use CopilotChat.nvim",
    vim.log.levels.INFO,
    {
      title = 'CopilotChat.nvim',
    }
  )
end

return M
