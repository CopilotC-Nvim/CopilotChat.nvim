---@class CopilotChat.Chat
---@field bufnr number
---@field winnr number
---@field valid fun(self: CopilotChat.Chat)
---@field visible fun(self: CopilotChat.Chat)
---@field active fun(self: CopilotChat.Chat)
---@field append fun(self: CopilotChat.Chat, str: string)
---@field last fun(self: CopilotChat.Chat)
---@field clear fun(self: CopilotChat.Chat)
---@field open fun(self: CopilotChat.Chat, config: CopilotChat.config)
---@field close fun(self: CopilotChat.Chat, bufnr: number?)
---@field focus fun(self: CopilotChat.Chat)
---@field follow fun(self: CopilotChat.Chat)
---@field finish fun(self: CopilotChat.Chat, msg: string?, offset: number?)
---@field delete fun(self: CopilotChat.Chat)

local Overlay = require('CopilotChat.overlay')
local Spinner = require('CopilotChat.spinner')
local utils = require('CopilotChat.utils')
local is_stable = utils.is_stable
local class = utils.class

function CopilotChatFoldExpr(lnum, separator)
  local to_match = separator .. '$'
  if string.match(vim.fn.getline(lnum), to_match) then
    return '1'
  elseif string.match(vim.fn.getline(lnum + 1), to_match) then
    return '0'
  end
  return '='
end

local Chat = class(function(self, help, on_buf_create)
  self.header_ns = vim.api.nvim_create_namespace('copilot-chat-headers')
  self.name = 'copilot-chat'
  self.help = help
  self.on_buf_create = on_buf_create
  self.bufnr = nil
  self.winnr = nil
  self.spinner = nil
  self.separator = nil
  self.auto_insert = false
  self.auto_follow_cursor = true
  self.highlight_headers = true
  self.layout = nil

  vim.treesitter.language.register('markdown', self.name)

  self.buf_create = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, self.name)
    vim.bo[bufnr].filetype = self.name
    vim.bo[bufnr].syntax = 'markdown'
    vim.bo[bufnr].textwidth = 0
    local ok, parser = pcall(vim.treesitter.get_parser, bufnr, 'markdown')
    if ok and parser then
      vim.treesitter.start(bufnr, 'markdown')
    end

    if not self.spinner then
      self.spinner = Spinner(bufnr)
    else
      self.spinner.bufnr = bufnr
    end

    return bufnr
  end
end, Overlay)

function Chat:visible()
  return self.winnr
    and vim.api.nvim_win_is_valid(self.winnr)
    and vim.api.nvim_win_get_buf(self.winnr) == self.bufnr
end

function Chat:render()
  if not self.highlight_headers or not self:visible() then
    return
  end

  vim.api.nvim_buf_clear_namespace(self.bufnr, self.header_ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
  for l, line in ipairs(lines) do
    if line:match(self.separator .. '$') then
      local sep = vim.fn.strwidth(line) - vim.fn.strwidth(self.separator)
      -- separator line
      vim.api.nvim_buf_set_extmark(self.bufnr, self.header_ns, l - 1, sep, {
        virt_text_win_col = sep,
        virt_text = { { string.rep(self.separator, vim.go.columns), 'CopilotChatSeparator' } },
        priority = 100,
        strict = false,
      })
      -- header hl group
      vim.api.nvim_buf_set_extmark(self.bufnr, self.header_ns, l - 1, 0, {
        end_col = sep + 1,
        hl_group = 'CopilotChatHeader',
        priority = 100,
        strict = false,
      })
    end
  end
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

  if self:active() then
    utils.return_to_normal_mode()
  end

  if self.spinner then
    self.spinner:start()
  end

  -- Decide if we should follow cursor after appending text.
  local should_follow_cursor = self.auto_follow_cursor
  if self.auto_follow_cursor and self:visible() then
    local current_pos = vim.api.nvim_win_get_cursor(self.winnr)
    local line_count = vim.api.nvim_buf_line_count(self.bufnr)
    -- Follow only if the cursor is currently at the last line.
    should_follow_cursor = current_pos[1] == line_count
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
  self:render()

  if should_follow_cursor then
    self:follow()
  end
end

function Chat:clear()
  self:validate()
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, {})
  self:render()
end

function Chat:open(config)
  self:validate()

  local window = config.window
  local layout = window.layout
  local width = window.width > 1 and window.width or math.floor(vim.o.columns * window.width)
  local height = window.height > 1 and window.height or math.floor(vim.o.lines * window.height)

  if self.layout ~= layout then
    self:close()
  end

  if self:visible() then
    return
  end

  if layout == 'float' then
    local win_opts = {
      style = 'minimal',
      width = width,
      height = height,
      zindex = window.zindex,
      relative = window.relative,
      border = window.border,
      title = window.title,
      row = window.row or math.floor((vim.o.lines - height) / 2),
      col = window.col or math.floor((vim.o.columns - width) / 2),
    }
    if not is_stable() then
      win_opts.footer = window.footer
    end
    self.winnr = vim.api.nvim_open_win(self.bufnr, false, win_opts)
  elseif layout == 'vertical' then
    local orig = vim.api.nvim_get_current_win()
    local cmd = 'vsplit'
    if width ~= 0 then
      cmd = width .. cmd
    end
    vim.cmd(cmd)
    self.winnr = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(self.winnr, self.bufnr)
    vim.api.nvim_set_current_win(orig)
  elseif layout == 'horizontal' then
    local orig = vim.api.nvim_get_current_win()
    local cmd = 'split'
    if height ~= 0 then
      cmd = height .. cmd
    end
    vim.cmd(cmd)
    self.winnr = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(self.winnr, self.bufnr)
    vim.api.nvim_set_current_win(orig)
  elseif layout == 'replace' then
    self.winnr = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(self.winnr, self.bufnr)
  end

  self.layout = layout
  self.separator = config.separator
  self.auto_insert = config.auto_insert
  self.auto_follow_cursor = config.auto_follow_cursor
  self.highlight_headers = config.highlight_headers

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
  self:render()
end

function Chat:close(bufnr)
  if not self:visible() then
    return
  end

  if self:active() then
    utils.return_to_normal_mode()
  end

  if self.layout == 'replace' then
    self:restore(self.winnr, bufnr)
  else
    vim.api.nvim_win_close(self.winnr, true)
  end

  self.winnr = nil
end

function Chat:focus()
  if self:visible() then
    vim.api.nvim_set_current_win(self.winnr)
    if self.auto_insert and self:active() then
      vim.cmd('startinsert')
    end
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

function Chat:finish(msg, offset)
  if not self.spinner then
    return
  end

  if not offset then
    offset = 0
  end

  self.spinner:finish()

  if msg and msg ~= '' then
    if self.help and self.help ~= '' then
      msg = msg .. '\n' .. self.help
    end
  else
    msg = self.help
  end

  self:show_help(msg, -offset)
  if self.auto_insert and self:active() then
    vim.cmd('startinsert')
  end
end

return Chat
