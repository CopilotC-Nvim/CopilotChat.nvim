local M = {}

local function get_selection_lines(bufnr, start_line, start_col, finish_line, finish_col, full_line)
  if start_line == finish_line and start_col == finish_col then
    return nil
  end

  if start_line > finish_line or (start_line == finish_line and start_col > finish_col) then
    start_line, finish_line = finish_line, start_line
    start_col, finish_col = finish_col, start_col
  end

  if full_line then
    start_col = 1
  end

  local finish_line_len = #vim.api.nvim_buf_get_lines(bufnr, finish_line - 1, finish_line, false)[1]
  if finish_col > finish_line_len or full_line then
    finish_col = finish_line_len
  end

  local lines =
    vim.api.nvim_buf_get_text(bufnr, start_line - 1, start_col - 1, finish_line - 1, finish_col, {})

  local lines_content = table.concat(lines, '\n')
  if vim.trim(lines_content) == '' then
    return nil
  end

  return {
    lines = lines_content,
    start_row = start_line,
    start_col = start_col,
    end_row = finish_line,
    end_col = finish_col,
  }
end

--- Select and process current visual selection
--- @param source CopilotChat.config.source
--- @return CopilotChat.config.selection|nil
function M.visual(source)
  local bufnr = source.bufnr

  local start_line, start_col = unpack(vim.api.nvim_buf_get_mark(bufnr, '<'))
  local finish_line, finish_col = unpack(vim.api.nvim_buf_get_mark(bufnr, '>'))
  start_col = start_col + 1
  finish_col = finish_col + 1
  return get_selection_lines(bufnr, start_line, start_col, finish_line, finish_col, false)
end

--- Select and process contents of unnamed register ('"')
--- @return CopilotChat.config.selection|nil
function M.unnamed()
  local lines = vim.fn.getreg('"')

  if not lines or lines == '' then
    return nil
  end

  return {
    lines = lines,
  }
end

--- Select and process whole buffer
--- @param source CopilotChat.config.source
--- @return CopilotChat.config.selection|nil
function M.buffer(source)
  local bufnr = source.bufnr
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  if not lines or #lines == 0 then
    return nil
  end

  return {
    lines = table.concat(lines, '\n'),
    start_row = 1,
    start_col = 1,
    end_row = #lines,
    end_col = #lines[#lines],
  }
end

--- Select and process current line
--- @param source CopilotChat.config.source
--- @return CopilotChat.config.selection|nil
function M.line(source)
  local bufnr = source.bufnr
  local winnr = source.winnr
  local cursor = vim.api.nvim_win_get_cursor(winnr)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]

  if not line then
    return nil
  end

  return {
    lines = line,
    start_row = cursor[1],
    start_col = 1,
    end_row = cursor[1],
    end_col = #line,
  }
end

--- Select whole buffer and find diagnostics
--- It uses the built-in LSP client in Neovim to get the diagnostics.
--- @param source CopilotChat.config.source
--- @return CopilotChat.config.selection|nil
function M.diagnostics(source)
  local bufnr = source.bufnr
  local winnr = source.winnr
  local select_buffer = M.buffer(source)
  if not select_buffer then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(winnr)
  local line_diagnostics = vim.lsp.diagnostic.get_line_diagnostics(bufnr, cursor[1] - 1)

  if #line_diagnostics == 0 then
    return nil
  end

  local diagnostics = {}
  for _, diagnostic in ipairs(line_diagnostics) do
    table.insert(diagnostics, diagnostic.message)
  end

  local result = table.concat(diagnostics, '. ')
  result = result:gsub('^%s*(.-)%s*$', '%1'):gsub('\n', ' ')

  local file_name = vim.api.nvim_buf_get_name(bufnr)
  select_buffer.prompt_extra = file_name .. ':' .. cursor[1] .. '. ' .. result
  return select_buffer
end

--- Select and process current git diff
--- @param source CopilotChat.config.source
--- @param staged boolean @If true, it will return the staged changes
--- @return CopilotChat.config.selection|nil
function M.gitdiff(source, staged)
  local select_buffer = M.buffer(source)
  if not select_buffer then
    return nil
  end

  local cmd = 'git diff --no-color --no-ext-diff' .. (staged and ' --staged' or '')
  local handle = io.popen(cmd)
  if not handle then
    return nil
  end

  local result = handle:read('*a')
  handle:close()

  if not result or result == '' then
    return nil
  end

  select_buffer.filetype = 'diff'
  select_buffer.lines = result
  return select_buffer
end

return M
