local Spinner = require('CopilotChat.spinner')
local class = require('CopilotChat.utils').class

local function create_buf()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, 'copilot-chat')
  vim.bo[bufnr].filetype = 'markdown'
  vim.treesitter.start(bufnr, 'markdown')
  return bufnr
end

local Chat = class(function(self, name)
  self.bufnr = create_buf()
  self.spinner = Spinner(self.bufnr, name)
end)

function Chat:valid()
  return vim.api.nvim_buf_is_valid(self.bufnr)
end

function Chat:append(str)
  if not self:valid() then
    return
  end

  local last_line, last_column = self:last()
  vim.api.nvim_buf_set_text(
    self.bufnr,
    last_line,
    last_column,
    last_line,
    last_column,
    vim.split(str, '\n')
  )

  return self:last()
end

function Chat:last()
  local last_line = vim.api.nvim_buf_line_count(self.bufnr) - 1
  local last_line_content = vim.api.nvim_buf_get_lines(self.bufnr, -2, -1, false)
  local last_column = #last_line_content[1]
  return last_line, last_column
end

function Chat:clear()
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, {})
end

return Chat
