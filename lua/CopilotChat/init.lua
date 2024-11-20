local default_config = require('CopilotChat.config')
local async = require('plenary.async')
local log = require('plenary.log')
local Copilot = require('CopilotChat.copilot')
local Chat = require('CopilotChat.chat')
local Diff = require('CopilotChat.diff')
local Overlay = require('CopilotChat.overlay')
local context = require('CopilotChat.context')
local prompts = require('CopilotChat.prompts')
local debuginfo = require('CopilotChat.debuginfo')
local utils = require('CopilotChat.utils')

local M = {}
local plugin_name = 'CopilotChat.nvim'

--- @class CopilotChat.state
--- @field copilot CopilotChat.Copilot?
--- @field source CopilotChat.config.source?
--- @field config CopilotChat.config?
--- @field last_prompt string?
--- @field last_response string?
--- @field chat CopilotChat.Chat?
--- @field diff CopilotChat.Diff?
--- @field system_prompt CopilotChat.Overlay?
--- @field user_selection CopilotChat.Overlay?
--- @field help CopilotChat.Overlay?
local state = {
  copilot = nil,

  -- Current state tracking
  source = nil,
  config = nil,

  -- Last state tracking
  last_prompt = nil,
  last_response = nil,

  -- Overlays
  chat = nil,
  diff = nil,
  system_prompt = nil,
  user_selection = nil,
  help = nil,
}

---@param config CopilotChat.config
---@return CopilotChat.config.selection?
local function get_selection(config)
  local bufnr = state.source and state.source.bufnr
  local winnr = state.source and state.source.winnr

  if
    config
    and config.selection
    and utils.buf_valid(bufnr)
    and winnr
    and vim.api.nvim_win_is_valid(winnr)
  then
    return state.config.selection(state.source)
  end

  return nil
end

---@param prompt string
---@param system_prompt string
---@return string, string
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

--- Highlights the selection in the source buffer.
---@param clear? boolean
local function highlight_selection(clear)
  local selection_ns = vim.api.nvim_create_namespace('copilot-chat-selection')
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    vim.api.nvim_buf_clear_namespace(buf, selection_ns, 0, -1)
  end

  if clear then
    return
  end

  local selection = get_selection(state.config)
  if not selection or not selection.start_line or not utils.buf_valid(selection.bufnr) then
    return
  end

  vim.api.nvim_buf_set_extmark(selection.bufnr, selection_ns, selection.start_line - 1, 0, {
    hl_group = 'CopilotChatSelection',
    end_row = selection.end_line,
    strict = false,
  })
end

--- Updates the selection based on previous window
local function update_selection()
  local prev_winnr = vim.fn.win_getid(vim.fn.winnr('#'))
  if prev_winnr ~= state.chat.winnr and vim.fn.win_gettype(prev_winnr) == '' then
    state.source = {
      bufnr = vim.api.nvim_win_get_buf(prev_winnr),
      winnr = prev_winnr,
    }
  end

  highlight_selection()
end

---@return string?, number?, number?
local function match_header(header)
  if not header then
    return
  end

  local header_filename, header_start_line, header_end_line =
    header:match('%[file:.+%]%((.+)%) line:(%d+)-(%d+)')
  if not header_filename then
    header_filename, header_start_line, header_end_line =
      header:match('%[file:(.+)%] line:(%d+)-(%d+)')
  end

  if header_filename then
    header_filename = vim.fn.fnamemodify(header_filename, ':p:.')
    header_start_line = tonumber(header_start_line) or 1
    header_end_line = tonumber(header_end_line) or header_start_line
  end

  return header_filename, header_start_line, header_end_line
end

---@return CopilotChat.Diff.diff|nil
local function get_diff()
  local chat_lines = vim.api.nvim_buf_get_lines(state.chat.bufnr, 0, -1, false)
  local current_line = vim.api.nvim_win_get_cursor(0)[1]
  local section, section_start =
    utils.find_lines(chat_lines, current_line, M.config.separator .. '$')
  local change, change_start =
    utils.find_lines(section, current_line - section_start, '^```%w+$', '^```$')

  -- If no change block found, return nil
  if not change or #change == 0 then
    return nil
  end

  -- Try to get header info first
  local header = section[change_start - 2]
  local header_filename, header_start_line, header_end_line = match_header(header)

  -- Initialize variables with selection if available
  local selection = get_selection(state.config)
  local reference = selection and selection.content
  local start_line = selection and selection.start_line
  local end_line = selection and selection.end_line
  local filename = selection and selection.filename
  local filetype = selection and selection.filetype
  local bufnr = selection and selection.bufnr

  -- If we have header info, use it as source of truth
  if header_filename and header_start_line and header_end_line then
    -- Try to find matching buffer and window
    bufnr = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local win_buf = vim.api.nvim_win_get_buf(win)
      if utils.filename_same(vim.api.nvim_buf_get_name(win_buf), header_filename) then
        bufnr = win_buf
        break
      end
    end

    filename = header_filename
    filetype = vim.filetype.match({ filename = filename })
    start_line = header_start_line
    end_line = header_end_line

    -- If we found a valid buffer, get the reference content
    if bufnr and utils.buf_valid(bufnr) then
      reference =
        table.concat(vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false), '\n')
      filetype = vim.bo[bufnr].filetype
    end
  end

  -- If we don't have either selection or valid header info, we can't proceed
  if not start_line or not end_line then
    return nil
  end

  return {
    change = table.concat(change, '\n'),
    reference = reference or '',
    filename = filename or 'unknown',
    filetype = filetype or 'text',
    start_line = start_line,
    end_line = end_line,
    bufnr = bufnr,
  }
end

---@param diff CopilotChat.Diff.diff?
local function apply_diff(diff)
  if not diff or not diff.bufnr then
    return
  end

  local winnr = vim.fn.win_findbuf(diff.bufnr)[1]
  if not winnr then
    return
  end

  local lines = vim.split(diff.change, '\n', { trimempty = false })

  -- Update the source buffer with the change
  vim.api.nvim_buf_set_lines(diff.bufnr, diff.start_line - 1, diff.end_line, false, lines)

  -- Update visual selection marks to the diff start/end and move cursor
  vim.api.nvim_win_set_cursor(winnr, { diff.start_line, 0 })
  vim.api.nvim_buf_set_mark(diff.bufnr, '<', diff.start_line, 0, {})
  vim.api.nvim_buf_set_mark(diff.bufnr, '>', diff.start_line + #lines - 1, 0, {})
  update_selection()
end

local function finish(config, message, hide_help, start_of_chat)
  if config.no_chat then
    return
  end

  if not start_of_chat then
    state.chat:append('\n\n')
  end

  state.chat:append(config.question_header .. config.separator .. '\n\n')

  local offset = 0

  if state.last_prompt then
    for sticky_line in state.last_prompt:gmatch('(>%s+[^\n]+)') do
      state.chat:append(sticky_line .. '\n')
      -- Account for sticky line
      offset = offset + 1
    end

    if offset > 0 then
      state.chat:append('\n')
      -- Account for new line after sticky lines
      offset = offset + 1
    end
  end

  -- Account for double new line after separator
  offset = offset + 2

  if not hide_help then
    state.chat:finish(message, offset)
  end
end

local function show_error(config, err, append_newline)
  log.error(vim.inspect(err))

  if config.no_chat then
    return
  end

  if type(err) == 'string' then
    local message = err:match('^[^:]+:[^:]+:(.+)') or err
    message = message:gsub('^%s*', '')
    err = message
  else
    err = vim.inspect(err)
  end

  if append_newline then
    state.chat:append('\n')
  end

  state.chat:append(config.error_header .. '\n```error\n' .. err .. '\n```')
  finish(config)
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
    vim.keymap.set('n', key.normal, fn, { buffer = bufnr, nowait = true })
  end
  if key.insert and key.insert ~= '' then
    vim.keymap.set('i', key.insert, fn, { buffer = bufnr })
  end
end

--- Get the info for a key.
---@param name string
---@param key CopilotChat.config.mapping?
---@param surround string|nil
---@return string
local function key_to_info(name, key, surround)
  if not key then
    return ''
  end

  if not surround then
    surround = ''
  end

  local out = ''
  if key.normal and key.normal ~= '' then
    out = out .. surround .. key.normal .. surround
  end
  if key.insert and key.insert ~= '' and key.insert ~= key.normal then
    if out ~= '' then
      out = out .. ' or '
    end
    out = out .. surround .. key.insert .. surround .. ' in insert mode'
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

local function trigger_complete()
  local info = M.complete_info()
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_get_current_line()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  local col = cursor[2]
  if col == 0 or #line == 0 then
    return
  end

  local prefix, cmp_start = unpack(vim.fn.matchstrpos(line:sub(1, col), info.pattern))
  if not prefix then
    return
  end

  if vim.startswith(prefix, '#') and vim.endswith(prefix, ':') then
    local found_context = M.config.contexts[prefix:sub(2, -2)]
    if found_context and found_context.input then
      found_context.input(function(value)
        if not value then
          return
        end

        vim.api.nvim_buf_set_text(bufnr, row - 1, col, row - 1, col, { tostring(value) })
      end)
    end

    return
  end

  M.complete_items(function(items)
    if vim.fn.mode() ~= 'i' then
      return
    end

    vim.fn.complete(
      cmp_start + 1,
      vim.tbl_filter(function(item)
        return vim.startswith(item.word:lower(), prefix:lower())
      end, items)
    )
  end)
end

--- Get the completion info for the chat window, for use with custom completion providers
---@return table
function M.complete_info()
  return {
    triggers = { '@', '/', '#', '$' },
    pattern = [[\%(@\|/\|#\|\$\)\S*]],
  }
end

--- Get the completion items for the chat window, for use with custom completion providers
---@param callback function(table)
function M.complete_items(callback)
  async.run(function()
    local models = state.copilot:list_models()
    local agents = state.copilot:list_agents()
    local prompts_to_use = M.prompts()
    local items = {}

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

    for name, description in pairs(models) do
      items[#items + 1] = {
        word = '$' .. name,
        kind = 'model',
        menu = description,
        icase = 1,
        dup = 0,
        empty = 0,
      }
    end

    for name, description in pairs(agents) do
      items[#items + 1] = {
        word = '@' .. name,
        kind = 'agent',
        menu = description,
        icase = 1,
        dup = 0,
        empty = 0,
      }
    end

    for name, value in pairs(M.config.contexts) do
      items[#items + 1] = {
        word = '#' .. name,
        kind = 'context',
        menu = value.description or '',
        icase = 1,
        dup = 0,
        empty = 0,
      }
    end

    table.sort(items, function(a, b)
      return a.kind < b.kind
    end)

    vim.schedule(function()
      callback(items)
    end)
  end)
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

--- Open the chat window.
---@param config CopilotChat.config|CopilotChat.config.prompt|nil
function M.open(config)
  -- If we are already in chat window, do nothing
  if state.chat:active() then
    return
  end

  config = vim.tbl_deep_extend('force', M.config, config or {})
  state.config = config
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
function M.toggle(config)
  if state.chat:visible() then
    M.close()
  else
    M.open(config)
  end
end

--- @returns string
function M.response()
  return state.last_response
end

--- Select a Copilot GPT model.
function M.select_model()
  async.run(function()
    local models = vim.tbl_keys(state.copilot:list_models())
    models = vim.tbl_map(function(model)
      if model == M.config.model then
        return model .. ' (selected)'
      end

      return model
    end, models)

    vim.schedule(function()
      vim.ui.select(models, {
        prompt = 'Select a model> ',
      }, function(choice)
        if choice then
          M.config.model = choice:gsub(' %(selected%)', '')
        end
      end)
    end)
  end)
end

--- Select a Copilot agent.
function M.select_agent()
  async.run(function()
    local agents = vim.tbl_keys(state.copilot:list_agents())
    agents = vim.tbl_map(function(agent)
      if agent == M.config.agent then
        return agent .. ' (selected)'
      end

      return agent
    end, agents)

    vim.schedule(function()
      vim.ui.select(agents, {
        prompt = 'Select an agent> ',
      }, function(choice)
        if choice then
          M.config.agent = choice:gsub(' %(selected%)', '')
        end
      end)
    end)
  end)
end

--- Ask a question to the Copilot model.
---@param prompt string
---@param config CopilotChat.config|CopilotChat.config.prompt|nil
function M.ask(prompt, config)
  config = vim.tbl_deep_extend('force', M.config, config or {})
  vim.diagnostic.reset(vim.api.nvim_create_namespace('copilot_diagnostics'))

  if not config.no_chat then
    M.open(config)
  end

  prompt = vim.trim(prompt or '')
  if prompt == '' then
    return
  end

  if not config.no_chat then
    if config.clear_chat_on_new_prompt then
      M.stop(true, config)
    elseif state.copilot:stop() then
      finish(config, nil, true)
    end

    state.last_prompt = prompt

    -- Clear the current input prompt before asking a new question
    local chat_lines = vim.api.nvim_buf_get_lines(state.chat.bufnr, 0, -1, false)
    local _, start_line, end_line =
      utils.find_lines(chat_lines, #chat_lines, M.config.separator .. '$', nil, true)
    if #chat_lines == end_line then
      vim.api.nvim_buf_set_lines(state.chat.bufnr, start_line, end_line, false, { '' })
    end

    state.chat:append(prompt)
    state.chat:append('\n\n' .. config.answer_header .. config.separator .. '\n\n')
  end

  -- Resolve prompt references
  local system_prompt, updated_prompt = update_prompts(prompt, config.system_prompt)

  -- Remove sticky prefix
  prompt = table.concat(
    vim.tbl_map(function(l)
      return l:gsub('>%s+', '')
    end, vim.split(updated_prompt, '\n')),
    '\n'
  )

  local embedding_map = {}
  local function parse_context(prompt_context)
    local split = vim.split(prompt_context, ':')
    local context_name = table.remove(split, 1)
    local context_input = vim.trim(table.concat(split, ':'))
    local context_value = config.contexts[context_name]
    if context_input == '' then
      context_input = nil
    end

    if context_value then
      for _, embedding in ipairs(context_value.resolve(context_input, state.source)) do
        if embedding then
          embedding_map[embedding.filename] = embedding
        end
      end

      prompt = prompt:gsub('#' .. prompt_context .. '%s*', '')
    end
  end

  -- Sort and parse contexts
  local contexts = {}
  if config.context then
    table.insert(contexts, config.context)
  end
  for prompt_context in prompt:gmatch('#([^%s]+)') do
    table.insert(contexts, prompt_context)
  end
  table.sort(contexts, function(a, b)
    return #a > #b
  end)
  for _, prompt_context in ipairs(contexts) do
    parse_context(prompt_context)
  end
  local embeddings = vim.tbl_values(embedding_map)

  -- Retrieve the selection
  local selection = get_selection(config)

  async.run(function()
    local agents = vim.tbl_keys(state.copilot:list_agents())
    local selected_agent = config.agent
    for agent in prompt:gmatch('@([^%s]+)') do
      if vim.tbl_contains(agents, agent) then
        selected_agent = agent
        prompt = prompt:gsub('@' .. agent .. '%s*', '')
      end
    end

    local models = vim.tbl_keys(state.copilot:list_models())
    local has_output = false
    local selected_model = config.model
    for model in prompt:gmatch('%$([^%s]+)') do
      if vim.tbl_contains(models, model) then
        selected_model = model
        prompt = prompt:gsub('%$' .. model .. '%s*', '')
      end
    end

    local query_ok, filtered_embeddings =
      pcall(context.filter_embeddings, state.copilot, prompt, embeddings)

    if not query_ok then
      vim.schedule(function()
        show_error(config, filtered_embeddings, has_output)
      end)
      return
    end

    local ask_ok, response, token_count, token_max_count =
      pcall(state.copilot.ask, state.copilot, prompt, {
        selection = selection,
        embeddings = filtered_embeddings,
        system_prompt = system_prompt,
        model = selected_model,
        agent = selected_agent,
        temperature = config.temperature,
        no_history = config.no_chat,
        on_progress = function(token)
          vim.schedule(function()
            if not config.no_chat then
              state.chat:append(token)
            end

            has_output = true
          end)
        end,
      })

    if not ask_ok then
      vim.schedule(function()
        show_error(config, response, has_output)
      end)
      return
    end

    if not response then
      return
    end

    if not config.no_chat then
      state.last_response = response
    end

    vim.schedule(function()
      if token_count and token_max_count and token_count > 0 then
        finish(config, token_count .. '/' .. token_max_count .. ' tokens used')
      else
        finish(config)
      end

      if config.callback then
        config.callback(response, state.source)
      end
    end)
  end)
end

--- Stop current copilot output and optionally reset the chat ten show the help message.
---@param reset boolean?
---@param config CopilotChat.config?
function M.stop(reset, config)
  config = vim.tbl_deep_extend('force', M.config, config or {})
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
      state.last_prompt = nil
      state.last_response = nil
    end

    finish(config, nil, nil, reset)
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
        state.chat:append('\n\n')
      end
      state.chat:append(M.config.question_header .. M.config.separator .. '\n\n')
      state.chat:append(message.content)
    elseif message.role == 'assistant' then
      state.chat:append('\n\n' .. M.config.answer_header .. M.config.separator .. '\n\n')
      state.chat:append(message.content)
    end
  end

  finish(M.config, nil, nil, #history == 0)
  M.open()
end

--- Set the log level
---@param level string
function M.log_level(level)
  M.config.log_level = level
  M.config.debug = level == 'debug'
  local logfile = string.format('%s/%s.log', vim.fn.stdpath('state'), plugin_name)
  log.new({
    plugin = plugin_name,
    level = level,
    outfile = logfile,
  }, true)
  log.logfile = logfile
end

--- Set up the plugin
---@param config CopilotChat.config|nil
function M.setup(config)
  -- Handle changed configuration
  if config then
    if config.mappings then
      for name, key in pairs(config.mappings) do
        if type(key) == 'string' then
          utils.deprecate(
            'config.mappings.' .. name,
            'config.mappings.' .. name .. '.normal and config.mappings.' .. name .. '.insert'
          )

          config.mappings[name] = {
            normal = key,
          }
        end
      end
    end

    if config.yank_diff_register then
      utils.deprecate('config.yank_diff_register', 'config.mappings.yank_diff.register')
      config.mappings.yank_diff.register = config.yank_diff_register
    end
  end

  -- Handle removed commands
  vim.api.nvim_create_user_command('CopilotChatFixDiagnostic', function()
    utils.deprecate('CopilotChatFixDiagnostic', 'CopilotChatFix')
    M.ask('/Fix')
  end, { force = true })
  vim.api.nvim_create_user_command('CopilotChatCommitStaged', function()
    utils.deprecate('CopilotChatCommitStaged', 'CopilotChatCommit')
    M.ask('/Commit')
  end, { force = true })

  M.config = vim.tbl_deep_extend('force', default_config, config or {})

  if state.copilot then
    state.copilot:stop()
  end

  state.copilot = Copilot(M.config.proxy, M.config.allow_insecure)

  if M.config.debug then
    M.log_level('debug')
  else
    M.log_level(M.config.log_level)
  end

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
  state.diff = Diff(diff_help, function(bufnr)
    map_key(M.config.mappings.close, bufnr, function()
      state.diff:restore(state.chat.winnr, state.chat.bufnr)
    end)

    map_key(M.config.mappings.accept_diff, bufnr, function()
      apply_diff(state.diff:get_diff())
    end)
  end)

  if state.system_prompt then
    state.system_prompt:delete()
  end
  state.system_prompt = Overlay('copilot-system-prompt', overlay_help, function(bufnr)
    map_key(M.config.mappings.close, bufnr, function()
      state.system_prompt:restore(state.chat.winnr, state.chat.bufnr)
    end)
  end)

  if state.user_selection then
    state.user_selection:delete()
  end
  state.user_selection = Overlay('copilot-user-selection', overlay_help, function(bufnr)
    map_key(M.config.mappings.close, bufnr, function()
      state.user_selection:restore(state.chat.winnr, state.chat.bufnr)
    end)
  end)

  if state.help then
    state.help:delete()
  end
  state.help = Overlay('copilot-help', overlay_help, function(bufnr)
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
    function(bufnr)
      map_key(M.config.mappings.show_help, bufnr, function()
        local chat_help = '**`Special tokens`**\n'
        chat_help = chat_help .. '`@<agent>` to select an agent\n'
        chat_help = chat_help .. '`#<context>` to select a context\n'
        chat_help = chat_help .. '`/<prompt>` to select a prompt\n'
        chat_help = chat_help .. '`$<model>` to select a model\n'
        chat_help = chat_help .. '`> <text>` to make a sticky prompt (copied to next prompt)\n'

        chat_help = chat_help .. '\n**`Mappings`**\n'
        local chat_keys = vim.tbl_keys(M.config.mappings)
        table.sort(chat_keys, function(a, b)
          a = M.config.mappings[a]
          a = a.normal or a.insert
          b = M.config.mappings[b]
          b = b.normal or b.insert
          return a < b
        end)
        for _, name in ipairs(chat_keys) do
          if name ~= 'close' then
            local key = M.config.mappings[name]
            local info = key_to_info(name, key, '`')
            if info ~= '' then
              chat_help = chat_help .. info .. '\n'
            end
          end
        end
        state.help:show(chat_help, 'markdown', state.chat.winnr)
      end)

      map_key(M.config.mappings.reset, bufnr, M.reset)
      map_key(M.config.mappings.close, bufnr, M.close)
      map_key(M.config.mappings.complete, bufnr, trigger_complete)

      map_key(M.config.mappings.submit_prompt, bufnr, function()
        local chat_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local current_line = vim.api.nvim_win_get_cursor(0)[1]
        local lines =
          utils.find_lines(chat_lines, current_line, M.config.separator .. '$', nil, true)
        M.ask(vim.trim(table.concat(lines, '\n')), state.config)
      end)

      map_key(M.config.mappings.toggle_sticky, bufnr, function()
        local current_line = vim.trim(vim.api.nvim_get_current_line())
        if current_line == '' then
          return
        end

        local cursor = vim.api.nvim_win_get_cursor(0)
        local cur_line = cursor[1]
        vim.api.nvim_buf_set_lines(bufnr, cur_line - 1, cur_line, false, {})

        local chat_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local _, start_line, end_line =
          utils.find_lines(chat_lines, cur_line, M.config.separator .. '$', nil, true)

        if vim.startswith(current_line, '> ') then
          return
        end

        if start_line then
          local insert_line = start_line
          local first_one = true

          for i = insert_line, end_line do
            local line = chat_lines[i]
            if line and vim.trim(line) ~= '' then
              if vim.startswith(line, '> ') then
                first_one = false
              else
                break
              end
            elseif i >= start_line + 1 then
              break
            end

            insert_line = insert_line + 1
          end

          local lines = first_one and { '> ' .. current_line, '' } or { '> ' .. current_line }
          vim.api.nvim_buf_set_lines(bufnr, insert_line - 1, insert_line - 1, false, lines)
          vim.api.nvim_win_set_cursor(0, cursor)
        end
      end)

      map_key(M.config.mappings.accept_diff, bufnr, function()
        apply_diff(get_diff())
      end)

      map_key(M.config.mappings.jump_to_diff, bufnr, function()
        if
          not state.source
          or not state.source.winnr
          or not vim.api.nvim_win_is_valid(state.source.winnr)
        then
          return
        end

        local diff = get_diff()
        if not diff then
          return
        end

        local diff_bufnr = diff.bufnr

        -- Try to find existing buffer first
        if not diff_bufnr then
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if utils.filename_same(vim.api.nvim_buf_get_name(buf), diff.filename) then
              diff_bufnr = buf
              break
            end
          end
        end

        -- Create new empty buffer if doesn't exist
        if not diff_bufnr then
          diff_bufnr = vim.api.nvim_create_buf(true, false)
          vim.api.nvim_buf_set_name(diff_bufnr, diff.filename)
          vim.bo[diff_bufnr].filetype = diff.filetype
        end

        -- Open the buffer in the source window and move cursor
        vim.api.nvim_win_set_buf(state.source.winnr, diff_bufnr)
        vim.api.nvim_win_set_cursor(state.source.winnr, { diff.start_line, 0 })

        -- Set the marks for visual selection and update selection
        pcall(vim.api.nvim_buf_set_mark, diff_bufnr, '<', diff.start_line, 0, {})
        pcall(vim.api.nvim_buf_set_mark, diff_bufnr, '>', diff.end_line, 0, {})
        update_selection()
      end)

      map_key(M.config.mappings.quickfix_diffs, bufnr, function()
        local chat_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local selection = get_selection(state.config)
        local items = {}
        local in_block = false
        local block_start = 0
        local filetype = ''
        local in_answer = false
        local last_header = nil

        for i, line in ipairs(chat_lines) do
          -- Track if we're in an AI response section
          if line:match(M.config.answer_header .. M.config.separator .. '$') then
            in_answer = true
          elseif line:match(M.config.question_header .. M.config.separator .. '$') then
            in_answer = false
          end

          -- Only process code blocks in AI responses
          if in_answer then
            -- Try to capture markdown header with file info
            local filename, start_line, end_line = match_header(line)
            if filename then
              last_header = {
                filename = filename,
                start_line = start_line,
                end_line = end_line,
              }
            end

            if line:match('^```%w+$') then
              in_block = true
              block_start = i + 1
              filetype = line:match('^```(%w+)$')
            elseif line == '```' and in_block then
              in_block = false
              local item = {
                bufnr = bufnr,
                lnum = block_start,
                end_lnum = i - 1,
              }

              if last_header then
                item.text = string.format(
                  '%s [lines %d-%d]',
                  last_header.filename,
                  last_header.start_line,
                  last_header.end_line
                )
              elseif
                selection
                and selection.filename
                and selection.start_line
                and selection.end_line
              then
                item.text = string.format(
                  '%s [lines %d-%d]',
                  selection.filename,
                  selection.start_line,
                  selection.end_line
                )
              else
                item.text = string.format('Code block (%s)', filetype)
              end

              table.insert(items, item)
              last_header = nil
            end
          end
        end

        vim.fn.setqflist(items)
        vim.cmd('copen')
      end)

      map_key(M.config.mappings.yank_diff, bufnr, function()
        local diff = get_diff()
        if not diff then
          return
        end

        vim.fn.setreg(M.config.mappings.yank_diff.register, diff.change)
      end)

      map_key(M.config.mappings.show_diff, bufnr, function()
        local diff = get_diff()
        if not diff then
          return
        end

        state.diff:show(diff, state.chat.winnr)
      end)

      map_key(M.config.mappings.show_system_prompt, bufnr, function()
        local prompt = state.config.system_prompt
        if not prompt then
          return
        end

        state.system_prompt:show(vim.trim(prompt) .. '\n', 'markdown', state.chat.winnr)
      end)

      map_key(M.config.mappings.show_user_selection, bufnr, function()
        local selection = get_selection(state.config)
        if not selection or not selection.content then
          return
        end

        state.user_selection:show(selection.content .. '\n', selection.filetype, state.chat.winnr)
      end)

      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufLeave' }, {
        buffer = bufnr,
        callback = function(ev)
          local is_enter = ev.event == 'BufEnter'

          if is_enter then
            update_selection()
          else
            highlight_selection(true)
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

      if M.config.chat_autocomplete then
        vim.api.nvim_create_autocmd('TextChangedI', {
          buffer = bufnr,
          callback = function()
            local line = vim.api.nvim_get_current_line()
            local cursor = vim.api.nvim_win_get_cursor(0)
            local col = cursor[2]
            local char = line:sub(col, col)

            if vim.tbl_contains(M.complete_info().triggers, char) then
              utils.debounce(trigger_complete, 100)
            end
          end,
        })
      end

      finish(M.config, nil, nil, true)
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

  vim.api.nvim_create_user_command('CopilotChatModels', function()
    M.select_model()
  end, { force = true })
  vim.api.nvim_create_user_command('CopilotChatAgents', function()
    M.select_agent()
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
  vim.api.nvim_create_user_command('CopilotChatDebugInfo', function()
    debuginfo.open()
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
