local utils = require('CopilotChat.utils')

local M = {}

local default_prompts = {
  Explain = 'Explain how it works.',
  Tests = 'Briefly how selected code works then generate unit tests.',
}

_COPILOT_CHAT_GLOBAL_CONFIG = {}

-- Set up the plugin
---@param options (table | nil)
--       - show_help: ('yes' | 'no') default: 'yes'.
--       - disable_extra_info: ('yes' | 'no') default: 'yes'.
--       - prompts: (table?) default: default_prompts.
--       - debug: (boolean?) default: false.
M.setup = function(options)
  vim.g.copilot_chat_show_help = options and options.show_help or 'yes'
  vim.g.copilot_chat_disable_separators = options and options.disable_extra_info or 'yes'
  vim.g.copilot_chat_proxy = options and options.proxy or ''
  local debug = options and options.debug or false
  _COPILOT_CHAT_GLOBAL_CONFIG.debug = debug

  -- Merge the provided prompts with the default prompts
  local prompts = vim.tbl_extend('force', default_prompts, options and options.prompts or {})
  vim.g.copilot_chat_user_prompts = prompts

  --  Loop through merged table and generate commands based on keys.
  for key, value in pairs(prompts) do
    utils.create_cmd('CopilotChat' .. key, function()
      vim.cmd('CopilotChat ' .. value)
    end, { nargs = '*', range = true })
  end

  -- Show debug info
  utils.create_cmd('CopilotChatDebugInfo', function()
    -- Get the log file path
    local log_file_path = utils.get_log_file_path()

    -- Get the rplugin path
    local rplugin_path = utils.get_remote_plugins_path()

    -- Create a popup with the log file path
    local lines = {
      'CopilotChat.nvim Info:',
      '- Log file path: ' .. log_file_path,
      '- Rplugin path: ' .. rplugin_path,
      'If you are facing issues, run `:checkhealth CopilotChat` and share the output.',
      'There is a common issue is "Ambiguous use of user-defined command". Please check the pin issues on the repository.',
      'Press `q` to close this window.',
      'Press `?` to open the rplugin file.',
    }

    local width = 0
    for _, line in ipairs(lines) do
      width = math.max(width, #line)
    end
    local height = #lines
    local opts = {
      relative = 'editor',
      width = width + 4,
      height = height + 2,
      row = (vim.o.lines - height) / 2 - 1,
      col = (vim.o.columns - width) / 2,
      style = 'minimal',
      border = 'rounded',
    }
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_open_win(bufnr, true, opts)

    -- Bind 'q' to close the window
    vim.api.nvim_buf_set_keymap(
      bufnr,
      'n',
      'q',
      '<cmd>close<CR>',
      { noremap = true, silent = true }
    )

    -- Bind `?` to open remote plugin detail
    vim.api.nvim_buf_set_keymap(
      bufnr,
      'n',
      '?',
      -- Close the current window and open the rplugin file
      '<cmd>close<CR><cmd>edit '
        .. rplugin_path
        .. '<CR>',
      { noremap = true, silent = true }
    )
  end, {
    nargs = '*',
    range = true,
  })

  utils.log_info(
    'Execute ":UpdateRemotePlugins" and restart Neovim before starting a chat with Copilot.'
  )
  utils.log_info('If issues arise, run ":healthcheck" and share the output.')
end

return M
