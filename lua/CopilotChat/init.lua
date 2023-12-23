local utils = require('CopilotChat.utils')

local M = {}

-- Set up the plugin
M.setup = function()
  -- Add new command to explain the selected text with CopilotChat
  utils.create_cmd('CChatExplain', function(opts)
    vim.cmd('CChat Explain how it works')
  end, { nargs = '*', range = true })
end

return M
