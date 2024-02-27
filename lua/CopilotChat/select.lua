local M = {}

local function get_selection_lines(start, finish, full_lines)
  local start_line, start_col = start[2], start[3]
  local finish_line, finish_col = finish[2], finish[3]

  if start_line > finish_line or (start_line == finish_line and start_col > finish_col) then
    start_line, start_col, finish_line, finish_col = finish_line, finish_col, start_line, start_col
  end

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, finish_line, false)
  if #lines == 0 then
    return nil, 0, 0, 0, 0
  end

  if full_lines then
    start_col = 0
    finish_col = #lines[#lines]
  else
    lines[#lines] = string.sub(lines[#lines], 1, finish_col)
    lines[1] = string.sub(lines[1], start_col)
  end

  return table.concat(lines, '\n'), start_line, start_col, finish_line, finish_col
end

--- Select and process current visual selection
--- @return table|nil
function M.visual()
  local mode = vim.fn.mode()
  if mode:lower() ~= 'v' then
    return nil
  end

  local start = vim.fn.getpos('v')
  local finish = vim.fn.getpos('.')

  -- Switch to vim normal mode from visual mode
  vim.api.nvim_feedkeys('<Esc>', 'n', true)

  local lines, start_row, start_col, end_row, end_col =
    get_selection_lines(start, finish, mode == 'V')

  return {
    buffer = vim.api.nvim_get_current_buf(),
    filetype = vim.bo.filetype,
    lines = lines,
    start_row = start_row,
    start_col = start_col,
    end_row = end_row,
    end_col = end_col,
  }
end

--- Select and process contents of unnamed register ('"')
--- @return table|nil
function M.unnamed()
  local lines = vim.fn.getreg('"')

  if not lines or lines == '' then
    return nil
  end

  return {
    buffer = vim.api.nvim_get_current_buf(),
    filetype = vim.bo.filetype,
    lines = lines,
  }
end

--- Select and process whole buffer
--- @return table|nil
function M.buffer()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

  if not lines or #lines == 0 then
    return nil
  end

  return {
    buffer = vim.api.nvim_get_current_buf(),
    filetype = vim.bo.filetype,
    lines = table.concat(lines, '\n'),
    start_row = 1,
    start_col = 0,
    end_row = #lines,
    end_col = #lines[#lines],
  }
end

--- Select and process current line
--- @return table|nil
function M.line()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()

  if not line or line == '' then
    return nil
  end

  return {
    buffer = vim.api.nvim_get_current_buf(),
    filetype = vim.bo.filetype,
    lines = line,
    start_row = cursor[1],
    start_col = 0,
    end_row = cursor[1],
    end_col = #line,
  }
end

--- Select whole buffer and find diagnostics
--- It uses the built-in LSP client in Neovim to get the diagnostics.
--- @return table|nil
function M.diagnostics()
  local select_buffer = M.buffer()
  if not select_buffer then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_diagnostics = vim.lsp.diagnostic.get_line_diagnostics(0, cursor[1] - 1)

  if #line_diagnostics == 0 then
    return nil
  end

  local diagnostics = {}
  for _, diagnostic in ipairs(line_diagnostics) do
    table.insert(diagnostics, diagnostic.message)
  end

  local result = table.concat(diagnostics, '. ')
  result = result:gsub('^%s*(.-)%s*$', '%1'):gsub('\n', ' ')

  local file_name = vim.api.nvim_buf_get_name(0)
  select_buffer.prompt_extra = file_name .. ':' .. cursor[1] .. '. ' .. result
  return select_buffer
end

return M
