---@class CopilotChat.Spinner
---@field bufnr number
---@field set fun(self: CopilotChat.Spinner, text: string, virt_line: boolean)
---@field start fun(self: CopilotChat.Spinner)
---@field finish fun(self: CopilotChat.Spinner)

local utils = require('CopilotChat.utils')
local class = utils.class
local is_stable = utils.is_stable

local spinner_frames = {
  '⠋',
  '⠙',
  '⠹',
  '⠸',
  '⠼',
  '⠴',
  '⠦',
  '⠧',
  '⠇',
  '⠏',
}

local Spinner = class(function(self, bufnr, ns, title)
  self.ns = ns
  self.bufnr = bufnr
  self.title = title
  self.timer = nil
  self.index = 1
end)

function Spinner:set(text, virt_line)
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(self.bufnr) then
      self:finish()
      return
    end

    local line = vim.api.nvim_buf_line_count(self.bufnr) - 1

    local opts = {
      id = self.ns,
      hl_mode = 'combine',
      priority = 100,
    }

    if virt_line then
      line = line - 1
      opts.virt_lines_leftcol = true
      opts.virt_lines = vim.tbl_map(function(t)
        return { { '| ' .. t, 'DiagnosticInfo' } }
      end, vim.split(text, '\n'))
    else
      opts.virt_text = vim.tbl_map(function(t)
        return { t, 'CursorColumn' }
      end, vim.split(text, '\n'))
    end

    vim.api.nvim_buf_set_extmark(self.bufnr, self.ns, math.max(0, line), 0, opts)
  end)
end

function Spinner:start()
  if self.timer then
    return
  end

  self.timer = vim.loop.new_timer()
  self.timer:start(0, 100, function()
    self:set(spinner_frames[self.index])
    self.index = self.index % #spinner_frames + 1
  end)
end

function Spinner:finish(msg, offset)
  vim.schedule(function()
    if not self.timer then
      return
    end

    self.timer:stop()
    self.timer:close()
    self.timer = nil

    if not vim.api.nvim_buf_is_valid(self.bufnr) then
      return
    end

    if msg then
      self:set(msg, offset)
    else
      vim.api.nvim_buf_del_extmark(self.bufnr, self.ns, self.ns)
      vim.notify('Done!', vim.log.levels.INFO, { title = self.title })
    end
  end)
end

return Spinner
