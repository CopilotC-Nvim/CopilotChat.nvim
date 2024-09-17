local default_config = require('CopilotChat.config')
local log = require('plenary.log')
local Copilot = require('CopilotChat.copilot')
local Chat = require('CopilotChat.chat')
local Overlay = require('CopilotChat.overlay')
local context = require('CopilotChat.context')
local prompts = require('CopilotChat.prompts')
local debuginfo = require('CopilotChat.debuginfo')
local tiktoken = require('CopilotChat.tiktoken')
local utils = require('CopilotChat.utils')

local M = {}
local plugin_name = 'CopilotChat.nvim'

--- @class CopilotChat.state
--- @field copilot CopilotChat.Copilot?
--- @field chat CopilotChat.Chat?
--- @field source CopilotChat.config.source?
--- @field config CopilotChat.config?
--- @field last_system_prompt string?
--- @field last_code_output string?
--- @field response string?
--- @field diff CopilotChat.Overlay?
--- @field system_prompt CopilotChat.Overlay?
--- @field user_selection CopilotChat.Overlay?
--- @field help CopilotChat.Overlay?
local state = {
  copilot = nil,
  chat = nil,
  source = nil,
  config = nil,

  -- Tracking for overlays
  last_system_prompt = nil,
  last_code_output = nil,

  -- Response for mappings
  response = nil,

  -- Overlays
  diff = nil,
  system_prompt = nil,
  user_selection = nil,
  help = nil,
}

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

local function update_prompts(prompt, system_prompt)
  local prompts_to_use = M.prompts()
  local try_again = false
  local result = string.gsub(prompt, [[/[%w_]+]], function(match)
    local found = prompts_to_use[string.sub(match, 2)]
    if found then
      if found.kind == 'user' then
        local out = found.prompt
        if out and string.match(out, [[/[%w_]+]]) then
          try_again = true
        end
        system_prompt = found.system_prompt or system_prompt
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
---@param config CopilotChat.config
local function append(str, config)
  state.chat:append(str)
  if config and config.auto_follow_cursor then
    state.chat:follow()
  end
end

local function complete()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  if col == 0 or #line == 0 then
    return
  end

  local prefix, cmp_start = unpack(vim.fn.matchstrpos(line:sub(1, col), [[\(/\|@\)\k*$]]))
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

--- Map a key to a function.
---@param key CopilotChat.config.mapping
---@param bufnr number
---@param fn function
local function map_key(key, bufnr, fn)
  if not key then
    return
  end
  if key.normal and key.normal ~= '' then
    vim.keymap.set('n', key.normal, fn, { buffer = bufnr })
  end
  if key.insert and key.insert ~= '' then
    vim.keymap.set('i', key.insert, fn, { buffer = bufnr })
  end
end

--- Get the info for a key.
---@param name string
---@param key CopilotChat.config.mapping?
---@return string
local function key_to_info(name, key)
  if not key then
    return ''
  end

  local out = ''
  if key.normal and key.normal ~= '' then
    out = out .. "'" .. key.normal .. "' in normal mode"
  end
  if key.insert and key.insert ~= '' then
    if out ~= '' then
      out = out .. ' or '
    end
    out = out .. "'" .. key.insert .. "' in insert mode"
  end

  if out == '' then
    return out
  end

  out = out .. ' to ' .. name:gsub('_', ' ')

  if key.detail and key.detail ~= '' then
    out = out .. '. ' .. key.detail
  end

  return out
end

--- Get the prompts to use.
---@param skip_system boolean|nil
---@return table<string, CopilotChat.config.prompt>
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

--- Highlights the selection in the source buffer.
---@param clear? boolean
function M.highlight_selection(clear)
  local selection_ns = vim.api.nvim_create_namespace('copilot-chat-selection')
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    vim.api.nvim_buf_clear_namespace(buf, selection_ns, 0, -1)
  end
  if clear then
    return
  end
  local selection = get_selection()
  if not selection.start_row or not selection.end_row then
    return
  end
  vim.api.nvim_buf_set_extmark(
    state.source.bufnr,
    selection_ns,
    selection.start_row - 1,
    selection.start_col - 1,
    {
      hl_group = 'CopilotChatSelection',
      end_row = selection.end_row - 1,
      end_col = selection.end_col,
      strict = false,
    }
  )
end

--- Open the chat window.
---@param config CopilotChat.config|CopilotChat.config.prompt|nil
---@param source CopilotChat.config.source?
function M.open(config, source)
  config = vim.tbl_deep_extend('force', M.config, config or {})
  state.config = config
  state.source = vim.tbl_extend('keep', source or {}, {
    bufnr = vim.api.nvim_get_current_buf(),
    winnr = vim.api.nvim_get_current_win(),
  })

  utils.return_to_normal_mode()
  state.chat:open(config)
  state.chat:follow()
  state.chat:focus()
end

--- Close the chat window.
function M.close()
  state.chat:close(state.source and state.source.bufnr or nil)
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

--- @returns string
function M.response()
  return state.response
end

--- Select a Copilot GPT model.
function M.select_model()
  state.copilot:select_model(function(models)
    vim.schedule(function()
      vim.ui.select(models, {
        prompt = 'Select a model',
      }, function(choice)
        M.config.model = choice
      end)
    end)
  end)
end

--- Ask a question to the Copilot model.
---@param prompt string
---@param config CopilotChat.config|CopilotChat.config.prompt|nil
---@param source CopilotChat.config.source?
function M.ask(prompt, config, source)
  config = vim.tbl_deep_extend('force', M.config, config or {})
  prompt = prompt or ''
  local system_prompt, updated_prompt = update_prompts(prompt, config.system_prompt)
  updated_prompt = vim.trim(updated_prompt)
  if updated_prompt == '' then
    M.open(config, source)
    return
  end

  M.open(config, source)

  if config.clear_chat_on_new_prompt then
    M.stop(true, config)
  end

  state.last_system_prompt = system_prompt
  local selection = get_selection()
  local filetype = selection.filetype
    or (vim.api.nvim_buf_is_valid(state.source.bufnr) and vim.bo[state.source.bufnr].filetype)
  local filename = selection.filename
    or (
      vim.api.nvim_buf_is_valid(state.source.bufnr)
      and vim.api.nvim_buf_get_name(state.source.bufnr)
    )
  if selection.prompt_extra then
    updated_prompt = updated_prompt .. ' ' .. selection.prompt_extra
  end

  if state.copilot:stop() then
    append('\n\n' .. config.question_header .. config.separator .. '\n\n', config)
  end

  append(updated_prompt, config)
  append('\n\n' .. config.answer_header .. config.separator .. '\n\n', config)

  local selected_context = config.context
  if string.find(prompt, '@buffers') then
    selected_context = 'buffers'
  elseif string.find(prompt, '@buffer') then
    selected_context = 'buffer'
  end
  updated_prompt = string.gsub(updated_prompt, '@buffers?%s*', '')

  local function on_error(err)
    vim.schedule(function()
      append('\n\n' .. config.error_header .. config.separator .. '\n\n', config)
      append('```\n' .. err .. '\n```', config)
      append('\n\n' .. config.question_header .. config.separator .. '\n\n', config)
      state.chat:finish()
    end)
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
        start_row = selection.start_row,
        end_row = selection.end_row,
        system_prompt = system_prompt,
        model = config.model,
        temperature = config.temperature,
        on_error = on_error,
        on_done = function(response, token_count)
          vim.schedule(function()
            append('\n\n' .. config.question_header .. config.separator .. '\n\n', config)
            state.response = response
            if tiktoken.available() and token_count and token_count > 0 then
              state.chat:finish(token_count .. ' tokens used')
            else
              state.chat:finish()
            end
            if config.callback then
              config.callback(response, state.source)
            end
          end)
        end,
        on_progress = function(token)
          vim.schedule(function()
            append(token, config)
          end)
        end,
      })
    end,
  })
end

--- Stop current copilot output and optionally reset the chat ten show the help message.
---@param reset boolean?
---@param config CopilotChat.config?
function M.stop(reset, config)
  config = vim.tbl_deep_extend('force', M.config, config or {})
  state.response = nil
  local stopped = reset and state.copilot:reset() or state.copilot:stop()
  local wrap = vim.schedule
  if not stopped then
    wrap = function(fn)
      fn()
    end
  end

  wrap(function()
    if reset then
      state.chat:clear()
    else
      append('\n\n', config)
    end
    append(M.config.question_header .. M.config.separator .. '\n\n', config)
    state.chat:finish()
  end)
end

--- Reset the chat window and show the help message.
---@param config CopilotChat.config?
function M.reset(config)
  M.stop(true, config)
end

--- Save the chat history to a file.
---@param name string?
---@param history_path string?
function M.save(name, history_path)
  if not name or vim.trim(name) == '' then
    name = 'default'
  else
    name = vim.trim(name)
  end

  history_path = history_path or M.config.history_path
  if history_path then
    state.copilot:save(name, history_path)
  end
end

--- Load the chat history from a file.
---@param name string?
---@param history_path string?
function M.load(name, history_path)
  if not name or vim.trim(name) == '' then
    name = 'default'
  else
    name = vim.trim(name)
  end

  history_path = history_path or M.config.history_path
  if not history_path then
    return
  end

  state.copilot:reset()
  state.chat:clear()

  local history = state.copilot:load(name, history_path)
  for i, message in ipairs(history) do
    if message.role == 'user' then
      if i > 1 then
        append('\n\n', state.config)
      end
      append(M.config.question_header .. M.config.separator .. '\n\n', state.config)
      append(message.content, state.config)
    elseif message.role == 'assistant' then
      append('\n\n' .. M.config.answer_header .. M.config.separator .. '\n\n', state.config)
      append(message.content, state.config)
    end
  end

  if #history > 0 then
    append('\n\n', state.config)
  end
  append(M.config.question_header .. M.config.separator .. '\n\n', state.config)

  state.chat:finish()
  M.open()
end

--- Enables/disables debug
---@param debug boolean
function M.debug(debug)
  M.config.debug = debug
  local logfile = string.format('%s/%s.log', vim.fn.stdpath('state'), plugin_name)
  log.new({
    plugin = plugin_name,
    level = debug and 'debug' or 'info',
    outfile = logfile,
  }, true)
  log.logfile = logfile
end

--- Set up the plugin
---@param config CopilotChat.config|nil
function M.setup(config)
  -- Handle old mapping format and show error
  local found_old_format = false
  if config then
    if config.mappings then
      for name, key in pairs(config.mappings) do
        if type(key) == 'string' then
          vim.notify(
            'config.mappings.'
              .. name
              .. ": 'mappings' format have changed, please update your configuration, for now revering to default settings. See ':help CopilotChat-configuration' for current format",
            vim.log.levels.ERROR
          )
          found_old_format = true
        end
      end
    end

    if config.yank_diff_register then
      vim.notify(
        'config.yank_diff_register: This option has been removed, please use mappings.yank_diff.register instead',
        vim.log.levels.ERROR
      )
    end
  end

  if found_old_format then
    config.mappings = nil
  end

  M.config = vim.tbl_deep_extend('force', default_config, config or {})
  if M.config.model == 'gpt-4o' then
    M.config.model = 'gpt-4o-2024-05-13'
  end

  if state.copilot then
    state.copilot:stop()
  else
    tiktoken.setup((config and config.model) or nil)
    debuginfo.setup()
  end
  state.copilot = Copilot(M.config.proxy, M.config.allow_insecure)
  M.debug(M.config.debug)

  local hl_ns = vim.api.nvim_create_namespace('copilot-chat-highlights')
  vim.api.nvim_set_hl(hl_ns, '@diff.plus', { bg = blend_color_with_neovim_bg('DiffAdd', 20) })
  vim.api.nvim_set_hl(hl_ns, '@diff.minus', { bg = blend_color_with_neovim_bg('DiffDelete', 20) })
  vim.api.nvim_set_hl(hl_ns, '@diff.delta', { bg = blend_color_with_neovim_bg('DiffChange', 20) })
  vim.api.nvim_set_hl(0, 'CopilotChatSpinner', { link = 'CursorColumn', default = true })
  vim.api.nvim_set_hl(0, 'CopilotChatHelp', { link = 'DiagnosticInfo', default = true })
  vim.api.nvim_set_hl(0, 'CopilotChatSelection', { link = 'Visual', default = true })
  vim.api.nvim_set_hl(
    0,
    'CopilotChatHeader',
    { link = '@markup.heading.2.markdown', default = true }
  )
  vim.api.nvim_set_hl(
    0,
    'CopilotChatSeparator',
    { link = '@punctuation.special.markdown', default = true }
  )

  local overlay_help = key_to_info('close', M.config.mappings.close)
  local diff_help = key_to_info('accept_diff', M.config.mappings.accept_diff)
  if overlay_help ~= '' and diff_help ~= '' then
    diff_help = diff_help .. '\n' .. overlay_help
  end

  if state.diff then
    state.diff:delete()
  end
  state.diff = Overlay('copilot-diff', hl_ns, diff_help, function(bufnr)
    map_key(M.config.mappings.close, bufnr, function()
      state.diff:restore(state.chat.winnr, state.chat.bufnr)
    end)

    map_key(M.config.mappings.accept_diff, bufnr, function()
      local current = state.last_code_output
      if not current then
        return
      end

      local selection = get_selection()
      if not selection.start_row or not selection.end_row then
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
    end)
  end)

  if state.system_prompt then
    state.system_prompt:delete()
  end
  state.system_prompt = Overlay('copilot-system-prompt', hl_ns, overlay_help, function(bufnr)
    map_key(M.config.mappings.close, bufnr, function()
      state.system_prompt:restore(state.chat.winnr, state.chat.bufnr)
    end)
  end)

  if state.user_selection then
    state.user_selection:delete()
  end
  state.user_selection = Overlay('copilot-user-selection', hl_ns, overlay_help, function(bufnr)
    map_key(M.config.mappings.close, bufnr, function()
      state.user_selection:restore(state.chat.winnr, state.chat.bufnr)
    end)
  end)

  if state.help then
    state.help:delete()
  end
  state.help = Overlay('copilot-help', hl_ns, overlay_help, function(bufnr)
    map_key(M.config.mappings.close, bufnr, function()
      state.help:restore(state.chat.winnr, state.chat.bufnr)
    end)
  end)

  if state.chat then
    state.chat:close(state.source and state.source.bufnr or nil)
    state.chat:delete()
  end
  state.chat = Chat(
    M.config.show_help and key_to_info('show_help', M.config.mappings.show_help),
    M.config.auto_insert_mode,
    function(bufnr)
      map_key(M.config.mappings.show_help, bufnr, function()
        local chat_help = ''
        local chat_keys = vim.tbl_keys(M.config.mappings)
        table.sort(chat_keys, function(a, b)
          a = M.config.mappings[a]
          a = a.normal or a.insert
          b = M.config.mappings[b]
          b = b.normal or b.insert
          return a < b
        end)
        for _, name in ipairs(chat_keys) do
          local key = M.config.mappings[name]
          chat_help = chat_help .. key_to_info(name, key) .. '\n'
        end
        chat_help = chat_help .. M.config.separator .. '\n'
        state.help:show(chat_help, 'markdown', 'markdown', state.chat.winnr)
      end)

      map_key(M.config.mappings.complete, bufnr, complete)
      map_key(M.config.mappings.reset, bufnr, M.reset)
      map_key(M.config.mappings.close, bufnr, M.close)

      map_key(M.config.mappings.submit_prompt, bufnr, function()
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
      end)

      map_key(M.config.mappings.accept_diff, bufnr, function()
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
      end)

      map_key(M.config.mappings.yank_diff, bufnr, function()
        local selection = get_selection()
        if not selection.start_row or not selection.end_row then
          return
        end

        local chat_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local section_lines =
          find_lines_between_separator(chat_lines, M.config.separator .. '$', true)
        local lines = find_lines_between_separator(section_lines, '^```%w*$', true)
        if #lines > 0 then
          local content = table.concat(lines, '\n')
          vim.fn.setreg(M.config.mappings.yank_diff.register, content)
        end
      end)

      map_key(M.config.mappings.show_diff, bufnr, function()
        local selection = get_selection()
        if not selection or not selection.start_row or not selection.end_row then
          return
        end

        local chat_lines = vim.api.nvim_buf_get_lines(state.chat.bufnr, 0, -1, false)
        local section_lines =
          find_lines_between_separator(chat_lines, M.config.separator .. '$', true)
        local lines =
          table.concat(find_lines_between_separator(section_lines, '^```%w*$', true), '\n')
        if vim.trim(lines) ~= '' then
          state.last_code_output = lines

          local filetype = selection.filetype or vim.bo[state.source.bufnr].filetype

          local diff = tostring(vim.diff(selection.lines, lines, {
            result_type = 'unified',
            ignore_blank_lines = true,
            ignore_whitespace = true,
            ignore_whitespace_change = true,
            ignore_whitespace_change_at_eol = true,
            ignore_cr_at_eol = true,
            algorithm = 'myers',
            ctxlen = #selection.lines,
          }))

          state.diff:show(diff, filetype, 'diff', state.chat.winnr)
        end
      end)

      map_key(M.config.mappings.show_system_prompt, bufnr, function()
        local prompt = state.last_system_prompt or M.config.system_prompt
        if not prompt then
          return
        end

        state.system_prompt:show(prompt, 'markdown', 'markdown', state.chat.winnr)
      end)

      map_key(M.config.mappings.show_user_selection, bufnr, function()
        local selection = get_selection()
        if not selection.start_row or not selection.end_row then
          return
        end

        local filetype = selection.filetype or vim.bo[state.source.bufnr].filetype
        local lines = selection.lines
        if vim.trim(lines) ~= '' then
          state.user_selection:show(lines, filetype, filetype, state.chat.winnr)
        end
      end)

      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufLeave' }, {
        buffer = state.chat.bufnr,
        callback = function(ev)
          if state.config.highlight_selection then
            M.highlight_selection(ev.event == 'BufLeave')
          end
        end,
      })

      if M.config.insert_at_end then
        vim.api.nvim_create_autocmd({ 'InsertEnter' }, {
          buffer = state.chat.bufnr,
          callback = function()
            vim.cmd('normal! 0')
            vim.cmd('normal! G$')
            vim.v.char = 'x'
          end,
        })
      end

      append(M.config.question_header .. M.config.separator .. '\n\n', M.config)
      state.chat:finish()
    end
  )

  for name, prompt in pairs(M.prompts(true)) do
    vim.api.nvim_create_user_command('CopilotChat' .. name, function(args)
      local input = prompt.prompt
      if args.args and vim.trim(args.args) ~= '' then
        input = input .. ' ' .. args.args
      end
      if input then
        M.ask(input, prompt)
      end
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

  vim.api.nvim_create_user_command('CopilotChatModel', function()
    -- Show which model is being used in an alert
    vim.notify('Using model: ' .. M.config.model, vim.log.levels.INFO)
  end, { force = true })

  vim.api.nvim_create_user_command('CopilotChatModels', function()
    M.select_model()
  end, { force = true })

  vim.api.nvim_create_user_command('CopilotChatOpen', function()
    M.open()
  end, { force = true })
  vim.api.nvim_create_user_command('CopilotChatClose', function()
    M.close()
  end, { force = true })
  vim.api.nvim_create_user_command('CopilotChatToggle', function()
    M.toggle()
  end, { force = true })
  vim.api.nvim_create_user_command('CopilotChatStop', function()
    M.stop()
  end, { force = true })
  vim.api.nvim_create_user_command('CopilotChatReset', function()
    M.reset()
  end, { force = true })

  local function complete_load()
    local options = vim.tbl_map(function(file)
      return vim.fn.fnamemodify(file, ':t:r')
    end, vim.fn.glob(M.config.history_path .. '/*', true, true))

    if not vim.tbl_contains(options, 'default') then
      table.insert(options, 1, 'default')
    end

    return options
  end

  vim.api.nvim_create_user_command('CopilotChatSave', function(args)
    M.save(args.args)
  end, { nargs = '*', force = true, complete = complete_load })
  vim.api.nvim_create_user_command('CopilotChatLoad', function(args)
    M.load(args.args)
  end, { nargs = '*', force = true, complete = complete_load })
end

return M
