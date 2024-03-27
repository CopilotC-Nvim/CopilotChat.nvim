---@class CopilotChat.Spinner
---@field bufnr number
---@field set fun(self: CopilotChat.Spinner, text: string, virt_line: boolean)
---@field start fun(self: CopilotChat.Spinner)
---@field finish fun(self: CopilotChat.Spinner)

local utils = require('CopilotChat.utils')
local class = utils.class

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

function Spinner:start()
  if self.timer then
    return
  end

  self.timer = vim.loop.new_timer()
  self.timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      if
        not vim.api.nvim_buf_is_valid(self.bufnr)
        or not vim.api.nvim_buf_is_loaded(self.bufnr)
        or not self.timer
      then
        self:finish()
        return
      end

      vim.api.nvim_buf_set_extmark(
        self.bufnr,
        self.ns,
        math.max(0, vim.api.nvim_buf_line_count(self.bufnr) - 1),
        0,
        {
          id = self.ns,
          hl_mode = 'combine',
          priority = 100,
          virt_text = vim.tbl_map(function(t)
            return { t, 'CursorColumn' }
          end, vim.split(spinner_frames[self.index], '\n')),
        }
      )

      self.index = self.index % #spinner_frames + 1
    end)
  )
end

function Spinner:finish()
  if not self.timer then
    return
  end

  local timer = self.timer
  self.timer = nil

  timer:stop()
  timer:close()

  vim.api.nvim_buf_del_extmark(self.bufnr, self.ns, self.ns)
end

return Spinner
