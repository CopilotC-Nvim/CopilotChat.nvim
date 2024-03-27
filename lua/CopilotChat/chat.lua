---@class CopilotChat.Chat
---@field bufnr number
---@field winnr number
---@field spinner CopilotChat.Spinner
---@field valid fun(self: CopilotChat.Chat)
---@field visible fun(self: CopilotChat.Chat)
---@field active fun(self: CopilotChat.Chat)
---@field append fun(self: CopilotChat.Chat, str: string)
---@field last fun(self: CopilotChat.Chat)
---@field clear fun(self: CopilotChat.Chat)
---@field open fun(self: CopilotChat.Chat, config: CopilotChat.config)
---@field close fun(self: CopilotChat.Chat)
---@field focus fun(self: CopilotChat.Chat)
---@field follow fun(self: CopilotChat.Chat)
---@field finish fun(self: CopilotChat.Chat, msg: string?)

local Overlay = require('CopilotChat.overlay')
local Spinner = require('CopilotChat.spinner')
local utils = require('CopilotChat.utils')
local is_stable = utils.is_stable
local class = utils.class
local show_virt_line = utils.show_virt_line

function CopilotChatFoldExpr(lnum, separator)
  local line = vim.fn.getline(lnum)
  if string.match(line, separator .. '$') then
    return '>1'
  end

  return '='
end

local Chat = class(function(self, mark_ns, help, on_buf_create)
  self.mark_ns = mark_ns
  self.help = help
  self.on_buf_create = on_buf_create
  self.bufnr = nil
  self.winnr = nil
  self.spinner = nil

  self.buf_create = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, 'copilot-chat')
    vim.bo[bufnr].filetype = 'copilot-chat'
    vim.bo[bufnr].syntax = 'markdown'
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, 'markdown')
    if ok and parser then
      vim.treesitter.start(bufnr, 'markdown')
    end

    if not self.spinner then
      self.spinner = Spinner(bufnr, mark_ns, 'copilot-chat')
    else
      self.spinner.bufnr = bufnr
    end

    return bufnr
  end
end, Overlay)

function Chat:visible()
  return self.winnr and vim.api.nvim_win_is_valid(self.winnr)
end

function Chat:active()
  return vim.api.nvim_get_current_win() == self.winnr
end

function Chat:last()
  self:validate()
  local line_count = vim.api.nvim_buf_line_count(self.bufnr)
  local last_line = line_count - 1
  if last_line < 0 then
    return 0, 0, line_count
  end
  local last_line_content = vim.api.nvim_buf_get_lines(self.bufnr, -2, -1, false)
  if not last_line_content or #last_line_content == 0 then
    return last_line, 0, line_count
  end
  local last_column = #last_line_content[1]
  return last_line, last_column, line_count
end

function Chat:append(str)
  self:validate()

  if self.spinner then
    self.spinner:start()
  end

  local last_line, last_column, _ = self:last()
  vim.api.nvim_buf_set_text(
    self.bufnr,
    last_line,
    last_column,
    last_line,
    last_column,
    vim.split(str, '\n')
  )
end

function Chat:clear()
  self:validate()
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, {})
end

function Chat:open(config)
  self:validate()

  if self:visible() then
    return
  end

  local window = config.window
  local win_opts = {
    style = 'minimal',
  }

  local layout = window.layout

  if layout == 'float' then
    win_opts.zindex = window.zindex
    win_opts.relative = window.relative
    win_opts.border = window.border
    win_opts.title = window.title
    win_opts.row = window.row or math.floor(vim.o.lines * ((1 - config.window.height) / 2))
    win_opts.col = window.col or math.floor(vim.o.columns * ((1 - window.width) / 2))
    win_opts.width = math.floor(vim.o.columns * window.width)
    win_opts.height = math.floor(vim.o.lines * window.height)

    if not is_stable() then
      win_opts.footer = window.footer
    end
  elseif layout == 'vertical' then
    if is_stable() then
      local orig = vim.api.nvim_get_current_win()
      vim.cmd('vsplit')
      self.winnr = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(self.winnr, self.bufnr)
      vim.api.nvim_set_current_win(orig)
    else
      win_opts.vertical = true
    end
  elseif layout == 'horizontal' then
    if is_stable() then
      local orig = vim.api.nvim_get_current_win()
      vim.cmd('split')
      self.winnr = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(self.winnr, self.bufnr)
      vim.api.nvim_set_current_win(orig)
    else
      win_opts.vertical = false
    end
  end

  if not self.winnr or not vim.api.nvim_win_is_valid(self.winnr) then
    self.winnr = vim.api.nvim_open_win(self.bufnr, false, win_opts)
  end

  vim.wo[self.winnr].wrap = true
  vim.wo[self.winnr].linebreak = true
  vim.wo[self.winnr].cursorline = true
  vim.wo[self.winnr].conceallevel = 2
  vim.wo[self.winnr].foldlevel = 99
  if config.show_folds then
    vim.wo[self.winnr].foldcolumn = '1'
    vim.wo[self.winnr].foldmethod = 'expr'
    vim.wo[self.winnr].foldexpr = "v:lua.CopilotChatFoldExpr(v:lnum, '" .. config.separator .. "')"
  else
    vim.wo[self.winnr].foldcolumn = '0'
  end
end

function Chat:close()
  if self.spinner then
    self.spinner:finish()
  end

  if self:visible() then
    vim.api.nvim_win_close(self.winnr, true)
    self.winnr = nil
  end
end

function Chat:focus()
  if self:visible() then
    vim.api.nvim_set_current_win(self.winnr)
  end
end

function Chat:follow()
  if not self:visible() then
    return
  end

  local last_line, last_column, line_count = self:last()
  if line_count == 0 then
    return
  end

  vim.api.nvim_win_set_cursor(self.winnr, { last_line + 1, last_column })
end

function Chat:finish(msg)
  if not self.spinner then
    return
  end

  self.spinner:finish()

  if msg and msg ~= '' then
    if self.help and self.help ~= '' then
      msg = msg .. '\n' .. self.help
    end
  else
    msg = self.help
  end
  msg = vim.trim(msg)

  if msg and msg ~= '' then
    local line = vim.api.nvim_buf_line_count(self.bufnr) - 2
    show_virt_line(msg, math.max(0, line - 1), self.bufnr, self.mark_ns)
  end
end

return Chat
