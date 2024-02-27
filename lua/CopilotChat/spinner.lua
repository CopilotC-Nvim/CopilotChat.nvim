local class = require('CopilotChat.utils').class

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

    vim.api.nvim_buf_set_extmark(self.bufnr, self.ns, line, 0, {
      id = self.ns,
      hl_mode = 'combine',
      priority = 100,
      virt_text_pos = offset ~= 0 and 'inline' or 'eol',
      virt_text = vim.tbl_map(function(t)
        return { t, 'Comment' }
      end, vim.split(text, '\n')),
    })
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
