---@class CopilotChat.select.selection.diagnostic
---@field content string
---@field start_line number
---@field end_line number
---@field severity string

---@class CopilotChat.select.selection
---@field content string
---@field start_line number
---@field end_line number
---@field filename string
---@field filetype string
---@field bufnr number
---@field diagnostics table<CopilotChat.select.selection.diagnostic>?

local utils = require('CopilotChat.utils')

local M = {}

--- Get diagnostics in a given range
--- @param bufnr number
--- @param start_line number
--- @param end_line number
--- @return table<CopilotChat.select.selection.diagnostic>|nil
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
        severity = severity[diagnostic.severity],
        content = diagnostic.message,
        start_line = lnum,
        end_line = diagnostic.end_lnum and diagnostic.end_lnum + 1 or lnum,
      })
    end
  end

  return #range_diagnostics > 0 and range_diagnostics or nil
end

--- Select and process current visual selection
--- @param source CopilotChat.source
--- @return CopilotChat.select.selection|nil
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
    filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':p:.'),
    filetype = vim.bo[bufnr].filetype,
    start_line = start_line,
    end_line = finish_line,
    bufnr = bufnr,
    diagnostics = get_diagnostics_in_range(bufnr, start_line, finish_line),
  }
end

--- Select and process whole buffer
--- @param source CopilotChat.source
--- @return CopilotChat.select.selection|nil
function M.buffer(source)
  local bufnr = source.bufnr
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if not lines or #lines == 0 then
    return nil
  end

  local out = {
    content = table.concat(lines, '\n'),
    filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':p:.'),
    filetype = vim.bo[bufnr].filetype,
    start_line = 1,
    end_line = #lines,
    bufnr = bufnr,
  }

  out.diagnostics = get_diagnostics_in_range(bufnr, out.start_line, out.end_line)
  return out
end

--- Select and process current line
--- @param source CopilotChat.source
--- @return CopilotChat.select.selection|nil
function M.line(source)
  local bufnr = source.bufnr
  local winnr = source.winnr
  local cursor = vim.api.nvim_win_get_cursor(winnr)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
  if not line then
    return nil
  end

  local out = {
    content = line,
    filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':p:.'),
    filetype = vim.bo[bufnr].filetype,
    start_line = cursor[1],
    end_line = cursor[1],
    bufnr = bufnr,
  }

  out.diagnostics = get_diagnostics_in_range(bufnr, out.start_line, out.end_line)
  return out
end

--- Select and process contents of unnamed register ("). This register contains last deleted, changed or yanked content.
--- @param source CopilotChat.source
--- @return CopilotChat.select.selection|nil
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
    filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':p:.'),
    filetype = vim.bo[bufnr].filetype,
    start_line = start_line,
    end_line = finish_line,
    bufnr = bufnr,
    diagnostics = get_diagnostics_in_range(bufnr, start_line, finish_line),
  }
end

function M.clipboard()
  utils.deprecate('selection.clipboard', 'context.register:+')
  return nil
end

function M.gitdiff()
  utils.deprecate('selection.gitdiff', 'context.gitdiff')
  return nil
end

return M
