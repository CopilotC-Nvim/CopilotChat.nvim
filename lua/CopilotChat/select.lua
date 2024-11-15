local M = {}

local function get_diagnostics_in_range(bufnr, start_line, end_line)
  local diagnostics = vim.diagnostic.get(bufnr)
  local range_diagnostics = {}
  local severity = {
    [1] = 'ERROR',
    [2] = 'WARNING',
    [3] = 'INFORMATION',
    [4] = 'HINT',
  }

  for _, diagnostic in ipairs(diagnostics) do
    local lnum = diagnostic.lnum + 1
    if lnum >= start_line and lnum <= end_line then
      table.insert(range_diagnostics, {
        message = diagnostic.message,
        severity = severity[diagnostic.severity],
        start_row = lnum,
        start_col = diagnostic.col + 1,
        end_row = lnum,
        end_col = diagnostic.end_col and (diagnostic.end_col + 1) or diagnostic.col + 1,
      })
    end
  end

  return #range_diagnostics > 0 and range_diagnostics or nil
end

local function get_selection_lines(bufnr, start_line, start_col, finish_line, finish_col, full_line)
  -- Exit if no actual selection
  if start_line == finish_line and start_col == finish_col then
    return nil
  end

  -- Get line lengths before swapping
  local function get_line_length(line)
    return #vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]
  end

  -- Swap positions if selection is backwards
  if start_line > finish_line or (start_line == finish_line and start_col > finish_col) then
    start_line, finish_line = finish_line, start_line
    start_col, finish_col = finish_col, start_col
  end

  -- Handle full line selection
  if full_line then
    start_col = 1
    finish_col = get_line_length(finish_line)
  end

  -- Ensure columns are within valid bounds
  start_col = math.max(1, math.min(start_col, get_line_length(start_line)))
  finish_col = math.max(start_col, math.min(finish_col, get_line_length(finish_line)))

  -- Get selected text
  local ok, lines = pcall(
    vim.api.nvim_buf_get_text,
    bufnr,
    start_line - 1,
    start_col - 1,
    finish_line - 1,
    finish_col,
    {}
  )
  if not ok then
    return nil
  end

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

--- Select and process whole buffer
--- @param source CopilotChat.config.source
--- @return CopilotChat.config.selection|nil
function M.buffer(source)
  local bufnr = source.bufnr
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  if not lines or #lines == 0 then
    return nil
  end

  local out = {
    lines = table.concat(lines, '\n'),
    start_row = 1,
    start_col = 1,
    end_row = #lines,
    end_col = #lines[#lines],
  }

  out.diagnostics = get_diagnostics_in_range(bufnr, out.start_row, out.end_row)
  return out
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

  local out = {
    lines = line,
    start_row = cursor[1],
    start_col = 1,
    end_row = cursor[1],
    end_col = #line,
  }

  out.diagnostics = get_diagnostics_in_range(bufnr, out.start_row, out.end_row)
  return out
end

--- Select and process contents of unnamed register ("). This register contains last deleted, changed or yanked content.
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

--- Select and process contents of plus register (+). This register is synchronized with system clipboard.
--- @return CopilotChat.config.selection|nil
function M.clipboard()
  local lines = vim.fn.getreg('+')

  if not lines or lines == '' then
    return nil
  end

  return {
    lines = lines,
  }
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

  local bufname = vim.api.nvim_buf_get_name(source.bufnr)
  local file_path = bufname:gsub('^%w+://', '')
  local dir = vim.fn.fnamemodify(file_path, ':h')
  if not dir or dir == '' then
    return nil
  end
  dir = dir:gsub('.git$', '')

  local cmd = 'git -C ' .. dir .. ' diff --no-color --no-ext-diff' .. (staged and ' --staged' or '')
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
