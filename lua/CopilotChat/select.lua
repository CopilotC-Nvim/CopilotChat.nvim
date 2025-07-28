---@class CopilotChat.select.Selection
---@field content string
---@field start_line number
---@field end_line number
---@field filename string
---@field filetype string
---@field bufnr number

local M = {}

--- Select and process current visual selection
--- @param source CopilotChat.source
--- @return CopilotChat.select.Selection|nil
function M.visual(source)
  local bufnr = source.bufnr
  local start_line = unpack(vim.api.nvim_buf_get_mark(bufnr, '<'))
  local finish_line = unpack(vim.api.nvim_buf_get_mark(bufnr, '>'))
  if start_line == 0 or finish_line == 0 then
    return nil
  end
  if start_line > finish_line then
    start_line, finish_line = finish_line, start_line
  end

  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, start_line - 1, finish_line, false)
  if not ok then
    return nil
  end
  local lines_content = table.concat(lines, '\n')
  if vim.trim(lines_content) == '' then
    return nil
  end

  return {
    content = lines_content,
    filename = vim.api.nvim_buf_get_name(bufnr),
    filetype = vim.bo[bufnr].filetype,
    start_line = start_line,
    end_line = finish_line,
    bufnr = bufnr,
  }
end

--- Select and process whole buffer
--- @param source CopilotChat.source
--- @return CopilotChat.select.Selection|nil
function M.buffer(source)
  local bufnr = source.bufnr
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if not lines or #lines == 0 then
    return nil
  end

  return {
    content = table.concat(lines, '\n'),
    filename = vim.api.nvim_buf_get_name(bufnr),
    filetype = vim.bo[bufnr].filetype,
    start_line = 1,
    end_line = #lines,
    bufnr = bufnr,
  }
end

--- Select and process current line
--- @param source CopilotChat.source
--- @return CopilotChat.select.Selection|nil
function M.line(source)
  local bufnr = source.bufnr
  local winnr = source.winnr
  local cursor = vim.api.nvim_win_get_cursor(winnr)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line then
    return nil
  end

  return {
    content = line,
    filename = vim.api.nvim_buf_get_name(bufnr),
    filetype = vim.bo[bufnr].filetype,
    start_line = cursor[1],
    end_line = cursor[1],
    bufnr = bufnr,
  }
end

--- Select and process contents of unnamed register ("). This register contains last deleted, changed or yanked content.
--- @param source CopilotChat.source
--- @return CopilotChat.select.Selection|nil
function M.unnamed(source)
  local bufnr = source.bufnr
  local start_line = unpack(vim.api.nvim_buf_get_mark(bufnr, '['))
  local finish_line = unpack(vim.api.nvim_buf_get_mark(bufnr, ']'))
  if start_line == 0 or finish_line == 0 then
    return nil
  end
  if start_line > finish_line then
    start_line, finish_line = finish_line, start_line
  end

  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, start_line - 1, finish_line, false)
  if not ok then
    return nil
  end
  local lines_content = table.concat(lines, '\n')
  if vim.trim(lines_content) == '' then
    return nil
  end

  return {
    content = lines_content,
    filename = vim.api.nvim_buf_get_name(bufnr),
    filetype = vim.bo[bufnr].filetype,
    start_line = start_line,
    end_line = finish_line,
    bufnr = bufnr,
  }
end

return M
