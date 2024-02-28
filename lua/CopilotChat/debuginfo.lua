local utils = require('CopilotChat.utils')
local M = {}

function M.setup()
  -- Show debug info
  vim.api.nvim_create_user_command('CopilotChatDebugInfo', function()
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
  end, { nargs = '*', range = true })
end

return M
