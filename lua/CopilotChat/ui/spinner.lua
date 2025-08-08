local notify = require('CopilotChat.notify')
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

---@class CopilotChat.ui.spinner.Spinner : Class
---@field bufnr number
---@field status string?
---@field model string?
---@field private index number
---@field private timer table
---@field private ns number
local Spinner = class(function(self, bufnr)
  self.bufnr = bufnr
  self.status = nil
  self.model = nil
  self.index = 1
  self.timer = nil
  self.ns = vim.api.nvim_create_namespace('copilot-chat-spinner')

  notify.listen(notify.STATUS, function(status)
    self.status = tostring(status)
  end)
end)

--- Set the model name to display
---@param model string
function Spinner:set_model(model)
  self.model = model
end

function Spinner:start()
  if self.timer then
    return
  end

  self.timer = vim.uv.new_timer()
  self.timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      if not utils.buf_valid(self.bufnr) or not self.timer then
        self:finish()
        return
      end

      local frame = spinner_frames[self.index]
      local display_text = ''
      
      if self.status then
        display_text = self.status
      end
      
      if self.model then
        if display_text ~= '' then
          display_text = display_text .. ' (' .. self.model .. ')'
        else
          display_text = self.model
        end
      end
      
      if display_text ~= '' then
        display_text = display_text .. ' ' .. frame
      else
        display_text = frame
      end

      vim.api.nvim_buf_set_extmark(self.bufnr, self.ns, math.max(0, vim.api.nvim_buf_line_count(self.bufnr) - 1), 0, {
        id = 1,
        hl_mode = 'combine',
        priority = 100,
        virt_text = {
          { display_text, 'CopilotChatStatus' },
        },
      })

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

  vim.api.nvim_buf_del_extmark(self.bufnr, self.ns, 1)
  
  -- Clear the model after finishing
  self.model = nil
end

return Spinner

