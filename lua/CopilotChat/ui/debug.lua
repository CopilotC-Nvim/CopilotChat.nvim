local async = require('plenary.async')
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

  local buf = context.buffer(0)
  if buf then
    if buf.symbols then
      table.insert(lines, 'Current buffer symbols:')
      for _, symbol in ipairs(buf.symbols) do
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
      table.insert(lines, '')
    end

    table.insert(lines, 'Current buffer outline:')
    table.insert(lines, '`' .. buf.filename .. '`')
    table.insert(lines, '```' .. buf.filetype)
    local outline_lines = vim.split(buf.outline or buf.content, '\n')
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

function Debug:close()
  if not self.winnr then
    return
  end

  if vim.api.nvim_win_is_valid(self.winnr) then
    vim.api.nvim_win_close(self.winnr, true)
  end

  self.winnr = nil
end

function Debug:open()
  self:validate()
  self:close()

  async.run(function()
    local lines = build_debug_info()
    async.util.scheduler()

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
    self.winnr = vim.api.nvim_open_win(self.bufnr, true, win_opts)
    vim.wo[self.winnr].wrap = true
    vim.wo[self.winnr].linebreak = true
    vim.wo[self.winnr].cursorline = true
    vim.wo[self.winnr].conceallevel = 2

    -- Show content
    self:show(table.concat(lines, '\n'), self.winnr, 'markdown')
    vim.api.nvim_win_set_cursor(self.winnr, { 1, 0 })
  end)
end

return Debug
