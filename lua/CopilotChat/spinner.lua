---@class CopilotChat.Spinner
---@field bufnr number
---@field set fun(self: CopilotChat.Spinner, text: string, offset: number)
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

local Spinner = class(function(self, bufnr, title)
  self.ns = vim.api.nvim_create_namespace('copilot-spinner')
  self.bufnr = bufnr
  self.title = title
  self.timer = nil
  self.index = 1
end)

function Spinner:set(text, offset)
  offset = offset or 0

  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(self.bufnr) then
      self:finish()
      return
    end

    local line = vim.api.nvim_buf_line_count(self.bufnr) - 1 + offset
    line = math.max(0, line)

    local opts = {
      id = self.ns,
      hl_mode = 'combine',
      priority = 100,
      virt_text = vim.tbl_map(function(t)
        return { t, 'CursorColumn' }
      end, vim.split(text, '\n')),
    }

    -- stable do not supports virt_text_pos
    if not is_stable() then
      opts.virt_text_pos = offset ~= 0 and 'inline' or 'eol'
    end

    vim.api.nvim_buf_set_extmark(self.bufnr, self.ns, line, 0, opts)
  end)
end

function Spinner:start()
  self.timer = vim.loop.new_timer()
  self.timer:start(0, 100, function()
    self:set(spinner_frames[self.index])
    self.index = self.index % #spinner_frames + 1
  end)
end

function Spinner:finish()
  if self.timer then
    self.timer:stop()
    self.timer:close()
    self.timer = nil

    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(self.bufnr) then
        return
      end

      vim.api.nvim_buf_del_extmark(self.bufnr, self.ns, self.ns)
      vim.notify('Done!', vim.log.levels.INFO, { title = self.title })
    end)
  end
end

return Spinner
