local utils = require('CopilotChat.utils')
local context = require('CopilotChat.context')
local M = {}

function M.setup()
  -- Show debug info
  vim.api.nvim_create_user_command('CopilotChatDebugInfo', function()
    -- Get the log file path
    local log_file_path = utils.get_log_file_path()

    -- Create a popup with the log file path
    local lines = {
      'If you are facing issues, run `:checkhealth CopilotChat` and share the output.',
      '',
      'Log file path:',
      '`' .. log_file_path .. '`',
      '',
    }

    local outline = context.build_outline(vim.api.nvim_get_current_buf())
    if outline then
      table.insert(lines, 'Current buffer outline:')
      table.insert(lines, '`' .. outline.filename .. '`')
      table.insert(lines, '```' .. outline.filetype)
      local outline_lines = vim.split(outline.content, '\n')
      for _, line in ipairs(outline_lines) do
        table.insert(lines, line)
      end
      table.insert(lines, '```')
    end

    local width = 0
    for _, line in ipairs(lines) do
      width = math.max(width, #line)
    end
    local height = math.min(vim.o.lines - 3, #lines)
    local opts = {
      title = 'CopilotChat.nvim Debug Info',
      relative = 'editor',
      width = width,
      height = height,
      row = (vim.o.lines - height) / 2 - 1,
      col = (vim.o.columns - width) / 2,
      style = 'minimal',
      border = 'rounded',
    }

    if not utils.is_stable() then
      opts.footer = "Press 'q' to close this window."
    end

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].syntax = 'markdown'
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false
    vim.treesitter.start(bufnr, 'markdown')

    local win = vim.api.nvim_open_win(bufnr, true, opts)
    vim.wo[win].wrap = true
    vim.wo[win].linebreak = true
    vim.wo[win].cursorline = true
    vim.wo[win].conceallevel = 2

    -- Bind 'q' to close the window
    vim.api.nvim_buf_set_keymap(
      bufnr,
      'n',
      'q',
      '<cmd>close<CR>',
      { noremap = true, silent = true }
    )
  end, { nargs = '*', range = true })
end

return M
