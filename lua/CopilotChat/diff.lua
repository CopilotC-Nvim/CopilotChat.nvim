---@class CopilotChat.Diff.diff
---@field change string
---@field reference string
---@field filename string
---@field filetype string
---@field start_line number
---@field end_line number
---@field bufnr number?

---@class CopilotChat.Diff
---@field bufnr number
---@field show fun(self: CopilotChat.Diff, diff: CopilotChat.Diff.diff, winnr: number)
---@field restore fun(self: CopilotChat.Diff, winnr: number, bufnr: number)
---@field delete fun(self: CopilotChat.Diff)
---@field get_diff fun(self: CopilotChat.Diff): CopilotChat.Diff.diff

local Overlay = require('CopilotChat.overlay')
local utils = require('CopilotChat.utils')
local class = utils.class

local Diff = class(function(self, help, on_buf_create)
  Overlay.init(self, 'copilot-diff', help, on_buf_create)
  self.hl_ns = vim.api.nvim_create_namespace('copilot-chat-highlights')
  vim.api.nvim_set_hl(self.hl_ns, '@diff.plus', { bg = utils.blend_color('DiffAdd', 20) })
  vim.api.nvim_set_hl(self.hl_ns, '@diff.minus', { bg = utils.blend_color('DiffDelete', 20) })
  vim.api.nvim_set_hl(self.hl_ns, '@diff.delta', { bg = utils.blend_color('DiffChange', 20) })

  self.diff = nil
end, Overlay)

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
    diff.filetype,
    winnr,
    'diff'
  )
end

function Diff:restore(winnr, bufnr)
  Overlay.restore(self, winnr, bufnr)
  vim.api.nvim_win_set_hl_ns(winnr, 0)
end

function Diff:get_diff()
  return self.diff
end

return Diff
