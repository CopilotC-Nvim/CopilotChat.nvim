---@class CopilotChat.Diff
---@field bufnr number
---@field show fun(self: CopilotChat.Diff, change: string, reference: string, start_line: number?, end_line: number?, filetype: string, winnr: number)
---@field restore fun(self: CopilotChat.Diff, winnr: number, bufnr: number)
---@field delete fun(self: CopilotChat.Diff)
---@field get_diff fun(self: CopilotChat.Diff): string, string, number?, number?

local Overlay = require('CopilotChat.overlay')
local utils = require('CopilotChat.utils')
local class = utils.class

local Diff = class(function(self, help, on_buf_create)
  self.hl_ns = vim.api.nvim_create_namespace('copilot-chat-highlights')
  vim.api.nvim_set_hl(
    self.hl_ns,
    '@diff.plus',
    { bg = utils.blend_color_with_neovim_bg('DiffAdd', 20) }
  )
  vim.api.nvim_set_hl(
    self.hl_ns,
    '@diff.minus',
    { bg = utils.blend_color_with_neovim_bg('DiffDelete', 20) }
  )
  vim.api.nvim_set_hl(
    self.hl_ns,
    '@diff.delta',
    { bg = utils.blend_color_with_neovim_bg('DiffChange', 20) }
  )

  self.name = 'copilot-diff'
  self.help = help
  self.on_buf_create = on_buf_create
  self.bufnr = nil
  self.change = nil
  self.reference = nil
  self.start_line = nil
  self.end_line = nil
  self.filetype = nil

  self.buf_create = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, self.name)
    vim.bo[bufnr].filetype = self.name
    return bufnr
  end
end, Overlay)

function Diff:show(change, reference, start_line, end_line, filetype, winnr)
  self.change = change
  self.reference = reference
  self.start_line = start_line
  self.end_line = end_line
  self.filetype = filetype

  self:validate()
  vim.api.nvim_win_set_hl_ns(winnr, self.hl_ns)

  -- mini.diff integration (unfinished)
  -- local diff_found, diff = pcall(require, 'mini.diff')
  -- if diff_found then
  --   diff.disable(self.bufnr)
  --   Overlay.show(self, change, filetype, winnr)
  --
  --   vim.b[self.bufnr].minidiff_config = {
  --     source = {
  --       name = self.name,
  --       attach = function(bufnr)
  --         diff.set_ref_text(bufnr, reference)
  --         diff.toggle_overlay(bufnr)
  --       end,
  --     },
  --   }
  --
  --   diff.enable(self.bufnr)
  --   return
  -- end

  Overlay.show(
    self,
    tostring(vim.diff(reference, change, {
      result_type = 'unified',
      ignore_blank_lines = true,
      ignore_whitespace = true,
      ignore_whitespace_change = true,
      ignore_whitespace_change_at_eol = true,
      ignore_cr_at_eol = true,
      algorithm = 'myers',
      ctxlen = #reference,
    })),
    filetype,
    winnr,
    'diff'
  )
end

function Diff:restore(winnr, bufnr)
  Overlay.restore(self, winnr, bufnr)
  vim.api.nvim_win_set_hl_ns(winnr, 0)
end

function Diff:get_diff()
  return self.change, self.reference, self.start_line, self.end_line, self.filetype
end

return Diff
