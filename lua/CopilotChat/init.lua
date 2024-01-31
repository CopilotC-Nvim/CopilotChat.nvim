local utils = require('CopilotChat.utils')

local M = {}

local default_prompts = {
  Explain = 'Explain how it works.',
  Tests = 'Briefly how selected code works then generate unit tests.',
}

-- Set up the plugin
---@param options (table | nil)
--       - mode: ('newbuffer' | 'split') default: newbuffer.
--       - show_help: ('yes' | 'no') default: 'yes'.
--       - prompts: (table?) default: default_prompts.
M.setup = function(options)
  vim.g.copilot_chat_view_option = options and options.mode or 'newbuffer'
  vim.g.copilot_chat_show_help = options and options.show_help or 'yes'

  -- Merge the provided prompts with the default prompts
  local prompts = vim.tbl_extend('force', default_prompts, options and options.prompts or {})
  vim.g.copilot_chat_user_prompts = prompts

  --  Loop through merged table and generate commands based on keys.
  for key, value in pairs(prompts) do
    utils.create_cmd('CopilotChat' .. key, function()
      vim.cmd('CopilotChat ' .. value)
    end, { nargs = '*', range = true })
  end

  for key, value in pairs(prompts) do
    utils.create_cmd('CC' .. key, function()
      vim.cmd('CopilotChatVsplit ' .. value)
    end, { nargs = '*', range = true })
  end

  -- Toggle between newbuffer and split
  utils.create_cmd('CopilotChatToggleLayout', function()
    if vim.g.copilot_chat_view_option == 'newbuffer' then
      vim.g.copilot_chat_view_option = 'split'
    else
      vim.g.copilot_chat_view_option = 'newbuffer'
    end
  end, { nargs = '*', range = true })
end

return M
