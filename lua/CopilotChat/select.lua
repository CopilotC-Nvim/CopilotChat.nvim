---@class CopilotChat.select.Selection
---@field content string
---@field start_line number
---@field end_line number
---@field filename string
---@field filetype string
---@field bufnr number

local log = require('plenary.log')
local utils = require('CopilotChat.utils')

local M = {}

--- Use #selection instead
---@deprecated
function M.visual(_)
  log.warn('CopilotChat.select.visual is deprecated, use #selection instead')
  return nil
end

--- Use #selection instead
---@deprecated use #selection instead
function M.buffer(_)
  log.warn('CopilotChat.select.buffer is deprecated, use #selection instead')
  return nil
end

--- Use #selection instead
---@deprecated use #selection instead
function M.line(_)
  log.warn('CopilotChat.select.line is deprecated, use #selection instead')
  return nil
end

--- Use #selection instead
---@deprecated use #selection instead
function M.unnamed(_)
  log.warn('CopilotChat.select.unnamed is deprecated, use #selection instead')
  return nil
end

--- Get the marks used for selection
---@return string[]
function M.marks()
  local config = require('CopilotChat.config')
  local marks = { '<', '>' }
  if config.selection == 'unnamed' then
    marks = { '[', ']' }
  end
  return marks
end

--- Highlight selection in target buffer or clear it
---@param bufnr number
---@param clear boolean?
function M.highlight(bufnr, clear)
  local selection_ns = vim.api.nvim_create_namespace('copilot-chat-selection')
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    vim.api.nvim_buf_clear_namespace(buf, selection_ns, 0, -1)
  end

  if clear then
    return
  end

  local selection = M.get(bufnr)
  if not selection then
    return
  end

  vim.api.nvim_buf_set_extmark(selection.bufnr, selection_ns, selection.start_line - 1, 0, {
    hl_group = 'CopilotChatSelection',
    end_row = selection.end_line,
    strict = false,
  })
end

--- Get the selection from the target buffer
---@param bufnr number
---@return CopilotChat.select.Selection?
function M.get(bufnr)
  if not utils.buf_valid(bufnr) then
    return nil
  end

  local marks = M.marks()
  local start_line = unpack(vim.api.nvim_buf_get_mark(bufnr, marks[1]))
  local finish_line = unpack(vim.api.nvim_buf_get_mark(bufnr, marks[2]))
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

--- Sets the selection to specific lines in buffer or clears it
---@param bufnr number
---@param winnr number?
---@param start_line number?
---@param end_line number?
function M.set(bufnr, winnr, start_line, end_line)
  if not utils.buf_valid(bufnr) then
    return
  end

  local marks = M.marks()

  if not start_line or not end_line then
    for _, mark in ipairs(marks) do
      pcall(vim.api.nvim_buf_del_mark, bufnr, mark)
    end
    return
  end

  pcall(vim.api.nvim_buf_set_mark, bufnr, marks[1], start_line, 0, {})
  pcall(vim.api.nvim_buf_set_mark, bufnr, marks[2], end_line, 0, {})

  if winnr and vim.api.nvim_win_is_valid(winnr) then
    pcall(vim.api.nvim_win_set_cursor, winnr, { start_line, 0 })
  end
end

return M
