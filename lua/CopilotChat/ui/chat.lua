local Overlay = require('CopilotChat.ui.overlay')
local Spinner = require('CopilotChat.ui.spinner')
local constants = require('CopilotChat.constants')
local notify = require('CopilotChat.notify')
local utils = require('CopilotChat.utils')
local class = require('CopilotChat.utils.class')

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
  '^(%w+)%s+path=(%S+)%s+start_line=(%d+)%s+end_line=(%d+)$',
  '^(%w+)$',
}

---@param headers table<string, string>?
---@return string?, string?
local function match_section_header(headers, separator, line)
  if not headers then
    return
  end

  for header_name, header_value in pairs(headers) do
    local id = line:match('^' .. vim.pesc(header_value) .. ' %(([^)]+)%) ' .. vim.pesc(separator) .. '$')
    if id then
      return id, header_name
    end
  end
end

---@param header? string
---@return string?, string?, number?, number?
local function match_block_header(header)
  if not header then
    return
  end

  for _, pattern in ipairs(HEADER_PATTERNS) do
    local type, path, start_line, end_line = header:match(pattern)
    if path then
      return type, path, tonumber(start_line) or 1, tonumber(end_line) or tonumber(start_line) or 1
    elseif type then
      return type, 'block'
    end
  end
end

---@class CopilotChat.ui.chat.Header
---@field filename string
---@field start_line number
---@field end_line number
---@field filetype string

---@class CopilotChat.ui.chat.Block
---@field header CopilotChat.ui.chat.Header
---@field start_line number
---@field end_line number
---@field content string

---@class CopilotChat.ui.chat.Section
---@field start_line number
---@field end_line number
---@field blocks table<CopilotChat.ui.chat.Block>

---@class CopilotChat.ui.chat.Message : CopilotChat.client.Message
---@field id string?
---@field section CopilotChat.ui.chat.Section?

---@class CopilotChat.ui.chat.Chat : CopilotChat.ui.overlay.Overlay
---@field winnr number?
---@field config CopilotChat.config.Shared
---@field token_count number?
---@field token_max_count number?
---@field messages table<CopilotChat.client.Message>
---@field private layout CopilotChat.config.Layout?
---@field private headers table<string, string>
---@field private separator string
---@field private spinner CopilotChat.ui.spinner.Spinner
---@field private chat_overlay CopilotChat.ui.overlay.Overlay
local Chat = class(function(self, config, on_buf_create)
  Overlay.init(self, 'copilot-chat', utils.key_to_info('show_help', config.mappings.show_help), on_buf_create)

  self.winnr = nil
  self.config = config
  self.token_count = nil
  self.token_max_count = nil
  self.messages = {}

  self.layout = nil
  self.headers = {}
  for k, v in pairs(config.headers or {}) do
    self.headers[k] = v:gsub('^#+', ''):gsub('^%s+', '')
  end
  self.separator = config.separator

  self.spinner = Spinner()
  self.chat_overlay = Overlay(
    'copilot-overlay',
    utils.key_to_info('close', {
      normal = config.mappings.close.normal,
    }),
    function(bufnr)
      vim.keymap.set('n', config.mappings.close.normal, function()
        self.chat_overlay:restore(self.winnr, self.bufnr)
      end)

      vim.api.nvim_create_autocmd({ 'BufHidden', 'BufDelete' }, {
        buffer = bufnr,
        callback = function()
          self.chat_overlay:restore(self.winnr, self.bufnr)
        end,
      })
    end
  )

  notify.listen(notify.MESSAGE, function(msg)
    utils.schedule_main()

    if not self:visible() then
      self:open(self.config)
    end

    if not msg or msg == '' then
      self.chat_overlay:restore(self.winnr, self.bufnr)
    else
      self:overlay({ text = msg })
    end
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

--- Get the closest code block to the cursor.
---@param role string? If specified, only considers sections of the given role
---@param cursor boolean? If true, returns the block closest to the cursor position
---@return CopilotChat.ui.chat.Block?
function Chat:get_block(role, cursor)
  if cursor then
    if not self:visible() then
      return nil
    end

    local cursor_pos = vim.api.nvim_win_get_cursor(self.winnr)
    local cursor_line = cursor_pos[1]
    local closest_block = nil
    local max_line_below_cursor = -1

    for _, message in ipairs(self.messages) do
      local section = message.section
      local matches_role = not role or message.role == role
      if matches_role and section and section.blocks then
        for _, block in ipairs(section.blocks) do
          if block.start_line <= cursor_line and block.start_line > max_line_below_cursor then
            max_line_below_cursor = block.start_line
            closest_block = block
          end
        end
      end
    end

    return closest_block
  end

  for i = #self.messages, 1, -1 do
    local message = self.messages[i]
    local matches_role = not role or message.role == role
    if matches_role and message.section and message.section.blocks and #message.section.blocks > 0 then
      return message.section.blocks[#message.section.blocks]
    end
  end
end

--- Get last message by role in the chat window.
---@param role string? If specified, only considers sections of the given role
---@param cursor boolean? If true, returns the message closest to the cursor position
---@return CopilotChat.ui.chat.Message?
function Chat:get_message(role, cursor)
  self:parse()

  if cursor then
    if not self:visible() then
      return nil
    end

    local cursor_pos = vim.api.nvim_win_get_cursor(self.winnr)
    local cursor_line = cursor_pos[1]
    local closest_message = nil
    local max_line_below_cursor = -1

    for _, message in ipairs(self.messages) do
      local section = message.section
      local matches_role = not role or message.role == role
      if matches_role and section.start_line <= cursor_line and section.start_line > max_line_below_cursor then
        max_line_below_cursor = section.start_line
        closest_message = message
      end
    end

    return closest_message
  end

  for i = #self.messages, 1, -1 do
    local message = self.messages[i]
    local matches_role = not role or message.role == role
    if matches_role then
      return message
    end
  end
end

--- Add a sticky line to the prompt in the chat window.
---@param sticky string
function Chat:add_sticky(sticky)
  if not self:visible() then
    return
  end

  local prompt = self:get_message(constants.ROLE.USER)
  if not prompt or not prompt.section then
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

  insert_line = prompt.section.start_line + insert_line - 1
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
---@param config CopilotChat.config.Shared
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
    vim.wo[self.winnr].winblend = window.blend or 0
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

  local ns = vim.api.nvim_create_namespace('copilot-chat-local-hl')
  vim.api.nvim_set_hl(ns, '@markup.quote.markdown', {}) -- disable quote block overriding chat keywords
  vim.api.nvim_set_hl(ns, '@markup.italic.markdown_inline', {}) -- disable italic messing up glob patterns
  vim.api.nvim_win_set_hl_ns(self.winnr, ns)
  vim.api.nvim_win_set_buf(self.winnr, self.bufnr)
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

--- Prepare the chat window for writing.
function Chat:start()
  self:validate()

  if self:focused() then
    utils.return_to_normal_mode()
  end

  if self.spinner then
    self.spinner:start()
  end

  vim.bo[self.bufnr].modifiable = false
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

--- Add a message to the chat window.
---@param message CopilotChat.ui.chat.Message
---@param replace boolean? If true, replaces the last message if it has same role
function Chat:add_message(message, replace)
  self:parse()

  local current_message = self.messages[#self.messages]
  local is_new = not current_message
    or current_message.role ~= message.role
    or (message.id and current_message.id ~= message.id)

  if is_new then
    -- Add appropriate header based on role and generate a new ID if not provided
    message.id = message.id or utils.uuid()
    local header = self.headers[message.role]
    table.insert(self.messages, message)

    if current_message then
      self:append('\n')
    end
    self:append('# ' .. header .. ' (' .. message.id .. ') ' .. self.separator .. '\n\n')
    self:append(message.content)
  elseif replace and current_message then
    -- Replace the content of the current message
    for k, v in pairs(message) do
      current_message[k] = v
    end

    local section = current_message.section

    if section then
      local modifiable = vim.bo[self.bufnr].modifiable
      vim.bo[self.bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(
        self.bufnr,
        section.start_line - 1,
        section.end_line,
        false,
        vim.split(message.content, '\n')
      )
      vim.bo[self.bufnr].modifiable = modifiable
      self:append('')
    end
  else
    -- Append to the current message
    current_message.content = current_message.content .. message.content
    self:append(message.content)
  end
end

--- Remove a message from the chat window by role.
---@param role string? If specified, only considers sections of the given role
---@param cursor boolean? If true, removes the message closest to the cursor position
function Chat:remove_message(role, cursor)
  if not self:visible() then
    return
  end

  self:parse()
  local message = self:get_message(role, cursor)
  if not message then
    return
  end

  local section = message.section
  if not section then
    return
  end

  -- Remove the section from the buffer
  local modifiable = vim.bo[self.bufnr].modifiable
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, section.start_line - 2, section.end_line + 1, false, {})
  vim.bo[self.bufnr].modifiable = modifiable

  -- Remove the message from the messages list
  for i, msg in ipairs(self.messages) do
    if msg.id == message.id then
      table.remove(self.messages, i)
      break
    end
  end
end

--- Append text to the chat window.
---@param str string
function Chat:append(str)
  self:validate()

  -- Decide if we should follow cursor after appending text.
  local should_follow_cursor = self.config.auto_follow_cursor
  if should_follow_cursor and self:visible() then
    local current_pos = vim.api.nvim_win_get_cursor(self.winnr)
    local line_count = vim.api.nvim_buf_line_count(self.bufnr)
    -- Follow only if the cursor is currently at the last line.
    should_follow_cursor = current_pos[1] >= line_count - 1
  end

  local last_line, last_column, _ = self:last()

  local modifiable = vim.bo[self.bufnr].modifiable
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_text(self.bufnr, last_line, last_column, last_line, last_column, vim.split(str, '\n'))
  vim.bo[self.bufnr].modifiable = modifiable

  if should_follow_cursor then
    self:follow()
  end
end

--- Clear the chat window.
function Chat:clear()
  self:validate()
  self.token_count = nil
  self.token_max_count = nil
  self.messages = {}

  local modifiable = vim.bo[self.bufnr].modifiable
  vim.bo[self.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, {})
  vim.bo[self.bufnr].modifiable = modifiable
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
      utils.debounce('chat-parse-' .. bufnr, function()
        self:parse()
        self:render()
      end, 150)
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

function Chat:parse()
  self:validate()

  local changedtick = vim.api.nvim_buf_get_changedtick(self.bufnr)
  if self._last_changedtick == changedtick then
    return false
  end
  self._last_changedtick = changedtick

  local parser = vim.treesitter.get_parser(self.bufnr, 'markdown')
  if not parser then
    return
  end

  local query = vim.treesitter.query.get('markdown', 'copilotchat')
  if not query then
    return
  end

  local root = parser:parse()[1]:root()
  local new_messages = {}
  local current_message = {
    content = {},
    section = {
      blocks = {},
    },
  }

  local current_block = {
    content = {},
  }

  for id, node in query:iter_captures(root, self.bufnr, 0, -1) do
    local name = query.captures[id]
    local start_row, _, end_row, _ = node:range()

    -- Convert 0 based to 1 based indexing
    start_row = start_row + 1
    end_row = end_row + 1

    -- Skip header line at start of the section
    start_row = start_row + 1

    if name == 'section_header' then
      local header_text = vim.treesitter.get_node_text(node, self.bufnr)
      local id, role = match_section_header(self.headers, self.separator, header_text)
      if role and id ~= current_message.id then
        current_message.section.end_line = start_row - 2

        current_message = {
          id = id,
          role = role,
          content = {},
          section = {
            blocks = {},
            start_line = start_row,
          },
        }
        table.insert(new_messages, current_message)
      end
    elseif name == 'section_content' then
      local content = vim.treesitter.get_node_text(node, self.bufnr)
      current_message.section.end_line = end_row
      table.insert(current_message.content, content)
    elseif current_message.role == constants.ROLE.ASSISTANT then
      if name == 'block_header' then
        local header_text = vim.treesitter.get_node_text(node, self.bufnr)
        local filetype, filename, start_line, end_line = match_block_header(header_text)
        if filetype then
          current_block = {
            header = {
              filetype = filetype,
              filename = filename,
              start_line = start_line,
              end_line = end_line,
            },
            start_line = start_row,
            content = {},
          }
          table.insert(current_message.section.blocks, current_block)
        end
      elseif name == 'block_content' then
        local content = vim.treesitter.get_node_text(node, self.bufnr)
        current_block.end_line = end_row
        table.insert(current_block.content, content)
      end
    end
  end

  -- Finish last message
  current_message.section.end_line = vim.api.nvim_buf_line_count(self.bufnr)

  for _, message in ipairs(new_messages) do
    message.content = vim.trim(table.concat(message.content, '\n'))
    if message.section then
      for _, block in ipairs(message.section.blocks) do
        block.content = vim.trim(table.concat(block.content, '\n'))
      end
    end
  end

  self.messages = new_messages
end

--- Render the chat window.
---@protected
function Chat:render()
  self:validate()

  local highlight_ns = vim.api.nvim_create_namespace('copilot-chat-headers')
  vim.api.nvim_buf_clear_namespace(self.bufnr, highlight_ns, 0, -1) -- Clear previous highlights
  self:show_help() -- Clear previous help

  for i, message in ipairs(self.messages) do
    if self.config.highlight_headers then
      -- Overlay section header with nice display
      local header_value = self.headers[message.role]
      local header_line = message.section.start_line - 2

      vim.api.nvim_buf_set_extmark(self.bufnr, highlight_ns, header_line, 0, {
        conceal = '',
        virt_text = {
          { ' ' .. header_value .. ' ', 'CopilotChatHeader' },
          { string.rep(self.separator, vim.go.columns - #header_value - 1), 'CopilotChatSeparator' },
        },
        virt_text_pos = 'overlay',
        priority = 300,
        strict = false,
      })

      -- Highlight code block headers and show file info as virtual lines
      for _, block in ipairs(message.section.blocks) do
        local header = block.header
        local filetype = header.filetype
        local filename = header.filename
        local text = string.format('[%s] %s', filetype, filename)
        if header.start_line and header.end_line then
          text = text .. string.format(' lines %d-%d', header.start_line, header.end_line)
        end
        vim.api.nvim_buf_set_extmark(self.bufnr, highlight_ns, block.start_line - 1, 0, {
          virt_lines_above = true,
          virt_lines = { { { text, 'CopilotChatAnnotationHeader' } } },
          priority = 100,
          strict = false,
        })
      end
    end

    -- Show reasoning as virtual text above assistant messages
    if
      message.role == constants.ROLE.ASSISTANT
      and not utils.empty(message.reasoning)
      and message.section
      and message.section.start_line
    then
      local virt_lines = {}
      for _, line in ipairs(vim.split(message.reasoning, '\n')) do
        table.insert(virt_lines, { { 'Reasoning: ' .. line, 'CopilotChatAnnotation' } })
      end
      vim.api.nvim_buf_set_extmark(self.bufnr, highlight_ns, message.section.start_line - 1, 0, {
        virt_lines = virt_lines,
        virt_lines_above = true,
        priority = 100,
        strict = false,
      })
    end

    -- Show tool call details as virt lines in assistant messages
    if message.tool_calls and #message.tool_calls > 0 then
      local section = message.section
      if section and section.end_line then
        local virt_lines = { { { 'Tool calls:', 'CopilotChatAnnotationHeader' } } }
        for _, tc in ipairs(message.tool_calls) do
          table.insert(virt_lines, { { string.format('  %s:%s', tc.name, tostring(tc.id)), 'CopilotChatAnnotation' } })
          for _, json_line in ipairs(vim.split(vim.inspect(utils.json_decode(tc.arguments)), '\n')) do
            table.insert(virt_lines, { { '    ' .. json_line, 'CopilotChatAnnotation' } })
          end
        end
        vim.api.nvim_buf_set_extmark(self.bufnr, highlight_ns, section.end_line - 1, 0, {
          virt_lines = virt_lines,
          virt_lines_above = true,
          priority = 100,
          strict = false,
        })
      end
    end

    -- Highlight tool calls in tool messages
    if message.tool_call_id then
      local section = message.section
      if section and section.start_line then
        local virt_lines = {
          { { 'Tool: ' .. message.tool_call_id, 'CopilotChatAnnotationHeader' } },
        }
        vim.api.nvim_buf_set_extmark(self.bufnr, highlight_ns, section.start_line - 1, 0, {
          virt_lines = virt_lines,
          virt_lines_above = true,
          priority = 100,
          strict = false,
        })
      end
    end

    if i == #self.messages and message.role == constants.ROLE.USER then
      -- Highlight tools in the last user message
      local assistant_msg = self:get_message(constants.ROLE.ASSISTANT)
      if assistant_msg and assistant_msg.tool_calls and #assistant_msg.tool_calls > 0 then
        for i, line in ipairs(utils.split_lines(message.content)) do
          for _, tool_call in ipairs(assistant_msg.tool_calls) do
            if line:match(string.format('#%s:%s', tool_call.name, vim.pesc(tool_call.id))) then
              local l = message.section.start_line - 1 + i
              vim.api.nvim_buf_add_highlight(self.bufnr, highlight_ns, 'CopilotChatAnnotationHeader', l, 0, #line)
              if not utils.empty(tool_call.arguments) then
                vim.api.nvim_buf_set_extmark(self.bufnr, highlight_ns, l - 1, 0, {
                  virt_lines = vim.tbl_map(function(json_line)
                    return { { json_line, 'CopilotChatAnnotation' } }
                  end, vim.split(vim.inspect(utils.json_decode(tool_call.arguments)), '\n')),
                  priority = 100,
                  strict = false,
                })
              end
            end
          end
        end
      end

      -- Show help message and token usage below the last user message
      local msg = self.config.show_help and self.help or ''
      if self.token_count and self.token_max_count then
        if msg ~= '' then
          msg = msg .. '\n'
        end
        msg = msg .. self.token_count .. '/' .. self.token_max_count .. ' tokens used'
      end
      self:show_help(msg, message.section.start_line - 1)
    end

    -- Auto fold non-assistant messages if enabled
    if self.config.auto_fold and self:visible() then
      if message.role ~= constants.ROLE.ASSISTANT and message.section and i < #self.messages then
        vim.api.nvim_win_call(self.winnr, function()
          local fold_level = vim.fn.foldlevel(message.section.start_line)
          if fold_level > 0 and vim.fn.foldclosed(message.section.start_line) == -1 then
            vim.api.nvim_cmd({ cmd = 'foldclose', range = { message.section.start_line } }, {})
          end
        end)
      end
    end
  end
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
