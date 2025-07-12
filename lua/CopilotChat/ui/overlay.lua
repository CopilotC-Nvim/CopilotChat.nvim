local utils = require('CopilotChat.utils')
local class = utils.class

---@class CopilotChat.ui.overlay.Overlay : Class
---@field bufnr number?
---@field protected name string
---@field protected help string
---@field private cursor integer[]?
---@field private on_buf_create fun(bufnr: number)
---@field private on_hide? fun(bufnr: number)
---@field private help_ns number
---@field private hl_ns number
local Overlay = class(function(self, name, help, on_buf_create)
  self.bufnr = nil
  self.name = name
  self.help = help
  self.cursor = nil
  self.on_buf_create = on_buf_create
  self.on_hide = nil

  self.help_ns = vim.api.nvim_create_namespace('copilot-chat-help')
end)

--- Show the overlay buffer
---@param text string
---@param winnr number
---@param filetype? string
---@param syntax string?
---@param on_show? fun(bufnr: number)
---@param on_hide? fun(bufnr: number)
function Overlay:show(text, winnr, filetype, syntax, on_show, on_hide)
  if not text or text == '' then
    return
  end

  self:validate()
  text = text .. '\n'

  self.cursor = vim.api.nvim_win_get_cursor(winnr)
  vim.api.nvim_win_set_buf(winnr, self.bufnr)
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, vim.split(text, '\n'))
  vim.bo[self.bufnr].modifiable = false
  self:show_help(self.help, -1)
  vim.api.nvim_win_set_cursor(winnr, { 1, 0 })

  filetype = filetype or 'markdown'
  syntax = syntax or filetype

  -- Dual mode with treesitter (for diffs for example)
  if filetype == syntax then
    vim.bo[self.bufnr].filetype = filetype
  else
    local ok, parser = pcall(vim.treesitter.get_parser, self.bufnr, syntax)
    if ok and parser then
      vim.treesitter.start(self.bufnr, syntax)
      vim.bo[self.bufnr].syntax = filetype
    else
      vim.bo[self.bufnr].syntax = syntax
    end
  end

  if on_show then
    on_show(self.bufnr)
  end

  self.on_hide = on_hide
end

--- Delete the overlay buffer
function Overlay:delete()
  if self:valid() then
    vim.api.nvim_buf_delete(self.bufnr, { force = true })
  end
end

--- Create the overlay buffer
---@return number
---@protected
function Overlay:create()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].filetype = self.name
  vim.bo[bufnr].modifiable = false
  vim.api.nvim_buf_set_name(bufnr, self.name)
  return bufnr
end

--- Check if the overlay buffer is valid
---@return boolean
---@protected
function Overlay:valid()
  return utils.buf_valid(self.bufnr)
end

--- Validate the overlay buffer
---@protected
function Overlay:validate()
  if self:valid() then
    return
  end

  self.bufnr = self:create()
  if self.on_buf_create then
    self.on_buf_create(self.bufnr)
  end
end

--- Restore the original buffer
---@param winnr number
---@param bufnr number?
---@protected
function Overlay:restore(winnr, bufnr)
  bufnr = bufnr or 0

  if self.on_hide then
    self.on_hide(self.bufnr)
  end

  vim.api.nvim_win_set_buf(winnr, bufnr)

  if self.cursor then
    vim.api.nvim_win_set_cursor(winnr, self.cursor)
  end

  -- Manually trigger BufEnter event as nvim_win_set_buf does not trigger it
  vim.schedule(function()
    vim.cmd(string.format('doautocmd <nomodeline> BufEnter %s', bufnr))
  end)
end

--- Show help message in the overlay
---@param msg string?
---@param offset number?
---@protected
function Overlay:show_help(msg, offset)
  if not msg or msg == '' then
    vim.api.nvim_buf_del_extmark(self.bufnr, self.help_ns, 1)
    return
  end

  self:validate()
  local line = vim.api.nvim_buf_line_count(self.bufnr) + (offset or 0)
  vim.api.nvim_buf_set_extmark(self.bufnr, self.help_ns, math.max(0, line - 1), 0, {
    id = 1,
    hl_mode = 'combine',
    priority = 100,
    virt_lines = vim.tbl_map(function(t)
      return { { t, 'CopilotChatHelp' } }
    end, vim.split(msg, '\n')),
  })
end

return Overlay
