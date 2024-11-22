local Overlay = require('CopilotChat.ui.overlay')
local utils = require('CopilotChat.utils')
local class = utils.class

---@class CopilotChat.ui.Diff.Diff
---@field change string
---@field reference string
---@field filename string
---@field filetype string
---@field start_line number
---@field end_line number
---@field bufnr number?

---@class CopilotChat.ui.Diff : CopilotChat.ui.Overlay
---@field hl_ns number
---@field diff CopilotChat.ui.Diff.Diff?
local Diff = class(function(self, help, on_buf_create)
  Overlay.init(self, 'copilot-diff', help, on_buf_create)
  self.hl_ns = vim.api.nvim_create_namespace('copilot-chat-highlights')
  vim.api.nvim_set_hl(self.hl_ns, '@diff.plus', { bg = utils.blend_color('DiffAdd', 20) })
  vim.api.nvim_set_hl(self.hl_ns, '@diff.minus', { bg = utils.blend_color('DiffDelete', 20) })
  vim.api.nvim_set_hl(self.hl_ns, '@diff.delta', { bg = utils.blend_color('DiffChange', 20) })

  self.diff = nil
end, Overlay)

---@param diff CopilotChat.ui.Diff.Diff
---@param winnr number
function Diff:show(diff, winnr)
  self.diff = diff
  self:validate()
  vim.api.nvim_win_set_hl_ns(winnr, self.hl_ns)

  Overlay.show(
    self,
    tostring(vim.diff(diff.reference, diff.change, {
      result_type = 'unified',
      ignore_blank_lines = true,
      ignore_whitespace = true,
      ignore_whitespace_change = true,
      ignore_whitespace_change_at_eol = true,
      ignore_cr_at_eol = true,
      algorithm = 'myers',
      ctxlen = #diff.reference,
    })),
    winnr,
    diff.filetype,
    'diff'
  )
end

---@param winnr number
---@param bufnr number
function Diff:restore(winnr, bufnr)
  Overlay.restore(self, winnr, bufnr)
  vim.api.nvim_win_set_hl_ns(winnr, 0)
end

---@return CopilotChat.ui.Diff.Diff?
function Diff:get_diff()
  return self.diff
end

return Diff
