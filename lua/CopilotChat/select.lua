local M = {}

local function get_selection_lines(start, finish, mode)
  local start_line, start_col = start[2], start[3]
  local finish_line, finish_col = finish[2], finish[3]

  if start_line > finish_line then
    start_line, finish_line = finish_line, start_line
  end
  if start_col > finish_col then
    start_col, finish_col = finish_col, start_col
  end
  if finish_col == vim.v.maxcol or mode == 'V' then
    finish_col = #vim.api.nvim_buf_get_lines(0, finish_line - 1, finish_line, false)[1]
  end

  if mode == 'V' then
    return vim.api.nvim_buf_get_lines(0, start_line - 1, finish_line, false),
      start_line,
      1,
      finish_line,
      finish_col
  end

  if mode == '\22' then
    local lines = {}
    for i = start_line, finish_line do
      table.insert(
        lines,
        vim.api.nvim_buf_get_text(
          0,
          i - 1,
          math.min(start_col - 1, finish_col),
          i - 1,
          math.max(start_col - 1, finish_col),
          {}
        )[1]
      )
    end
    return lines, start_line, start_col, finish_line, finish_col
  end

  return vim.api.nvim_buf_get_text(
    0,
    start_line - 1,
    start_col - 1,
    finish_line - 1,
    finish_col,
    {}
  ),
    start_line,
    start_col,
    finish_line,
    finish_col
end

--- Select and process current visual selection
--- @return table|nil
function M.visual()
  local mode = vim.fn.mode()
  local start = vim.fn.getpos('v')
  local finish = vim.fn.getpos('.')

  if start[2] == finish[2] and start[3] == finish[3] then
    start = vim.fn.getpos("'<")
    finish = vim.fn.getpos("'>")

    if start[2] == finish[2] and start[3] == finish[3] then
      return nil
    end

    mode = 'v'
  else
    -- Exit visual mode
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<esc>', true, false, true), 'x', true)
  end

  local lines, start_row, start_col, end_row, end_col = get_selection_lines(start, finish, mode)
  local lines_content = table.concat(lines, '\n')
  if vim.trim(lines_content) == '' then
    return nil
  end

  return {
    buffer = vim.api.nvim_get_current_buf(),
    filetype = vim.bo.filetype,
    lines = lines_content,
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

--- Select and process current git diff
--- @param staged boolean @If true, it will return the staged changes
--- @return table|nil
function M.gitdiff(staged)
  local select_buffer = M.buffer()
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
