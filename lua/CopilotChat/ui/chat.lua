local Overlay = require('CopilotChat.ui.overlay')
local Spinner = require('CopilotChat.ui.spinner')
local utils = require('CopilotChat.utils')
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

local HEADER_PATTERNS = {
  '%[file:.+%]%((.+)%) line:(%d+)-?(%d*)',
  '%[file:(.+)%] line:(%d+)-?(%d*)',
}

---@param header? string
---@return string?, number?, number?
local function match_header(header)
  if not header then
    return
  end

  for _, pattern in ipairs(HEADER_PATTERNS) do
    local filename, start_line, end_line = header:match(pattern)
    if filename then
      return utils.filepath(filename), tonumber(start_line) or 1, tonumber(end_line) or tonumber(start_line) or 1
    end
  end
end

---@class CopilotChat.ui.Chat.Section.Block.Header
---@field filename string
---@field start_line number
---@field end_line number
---@field filetype string

---@class CopilotChat.ui.Chat.Section.Block
---@field header CopilotChat.ui.Chat.Section.Block.Header
---@field start_line number
---@field end_line number
---@field content string?

---@class CopilotChat.ui.Chat.Section
---@field answer boolean
---@field start_line number
---@field end_line number
---@field blocks table<CopilotChat.ui.Chat.Section.Block>
---@field content string?

---@class CopilotChat.ui.Chat : CopilotChat.ui.Overlay
---@field winnr number?
---@field config CopilotChat.config.shared
---@field layout CopilotChat.config.Layout?
---@field sections table<CopilotChat.ui.Chat.Section>
---@field references table<CopilotChat.Provider.reference>
---@field token_count number?
---@field token_max_count number?
---@field private question_header string
---@field private answer_header string
---@field private separator string
---@field private header_ns number
---@field private spinner CopilotChat.ui.Spinner
---@field private chat_overlay CopilotChat.ui.Overlay
local Chat = class(function(self, question_header, answer_header, separator, help, on_buf_create)
  Overlay.init(self, 'copilot-chat', help, on_buf_create)

  self.winnr = nil
  self.sections = {}
  self.config = {}
  self.layout = nil
  self.references = {}
  self.token_count = nil
  self.token_max_count = nil

  self.question_header = question_header
  self.answer_header = answer_header
  self.separator = separator
  self.header_ns = vim.api.nvim_create_namespace('copilot-chat-headers')

  self.spinner = Spinner()
  self.chat_overlay = Overlay('copilot-overlay', 'q to close', function(bufnr)
    vim.keymap.set('n', 'q', function()
      self.chat_overlay:restore(self.winnr, self.bufnr)
    end)

    vim.api.nvim_create_autocmd({ 'BufHidden', 'BufDelete' }, {
      buffer = bufnr,
      callback = function()
        self.chat_overlay:restore(self.winnr, self.bufnr)
      end,
    })
  end)
end, Overlay)

--- Returns whether the chat window is visible.
---@return boolean
function Chat:visible()
  return self.winnr and vim.api.nvim_win_is_valid(self.winnr) and vim.api.nvim_win_get_buf(self.winnr) == self.bufnr
    or false
end

--- Returns whether the chat window is focused.
---@return boolean
function Chat:focused()
  return self:visible() and vim.api.nvim_get_current_win() == self.winnr
end

--- Get the closest section to the cursor.
---@param type? "answer"|"question" If specified, only considers sections of the given type
---@return CopilotChat.ui.Chat.Section?
function Chat:get_closest_section(type)
  if not self:visible() then
    return nil
  end

  self:render()
  local cursor_pos = vim.api.nvim_win_get_cursor(self.winnr)
  local cursor_line = cursor_pos[1]
  local closest_section = nil
  local max_line_below_cursor = -1

  for _, section in ipairs(self.sections) do
    local matches_type = not type
      or (type == 'answer' and section.answer)
      or (type == 'question' and not section.answer)

    if matches_type and section.start_line <= cursor_line and section.start_line > max_line_below_cursor then
      max_line_below_cursor = section.start_line
      closest_section = section
    end
  end

  return closest_section
end

--- Get the closest code block to the cursor.
---@return CopilotChat.ui.Chat.Section.Block?
function Chat:get_closest_block()
  if not self:visible() then
    return nil
  end

  self:render()
  local cursor_pos = vim.api.nvim_win_get_cursor(self.winnr)
  local cursor_line = cursor_pos[1]
  local closest_block = nil
  local max_line_below_cursor = -1

  for _, section in pairs(self.sections) do
    for _, block in ipairs(section.blocks) do
      if block.start_line <= cursor_line and block.start_line > max_line_below_cursor then
        max_line_below_cursor = block.start_line
        closest_block = block
      end
    end
  end

  return closest_block
end

--- Get the prompt in the chat window.
---@return CopilotChat.ui.Chat.Section?
function Chat:get_prompt()
  if not self:visible() then
    return
  end

  self:render()
  local section = self.sections[#self.sections]
  if not section or section.answer then
    return
  end

  return section
end

--- Set the prompt in the chat window.
---@param prompt string?
function Chat:set_prompt(prompt)
  if not self:visible() then
    return
  end

  local section = self:get_prompt()
  if not section then
    return
  end

  local modifiable = vim.bo[self.bufnr].modifiable
  vim.bo[self.bufnr].modifiable = true
  local lines = prompt and vim.split('\n' .. prompt, '\n') or {}
  vim.api.nvim_buf_set_lines(self.bufnr, section.start_line - 1, section.end_line, false, lines)
  vim.bo[self.bufnr].modifiable = modifiable
end

--- Add a sticky line to the prompt in the chat window.
---@param sticky string
function Chat:add_sticky(sticky)
  if not self:visible() then
    return
  end

  local prompt = self:get_prompt()
  if not prompt then
    return
  end

  local lines = vim.split(prompt.content, '\n')
  local insert_line = 1
  local first_one = true
  local found = false

  for i = insert_line, #lines do
    local line = lines[i]
    if line and line ~= '' then
      if vim.startswith(line, '> ') then
        if line:sub(3) == sticky then
          found = true
          break
        end

        first_one = false
      else
        break
      end
    elseif i >= 2 then
      break
    end

    insert_line = insert_line + 1
  end

  if found then
    return
  end

  insert_line = prompt.start_line + insert_line - 1
  local to_insert = first_one and { '> ' .. sticky, '' } or { '> ' .. sticky }
  local modifiable = vim.bo[self.bufnr].modifiable
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, insert_line - 1, insert_line - 1, false, to_insert)
  vim.bo[self.bufnr].modifiable = modifiable
end

---@class CopilotChat.ui.Chat.show_overlay
---@field text string
---@field filetype string?
---@field syntax string?
---@field on_show? fun(bufnr: number)
---@field on_hide? fun(bufnr: number)

--- Show the overlay buffer.
---@param opts CopilotChat.ui.Chat.show_overlay
function Chat:overlay(opts)
  if not self:visible() then
    return
  end

  self.chat_overlay:show(opts.text, self.winnr, opts.filetype, opts.syntax, opts.on_show, opts.on_hide)
end

--- Open the chat window.
---@param config CopilotChat.config.shared
function Chat:open(config)
  self:validate()

  local window = config.window or {}

  local layout = window.layout
  if type(layout) == 'function' then
    layout = layout()
  end

  local width = window.width > 1 and window.width or math.floor(vim.o.columns * window.width)
  local height = window.height > 1 and window.height or math.floor(vim.o.lines * window.height)

  if self.layout ~= layout then
    self:close()
  end

  self.config = config
  self.layout = layout

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
      footer = window.footer,
    }

    self.winnr = vim.api.nvim_open_win(self.bufnr, false, win_opts)
  elseif layout == 'vertical' then
    local orig = vim.api.nvim_get_current_win()
    local cmd = 'vsplit'
    if width ~= 0 then
      cmd = width .. cmd
    end
    if vim.api.nvim_get_option_value('splitright', {}) then
      cmd = 'botright ' .. cmd
    else
      cmd = 'topleft ' .. cmd
    end
    vim.cmd(cmd)
    self.winnr = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(orig)
  elseif layout == 'horizontal' then
    local orig = vim.api.nvim_get_current_win()
    local cmd = 'split'
    if height ~= 0 then
      cmd = height .. cmd
    end
    if vim.api.nvim_get_option_value('splitbelow', {}) then
      cmd = 'botright ' .. cmd
    else
      cmd = 'topleft ' .. cmd
    end
    vim.cmd(cmd)
    self.winnr = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(orig)
  elseif layout == 'replace' then
    self.winnr = vim.api.nvim_get_current_win()
  end

  vim.wo[self.winnr].wrap = true
  vim.wo[self.winnr].linebreak = true
  vim.wo[self.winnr].cursorline = true
  vim.wo[self.winnr].conceallevel = 2
  vim.wo[self.winnr].foldlevel = 99
  if config.show_folds then
    vim.wo[self.winnr].foldcolumn = '1'
    vim.wo[self.winnr].foldmethod = 'expr'
    vim.wo[self.winnr].foldexpr = "v:lua.CopilotChatFoldExpr(v:lnum, '" .. self.separator .. "')"
  else
    vim.wo[self.winnr].foldcolumn = '0'
  end

  vim.api.nvim_win_set_buf(self.winnr, self.bufnr)
  self:render()
end

--- Close the chat window.
---@param bufnr number?
function Chat:close(bufnr)
  if not self:visible() then
    return
  end

  if self:focused() then
    utils.return_to_normal_mode()
  end

  if self.layout == 'replace' then
    if bufnr then
      self:restore(self.winnr, bufnr)
    end
  else
    vim.api.nvim_win_close(self.winnr, true)
  end

  self.winnr = nil
end

--- Focus the chat window.
function Chat:focus()
  if not self:visible() then
    return
  end

  vim.api.nvim_set_current_win(self.winnr)
  if self.config.auto_insert_mode and self:focused() and vim.bo[self.bufnr].modifiable then
    vim.cmd('startinsert')
  end
end

--- Follow the cursor to the last line of the chat window.
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

--- Finish writing to the chat window.
function Chat:finish()
  if not self.spinner then
    return
  end

  self.spinner:finish()
  vim.bo[self.bufnr].modifiable = true
  if self.config.auto_insert_mode and self:focused() then
    vim.cmd('startinsert')
  end
end

--- Append text to the chat window.
---@param str string
function Chat:append(str)
  self:validate()
  vim.bo[self.bufnr].modifiable = true

  if self:focused() then
    utils.return_to_normal_mode()
  end

  if self.spinner then
    self.spinner:start()
  end

  -- Decide if we should follow cursor after appending text.
  local should_follow_cursor = self.config.auto_follow_cursor
  if should_follow_cursor and self:visible() then
    local current_pos = vim.api.nvim_win_get_cursor(self.winnr)
    local line_count = vim.api.nvim_buf_line_count(self.bufnr)
    -- Follow only if the cursor is currently at the last line.
    should_follow_cursor = current_pos[1] == line_count
  end

  local last_line, last_column, _ = self:last()
  vim.api.nvim_buf_set_text(self.bufnr, last_line, last_column, last_line, last_column, vim.split(str, '\n'))

  if should_follow_cursor then
    self:follow()
  end

  vim.bo[self.bufnr].modifiable = false
end

--- Clear the chat window.
function Chat:clear()
  self:validate()
  self.references = {}
  self.token_count = nil
  self.token_max_count = nil
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, {})
  vim.bo[self.bufnr].modifiable = false
end

--- Create the chat window buffer.
---@protected
function Chat:create()
  local bufnr = Overlay.create(self)
  vim.bo[bufnr].syntax = 'markdown'
  vim.bo[bufnr].textwidth = 0

  vim.api.nvim_create_autocmd({ 'TextChanged', 'InsertLeave' }, {
    buffer = bufnr,
    callback = function()
      utils.debounce(self.name, function()
        self:render()
      end, 100)
    end,
  })

  self.spinner.bufnr = bufnr
  return bufnr
end

--- Validate the chat window.
---@protected
function Chat:validate()
  Overlay.validate(self)
  if self.winnr and vim.api.nvim_win_is_valid(self.winnr) and vim.api.nvim_win_get_buf(self.winnr) ~= self.bufnr then
    vim.api.nvim_win_set_buf(self.winnr, self.bufnr)
  end
end

--- Render the chat window.
---@protected
function Chat:render()
  vim.api.nvim_buf_clear_namespace(self.bufnr, self.header_ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
  local line_count = #lines

  local sections = {}
  local current_section = nil
  local current_block = nil

  for l, line in ipairs(lines) do
    local separator_found = false

    if line == self.answer_header .. self.separator then
      separator_found = true
      if current_section then
        current_section.end_line = l - 1
        current_section.content =
          vim.trim(table.concat(vim.list_slice(lines, current_section.start_line, current_section.end_line), '\n'))
        table.insert(sections, current_section)
      end
      current_section = {
        answer = true,
        start_line = l + 1,
        blocks = {},
      }
    elseif line == self.question_header .. self.separator then
      separator_found = true
      if current_section then
        current_section.end_line = l - 1
        current_section.content =
          vim.trim(table.concat(vim.list_slice(lines, current_section.start_line, current_section.end_line), '\n'))
        table.insert(sections, current_section)
      end
      current_section = {
        answer = false,
        start_line = l + 1,
        blocks = {},
      }
    elseif l == line_count then
      if current_section then
        current_section.end_line = l
        current_section.content =
          vim.trim(table.concat(vim.list_slice(lines, current_section.start_line, current_section.end_line), '\n'))
        table.insert(sections, current_section)
      end
    end

    -- Highlight separators
    if self.config.highlight_headers and separator_found then
      local sep = vim.fn.strwidth(line) - vim.fn.strwidth(self.separator)
      -- separator line
      vim.api.nvim_buf_set_extmark(self.bufnr, self.header_ns, l - 1, sep, {
        virt_text_win_col = sep,
        virt_text = {
          { string.rep(self.separator, vim.go.columns), 'CopilotChatSeparator' },
        },
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

    -- Parse code blocks
    if current_section and current_section.answer then
      local filetype = line:match('^```(%w+)$')
      if filetype and not current_block then
        local filename, start_line, end_line = match_header(lines[l - 1])
        if not filename then
          filename, start_line, end_line = match_header(lines[l - 2])
        end
        filename = filename or 'code-block'

        current_block = {
          header = {
            filename = filename,
            start_line = start_line,
            end_line = end_line,
            filetype = filetype,
          },
          start_line = l + 1,
        }
      elseif line == '```' and current_block then
        current_block.end_line = l - 1
        current_block.content =
          table.concat(vim.list_slice(lines, current_block.start_line, current_block.end_line), '\n')
        table.insert(current_section.blocks, current_block)
        current_block = nil
      end
    end
  end

  local last_section = sections[#sections]
  if last_section and not last_section.answer then
    local msg = self.config.show_help and self.help or ''
    if self.token_count and self.token_max_count then
      if msg ~= '' then
        msg = msg .. '\n'
      end
      msg = msg .. self.token_count .. '/' .. self.token_max_count .. ' tokens used'
    end

    self:show_help(msg, last_section.start_line - last_section.end_line - 1)

    if not utils.empty(self.references) and self.config.references_display == 'virtual' then
      msg = 'References:\n'
      for _, ref in ipairs(self.references) do
        msg = msg .. '  ' .. ref.name .. '\n'
      end

      vim.api.nvim_buf_set_extmark(self.bufnr, self.header_ns, last_section.start_line - 2, 0, {
        hl_mode = 'combine',
        priority = 100,
        virt_lines_above = true,
        virt_lines = vim.tbl_map(function(t)
          return { { t, 'CopilotChatHelp' } }
        end, vim.split(msg, '\n')),
      })
    end
  else
    self:show_help()
  end

  self.sections = sections
end

--- Get the last line and column of the chat window.
---@return number, number, number
---@protected
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

return Chat
