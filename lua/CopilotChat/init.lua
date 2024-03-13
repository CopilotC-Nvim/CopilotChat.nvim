local default_config = require('CopilotChat.config')
local log = require('plenary.log')
local Copilot = require('CopilotChat.copilot')
local Chat = require('CopilotChat.chat')
local Diff = require('CopilotChat.diff')
local context = require('CopilotChat.context')
local prompts = require('CopilotChat.prompts')
local debuginfo = require('CopilotChat.debuginfo')
local tiktoken = require('CopilotChat.tiktoken')

local M = {}
local plugin_name = 'CopilotChat.nvim'

--- @class CopilotChat.state
--- @field copilot CopilotChat.Copilot?
--- @field chat CopilotChat.Chat?
--- @field diff CopilotChat.Diff?
--- @field source CopilotChat.config.source?
--- @field config CopilotChat.config?
local state = {
  copilot = nil,
  chat = nil,
  diff = nil,
  source = nil,
  config = nil,
}

local function find_lines_between_separator(lines, pattern, at_least_one)
  local line_count = #lines
  local separator_line_start = 1
  local separator_line_finish = line_count
  local found_one = false

  -- Find the last occurrence of the separator
  for i = line_count, 1, -1 do -- Reverse the loop to start from the end
    local line = lines[i]
    if string.find(line, pattern) then
      if i < (separator_line_finish + 1) and (not at_least_one or found_one) then
        separator_line_start = i + 1
        break -- Exit the loop as soon as the condition is met
      end

      found_one = true
      separator_line_finish = i - 1
    end
  end

  if at_least_one and not found_one then
    return {}, 1, 1, 0
  end

  -- Extract everything between the last and next separator
  local result = {}
  for i = separator_line_start, separator_line_finish do
    table.insert(result, lines[i])
  end

  return result, separator_line_start, separator_line_finish, line_count
end

local function show_diff_between_selection_and_copilot(selection)
  if not selection or not selection.start_row or not selection.end_row then
    return
  end

  local chat_lines = vim.api.nvim_buf_get_lines(state.chat.bufnr, 0, -1, false)
  local section_lines = find_lines_between_separator(chat_lines, M.config.separator .. '$', true)
  local lines = find_lines_between_separator(section_lines, '^```%w*$', true)
  if #lines > 0 then
    local filetype = selection.filetype or vim.bo[state.source.bufnr].filetype
    state.diff:show(selection.lines, table.concat(lines, '\n'), filetype, state.chat.winnr)
  end
end

local function update_prompts(prompt, system_prompt)
  local prompts_to_use = M.prompts()
  local try_again = false
  local result = string.gsub(prompt, [[/[%w_]+]], function(match)
    local found = prompts_to_use[string.sub(match, 2)]
    if found then
      if found.kind == 'user' then
        local out = found.prompt
        if string.match(out, [[/[%w_]+]]) then
          try_again = true
        end
        return out
      elseif found.kind == 'system' then
        system_prompt = found.prompt
        return ''
      end
    end

    return match
  end)

  if try_again then
    return update_prompts(result, system_prompt)
  end

  return system_prompt, result
end

--- Append a string to the chat window.
---@param str (string)
local function append(str)
  vim.schedule(function()
    state.chat:append(str)
    if M.config.auto_follow_cursor then
      state.chat:follow()
    end
  end)
end

local function show_help()
  local out = 'Press '
  for name, key in pairs(M.config.mappings) do
    if key then
      out = out .. "'" .. key .. "' to " .. name:gsub('_', ' ') .. ', '
    end
  end

  out = out
    .. 'use @'
    .. M.config.mappings.complete
    .. ' or /'
    .. M.config.mappings.complete
    .. ' for different options.'
  state.chat.spinner:finish()
  state.chat.spinner:set(out, -1)
end

local function complete()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  if col == 0 or #line == 0 then
    return
  end

  local prefix, cmp_start = unpack(vim.fn.matchstrpos(line:sub(1, col), '\\/\\|@\\k*$'))
  if not prefix then
    return
  end

  local items = {}
  local prompts_to_use = M.prompts()

  for name, prompt in pairs(prompts_to_use) do
    items[#items + 1] = {
      word = '/' .. name,
      kind = prompt.kind,
      info = prompt.prompt,
      menu = prompt.description or '',
      icase = 1,
      dup = 0,
      empty = 0,
    }
  end

  items[#items + 1] = {
    word = '@buffers',
    kind = 'context',
    menu = 'Use all loaded buffers as context',
    icase = 1,
    dup = 0,
    empty = 0,
  }

  items[#items + 1] = {
    word = '@buffer',
    kind = 'context',
    menu = 'Use the current buffer as context',
    icase = 1,
    dup = 0,
    empty = 0,
  }

  items = vim.tbl_filter(function(item)
    return vim.startswith(item.word:lower(), prefix:lower())
  end, items)

  vim.fn.complete(cmp_start + 1, items)
end

local function get_selection()
  local bufnr = state.source.bufnr
  local winnr = state.source.winnr
  if
    state.config
    and state.config.selection
    and vim.api.nvim_buf_is_valid(bufnr)
    and vim.api.nvim_win_is_valid(winnr)
  then
    return state.config.selection(state.source) or {}
  end
  return {}
end

--- Get the prompts to use.
---@param skip_system boolean|nil
function M.prompts(skip_system)
  local function get_prompt_kind(name)
    return vim.startswith(name, 'COPILOT_') and 'system' or 'user'
  end

  local prompts_to_use = {}

  if not skip_system then
    for name, prompt in pairs(prompts) do
      prompts_to_use[name] = {
        prompt = prompt,
        kind = get_prompt_kind(name),
      }
    end
  end

  for name, prompt in pairs(M.config.prompts) do
    local val = prompt
    if type(prompt) == 'string' then
      val = {
        prompt = prompt,
        kind = get_prompt_kind(name),
      }
    elseif not val.kind then
      val.kind = get_prompt_kind(name)
    end

    prompts_to_use[name] = val
  end

  return prompts_to_use
end

--- Open the chat window.
---@param config CopilotChat.config?
---@param source CopilotChat.config.source?
function M.open(config, source, no_focus)
  local should_reset = config and config.window ~= nil and not vim.tbl_isempty(config.window)
  config = vim.tbl_deep_extend('force', M.config, config or {})
  state.config = config
  state.source = vim.tbl_extend('keep', source or {}, {
    bufnr = vim.api.nvim_get_current_buf(),
    winnr = vim.api.nvim_get_current_win(),
  })

  -- Exit visual mode if we are in visual mode
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<esc>', true, false, true), 'x', false)

  -- Recreate the window if the layout has changed
  if should_reset then
    M.close()
  end

  state.chat:open(config)
  if not no_focus then
    state.chat:focus()
    state.chat:follow()
  end
end

--- Close the chat window and stop the Copilot model.
function M.close()
  state.copilot:stop()
  state.chat:close()
end

--- Toggle the chat window.
---@param config CopilotChat.config|nil
---@param source CopilotChat.config.source?
function M.toggle(config, source)
  if state.chat:visible() then
    M.close()
  else
    M.open(config, source)
  end
end

--- Ask a question to the Copilot model.
---@param prompt string
---@param config CopilotChat.config|nil
---@param source CopilotChat.config.source?
function M.ask(prompt, config, source)
  M.open(config, source, true)

  config = vim.tbl_deep_extend('force', M.config, config or {})
  local selection = get_selection()
  state.chat:focus()

  prompt = prompt or ''
  local system_prompt, updated_prompt = update_prompts(prompt, config.system_prompt)
  if vim.trim(prompt) == '' then
    return
  end

  if config.clear_chat_on_new_prompt then
    M.reset()
  end

  local filetype = selection.filetype or vim.bo[state.source.bufnr].filetype
  local filename = selection.filename or vim.api.nvim_buf_get_name(state.source.bufnr)
  if selection.prompt_extra then
    updated_prompt = updated_prompt .. ' ' .. selection.prompt_extra
  end

  local finish = false
  if config.show_system_prompt then
    finish = true
    append(' **System prompt** ' .. config.separator .. '\n```\n' .. system_prompt .. '```\n')
  end
  if config.show_user_selection and selection.lines and selection.lines ~= '' then
    finish = true
    append(
      ' **Selection** '
        .. config.separator
        .. '\n```'
        .. (filetype or '')
        .. '\n'
        .. selection.lines
        .. '\n```'
    )
  end
  if finish then
    append('\n' .. config.separator .. '\n\n')
  end

  append(updated_prompt)
  append('\n\n **' .. config.name .. '** ' .. config.separator .. '\n\n')
  state.chat:follow()
  state.chat.spinner:start()

  local selected_context = config.context
  if string.find(prompt, '@buffers') then
    selected_context = 'buffers'
  elseif string.find(prompt, '@buffer') then
    selected_context = 'buffer'
  end
  updated_prompt = string.gsub(updated_prompt, '@buffers?%s*', '')

  local function on_error(err)
    append('\n\n **Error** ' .. config.separator .. '\n\n')
    append('```\n' .. err .. '\n```')
    append('\n\n' .. config.separator .. '\n\n')
    show_help()
  end

  context.find_for_query(state.copilot, {
    context = selected_context,
    prompt = updated_prompt,
    selection = selection.lines,
    filename = filename,
    filetype = filetype,
    bufnr = state.source.bufnr,
    on_error = on_error,
    on_done = function(embeddings)
      state.copilot:ask(updated_prompt, {
        selection = selection.lines,
        embeddings = embeddings,
        filename = filename,
        filetype = filetype,
        system_prompt = system_prompt,
        model = config.model,
        temperature = config.temperature,
        on_error = on_error,
        on_done = function(_, token_count)
          if tiktoken.available() and token_count and token_count > 0 then
            append('\n\n' .. token_count .. ' tokens used')
          end
          append('\n\n' .. config.separator .. '\n\n')
          show_help()
        end,
        on_progress = function(token)
          append(token)
        end,
      })
    end,
  })
end

--- Reset the chat window and show the help message.
function M.reset()
  state.copilot:reset()
  state.chat:clear()
  append('\n')
  show_help()
end

--- Enables/disables debug
---@param debug boolean
function M.debug(debug)
  M.config.debug = debug
  local logfile = string.format('%s/%s.log', vim.fn.stdpath('state'), plugin_name)
  log.new({
    plugin = plugin_name,
    level = debug and 'debug' or 'warn',
    outfile = logfile,
  }, true)
  log.logfile = logfile
end

--- Set up the plugin
---@param config CopilotChat.config|nil
function M.setup(config)
  M.config = vim.tbl_deep_extend('force', default_config, config or {})
  state.copilot = Copilot(M.config.proxy, M.config.allow_insecure)

  state.diff = Diff(
    function(bufnr)
      if M.config.mappings.close then
        vim.keymap.set('n', M.config.mappings.close, function()
          state.diff:restore(state.chat.winnr, state.chat.bufnr)
        end, { buffer = bufnr })
      end
      if M.config.mappings.accept_diff then
        vim.keymap.set('n', M.config.mappings.accept_diff, function()
          local selection = get_selection()
          if not selection.start_row or not selection.end_row then
            return
          end

          local current = state.diff.current
          if not current then
            return
          end

          local lines = vim.split(current, '\n')
          if #lines > 0 then
            vim.api.nvim_buf_set_text(
              state.source.bufnr,
              selection.start_row - 1,
              selection.start_col - 1,
              selection.end_row - 1,
              selection.end_col,
              lines
            )
          end
        end, { buffer = bufnr })
      end
    end,
    "Press '"
      .. M.config.mappings.close
      .. "' to close diff, '"
      .. M.config.mappings.accept_diff
      .. "' to accept diff."
  )

  state.chat = Chat(function(bufnr)
    if M.config.mappings.complete then
      vim.keymap.set('i', M.config.mappings.complete, complete, { buffer = bufnr })
    end

    if M.config.mappings.reset then
      vim.keymap.set('n', M.config.mappings.reset, M.reset, { buffer = bufnr })
    end

    if M.config.mappings.close then
      vim.keymap.set('n', M.config.mappings.close, M.close, { buffer = bufnr })
    end

    if M.config.mappings.submit_prompt then
      vim.keymap.set('n', M.config.mappings.submit_prompt, function()
        local chat_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local lines, start_line, end_line, line_count =
          find_lines_between_separator(chat_lines, M.config.separator .. '$')
        local input = vim.trim(table.concat(lines, '\n'))
        if input ~= '' then
          -- If we are entering the input at the end, replace it
          if line_count == end_line then
            vim.api.nvim_buf_set_lines(bufnr, start_line, end_line, false, { '' })
          end
          M.ask(input, state.config, state.source)
        end
      end, { buffer = bufnr })
    end

    if M.config.mappings.show_diff then
      vim.keymap.set('n', M.config.mappings.show_diff, function()
        local selection = get_selection()
        show_diff_between_selection_and_copilot(selection)
      end, {
        buffer = bufnr,
      })
    end

    if M.config.mappings.accept_diff then
      vim.keymap.set('n', M.config.mappings.accept_diff, function()
        local selection = get_selection()
        if not selection.start_row or not selection.end_row then
          return
        end

        local chat_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local section_lines =
          find_lines_between_separator(chat_lines, M.config.separator .. '$', true)
        local lines = find_lines_between_separator(section_lines, '^```%w*$', true)
        if #lines > 0 then
          vim.api.nvim_buf_set_text(
            state.source.bufnr,
            selection.start_row - 1,
            selection.start_col - 1,
            selection.end_row - 1,
            selection.end_col,
            lines
          )
        end
      end, { buffer = bufnr })
    end

    M.reset()
  end)

  tiktoken.setup(M.config.enable_tiktoken)
  debuginfo.setup()
  M.debug(M.config.debug)

  for name, prompt in pairs(M.prompts(true)) do
    vim.api.nvim_create_user_command('CopilotChat' .. name, function(args)
      local input = prompt.prompt
      if args.args and vim.trim(args.args) ~= '' then
        input = input .. ' ' .. args.args
      end
      M.ask(input, prompt)
    end, {
      nargs = '*',
      force = true,
      range = true,
      desc = prompt.description or (plugin_name .. ' ' .. name),
    })

    if prompt.mapping then
      vim.keymap.set({ 'n', 'v' }, prompt.mapping, function()
        M.ask(prompt.prompt, prompt)
      end, { desc = prompt.description or (plugin_name .. ' ' .. name) })
    end
  end

  vim.api.nvim_create_user_command('CopilotChat', function(args)
    M.ask(args.args)
  end, {
    nargs = '*',
    force = true,
    range = true,
  })

  vim.api.nvim_create_user_command('CopilotChatOpen', M.open, { force = true })
  vim.api.nvim_create_user_command('CopilotChatClose', M.close, { force = true })
  vim.api.nvim_create_user_command('CopilotChatToggle', M.toggle, { force = true })
  vim.api.nvim_create_user_command('CopilotChatReset', M.reset, { force = true })
end

return M
