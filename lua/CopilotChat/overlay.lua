---@class CopilotChat.Overlay
---@field bufnr number
---@field valid fun(self: CopilotChat.Overlay)
---@field validate fun(self: CopilotChat.Overlay)
---@field show fun(self: CopilotChat.Overlay, text: string, filetype: string, syntax: string, winnr: number)
---@field restore fun(self: CopilotChat.Overlay, winnr: number, bufnr: number)
---@field delete fun(self: CopilotChat.Overlay)
---@field show_help fun(self: CopilotChat.Overlay, msg: string, offset: number)

local utils = require('CopilotChat.utils')
local class = utils.class

local Overlay = class(function(self, name, hl_ns, help, on_buf_create)
  self.hl_ns = hl_ns
  self.help = help
  self.on_buf_create = on_buf_create
  self.bufnr = nil

  self.buf_create = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].filetype = name
    vim.api.nvim_buf_set_name(bufnr, name)
    return bufnr
  end
end)

function Overlay:valid()
  return self.bufnr
    and vim.api.nvim_buf_is_valid(self.bufnr)
    and vim.api.nvim_buf_is_loaded(self.bufnr)
end

function Overlay:validate()
  if self:valid() then
    return
  end

  self.bufnr = self.buf_create(self)
  self.on_buf_create(self.bufnr)
end

function Overlay:show(text, filetype, syntax, winnr)
  self:validate()

  vim.api.nvim_win_set_buf(winnr, self.bufnr)

  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, vim.split(text, '\n'))
  vim.bo[self.bufnr].modifiable = false
  self:show_help(self.help, -1)
  vim.api.nvim_win_set_cursor(winnr, { vim.api.nvim_buf_line_count(self.bufnr), 0 })

  -- Dual mode with treesitter (for diffs for example)
  vim.api.nvim_win_set_hl_ns(winnr, self.hl_ns)
  local ok, parser = pcall(vim.treesitter.get_parser, self.bufnr, syntax)
  if ok and parser then
    vim.treesitter.start(self.bufnr, syntax)
    vim.bo[self.bufnr].syntax = filetype
  else
    vim.bo[self.bufnr].syntax = syntax
  end
end

function Overlay:restore(winnr, bufnr)
  self.current = nil
  vim.api.nvim_win_set_buf(winnr, bufnr or 0)
  vim.api.nvim_win_set_hl_ns(winnr, 0)
end

function Overlay:delete()
  if self:valid() then
    vim.api.nvim_buf_delete(self.bufnr, { force = true })
  end
end

function Overlay:show_help(msg, offset)
  if not msg then
    return
  end

  msg = vim.trim(msg)
  if msg == '' then
    return
  end

  self:validate()
  local help_ns = vim.api.nvim_create_namespace('copilot-chat-help')
  local line = vim.api.nvim_buf_line_count(self.bufnr) + offset
  vim.api.nvim_buf_set_extmark(self.bufnr, help_ns, math.max(0, line - 1), 0, {
    id = help_ns,
    hl_mode = 'combine',
    priority = 100,
    virt_lines = vim.tbl_map(function(t)
      return { { t, 'CopilotChatHelp' } }
    end, vim.split(msg, '\n')),
  })
end

return Overlay
