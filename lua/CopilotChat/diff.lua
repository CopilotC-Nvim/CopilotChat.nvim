---@class CopilotChat.Diff
---@field bufnr number
---@field current string?
---@field valid fun(self: CopilotChat.Diff)
---@field validate fun(self: CopilotChat.Diff)
---@field show fun(self: CopilotChat.Diff, a: string, b: string, filetype: string, winnr: number)
---@field restore fun(self: CopilotChat.Diff, winnr: number, bufnr: number)

local utils = require('CopilotChat.utils')
local is_stable = utils.is_stable
local class = utils.class

local function blend_color_with_neovim_bg(color_name, blend)
  local color_int = vim.api.nvim_get_hl(0, { name = color_name }).fg
  local bg_int = vim.api.nvim_get_hl(0, { name = 'Normal' }).bg

  if not color_int or not bg_int then
    return
  end

  local color = { (color_int / 65536) % 256, (color_int / 256) % 256, color_int % 256 }
  local bg = { (bg_int / 65536) % 256, (bg_int / 256) % 256, bg_int % 256 }
  local r = math.floor((color[1] * blend + bg[1] * (100 - blend)) / 100)
  local g = math.floor((color[2] * blend + bg[2] * (100 - blend)) / 100)
  local b = math.floor((color[3] * blend + bg[3] * (100 - blend)) / 100)
  return string.format('#%02x%02x%02x', r, g, b)
end

local function create_buf()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, 'copilot-diff')
  vim.bo[bufnr].filetype = 'diff'
  vim.treesitter.start(bufnr, 'diff')
  return bufnr
end

local Diff = class(function(self, on_buf_create, help)
  self.help = help
  self.on_buf_create = on_buf_create
  self.current = nil
  self.ns = vim.api.nvim_create_namespace('copilot-diff')
  self.mark_ns = vim.api.nvim_create_namespace('copilot-diff-mark')
  self.bufnr = nil
  vim.api.nvim_set_hl(self.ns, '@diff.plus', { bg = blend_color_with_neovim_bg('DiffAdd', 20) })
  vim.api.nvim_set_hl(self.ns, '@diff.minus', { bg = blend_color_with_neovim_bg('DiffDelete', 20) })
  vim.api.nvim_set_hl(self.ns, '@diff.delta', { bg = blend_color_with_neovim_bg('DiffChange', 20) })
end)

function Diff:valid()
  return self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr)
end

function Diff:validate()
  if self:valid() then
    return
  end
  self.bufnr = create_buf()
  self.on_buf_create(self.bufnr)
end

function Diff:show(a, b, filetype, winnr)
  self:validate()
  self.current = b

  local diff = tostring(vim.diff(a, b, {
    result_type = 'unified',
    ignore_blank_lines = true,
    ignore_whitespace = true,
    ignore_whitespace_change = true,
    ignore_whitespace_change_at_eol = true,
    ignore_cr_at_eol = true,
    algorithm = 'myers',
    ctxlen = #a,
  }))
  diff = '\n' .. diff

  vim.api.nvim_win_set_buf(winnr, self.bufnr)
  vim.api.nvim_win_set_hl_ns(winnr, self.ns)
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, vim.split(diff, '\n'))
  vim.bo[self.bufnr].modifiable = false

  local opts = {
    id = self.mark_ns,
    hl_mode = 'combine',
    priority = 100,
    virt_text = { { self.help, 'CursorColumn' } },
  }

  -- stable do not supports virt_text_pos
  if not is_stable() then
    opts.virt_text_pos = 'inline'
  end

  vim.api.nvim_buf_set_extmark(self.bufnr, self.mark_ns, 0, 0, opts)
  vim.treesitter.start(self.bufnr, 'diff')
  vim.bo[self.bufnr].syntax = filetype
end

function Diff:restore(winnr, bufnr)
  self.current = nil
  vim.api.nvim_win_set_buf(winnr, bufnr)
  vim.api.nvim_win_set_hl_ns(winnr, 0)
end

return Diff
