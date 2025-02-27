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
---@field augroup number
local Diff = class(function(self, help, on_buf_create)
  Overlay.init(self, 'copilot-diff', help, on_buf_create)
  self.hl_ns = vim.api.nvim_create_namespace('copilot-chat-highlights')
  vim.api.nvim_set_hl(self.hl_ns, '@diff.plus', { bg = utils.blend_color('DiffAdd', 20) })
  vim.api.nvim_set_hl(self.hl_ns, '@diff.minus', { bg = utils.blend_color('DiffDelete', 20) })
  vim.api.nvim_set_hl(self.hl_ns, '@diff.delta', { bg = utils.blend_color('DiffChange', 20) })

  self.augroup = vim.api.nvim_create_augroup('CopilotChatDiff', { clear = true })
  self.diff = nil
end, Overlay)

---@param diff CopilotChat.ui.Diff.Diff
---@param winnr number
---@param full_diff boolean
function Diff:show(diff, winnr, full_diff)
  self.diff = diff
  self:validate()
  vim.api.nvim_win_set_hl_ns(winnr, self.hl_ns)

  if not full_diff then
    -- Create unified diff view
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

    return
  end

  -- Create modified version by applying the change
  local modified = {}
  if utils.buf_valid(diff.bufnr) then
    modified = vim.api.nvim_buf_get_lines(diff.bufnr, 0, -1, false)
  end
  local change_lines = vim.split(diff.change, '\n')

  -- Replace the lines in the modified content
  if #modified > 0 then
    local start_idx = diff.start_line - 1
    local end_idx = diff.end_line - 1
    for _ = start_idx, end_idx do
      table.remove(modified, start_idx)
    end
    for i, line in ipairs(change_lines) do
      table.insert(modified, start_idx + i - 1, line)
    end
  else
    modified = change_lines
  end

  Overlay.show(self, table.concat(modified, '\n'), winnr, diff.filetype)

  if utils.buf_valid(diff.bufnr) then
    vim.cmd('diffthis')
    vim.api.nvim_set_current_win(vim.fn.bufwinid(diff.bufnr))
    vim.api.nvim_win_set_cursor(0, { diff.start_line, 0 })
    vim.cmd('diffthis')
    vim.api.nvim_set_current_win(winnr)
    vim.api.nvim_win_set_cursor(winnr, { diff.start_line, 0 })

    -- Link diff buffers lifecycle
    vim.api.nvim_create_autocmd('BufWipeout', {
      group = self.augroup,
      buffer = self.bufnr,
      callback = function()
        vim.cmd('diffoff')
      end,
    })
  end
end

---@param winnr number
---@param bufnr number
function Diff:restore(winnr, bufnr)
  vim.cmd('diffoff')
  Overlay.restore(self, winnr, bufnr)
  vim.api.nvim_win_set_hl_ns(winnr, 0)
end

---@return CopilotChat.ui.Diff.Diff?
function Diff:get_diff()
  return self.diff
end

return Diff
