local utils = require('CopilotChat.utils')

local M = {}

-- Set up the plugin
---@param options (table | nil)
--       - mode: ('newbuffer' | 'split') default: newbuffer.
M.setup = function(options)
  vim.g.copilot_chat_view_option = options and options.mode or 'newbuffer'

  -- Add new command to explain the selected text with CopilotChat
  utils.create_cmd('CopilotChatExplain', function()
    vim.cmd('CopilotChat Explain how it works')
  end, { nargs = '*', range = true })

  -- Add new command to generate unit tests with CopilotChat for selected text
  utils.create_cmd('CopilotChatTests', function(opts)
    local cmd = 'CopilotChat Briefly how selected code works then generate unit tests for the code.'
    -- Append the provided arguments to the command if any
    if opts.args then
      cmd = cmd .. ' ' .. opts.args
    end
    vim.cmd(cmd)
  end, { nargs = '*', range = true })
end

return M
