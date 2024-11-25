local log = require('plenary.log')
local utils = require('CopilotChat.utils')
local context = require('CopilotChat.context')
local Overlay = require('CopilotChat.ui.overlay')
local class = utils.class

---@return table<string>
local function build_debug_info()
  local lines = {
    'If you are facing issues, run `:checkhealth CopilotChat` and share the output.',
    '',
    'Log file path:',
    '`' .. log.logfile .. '`',
    '',
    'Data directory:',
    '`' .. vim.fn.stdpath('data') .. '`',
    '',
    'Config directory:',
    '`' .. utils.config_path() .. '`',
    '',
    'Temp directory:',
    '`' .. vim.fn.fnamemodify(os.tmpname(), ':h') .. '`',
    '',
  }

  local buf = context.buffer(vim.api.nvim_get_current_buf())
  local outline = buf and context.outline(buf.content, buf.filename, buf.filetype)
  if outline then
    table.insert(lines, 'Current buffer symbols:')
    for _, symbol in ipairs(outline.symbols) do
      table.insert(
        lines,
        string.format(
          '%s `%s` (%s %s %s %s) - `%s`',
          symbol.type,
          symbol.name,
          symbol.start_row,
          symbol.start_col,
          symbol.end_row,
          symbol.end_col,
          symbol.signature
        )
      )
    end
    table.insert(lines, 'Current buffer outline:')
    table.insert(lines, '`' .. outline.filename .. '`')
    table.insert(lines, '```' .. outline.filetype)
    local outline_lines = vim.split(outline.content, '\n')
    for _, line in ipairs(outline_lines) do
      table.insert(lines, line)
    end
    table.insert(lines, '```')
  end

  local files = context.files()
  if files then
    table.insert(lines, 'Current workspace file map:')
    table.insert(lines, '```text')
    for _, file in ipairs(files) do
      for _, line in ipairs(vim.split(file.content, '\n')) do
        table.insert(lines, line)
      end
    end
    table.insert(lines, '```')
  end

  return lines
end

---@class CopilotChat.ui.Debug : CopilotChat.ui.Overlay
local Debug = class(function(self)
  Overlay.init(self, 'copilot-debug', nil, function(bufnr)
    vim.keymap.set('n', 'q', function()
      vim.api.nvim_win_close(0, true)
    end, { buffer = bufnr })
  end)
end, Overlay)

function Debug:open()
  self:validate()

  local lines = build_debug_info()
  local height = math.min(vim.o.lines - 3, #lines)
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, #line)
  end

  local win_opts = {
    title = 'CopilotChat.nvim Debug Info',
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    zindex = 50,
  }

  if not utils.is_stable() then
    win_opts.footer = "Press 'q' to close this window."
  end

  -- Open window
  local winnr = vim.api.nvim_open_win(self.bufnr, true, win_opts)
  vim.wo[winnr].wrap = true
  vim.wo[winnr].linebreak = true
  vim.wo[winnr].cursorline = true
  vim.wo[winnr].conceallevel = 2

  -- Show content
  self:show(table.concat(lines, '\n'), winnr, 'markdown')
  vim.api.nvim_win_set_cursor(winnr, { 1, 0 })
end

return Debug
