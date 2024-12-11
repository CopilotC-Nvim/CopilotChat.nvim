local async = require('plenary.async')
local log = require('plenary.log')
local default_config = require('CopilotChat.config')
local Copilot = require('CopilotChat.copilot')
local context = require('CopilotChat.context')
local prompts = require('CopilotChat.prompts')
local utils = require('CopilotChat.utils')

local Chat = require('CopilotChat.ui.chat')
local Diff = require('CopilotChat.ui.diff')
local Overlay = require('CopilotChat.ui.overlay')
local Debug = require('CopilotChat.ui.debug')

local M = {}
local PLUGIN_NAME = 'CopilotChat'
local WORD = '([^%s]+)'

--- @class CopilotChat.source
--- @field bufnr number
--- @field winnr number

--- @class CopilotChat.state
--- @field copilot CopilotChat.Copilot?
--- @field source CopilotChat.source?
--- @field last_prompt string?
--- @field last_response string?
--- @field chat CopilotChat.ui.Chat?
--- @field diff CopilotChat.ui.Diff?
--- @field debug CopilotChat.ui.Debug?
--- @field overlay CopilotChat.ui.Overlay?
local state = {
  copilot = nil,

  -- Current state tracking
  source = nil,

  -- Last state tracking
  last_prompt = nil,
  last_response = nil,

  -- Overlays
  chat = nil,
  diff = nil,
  overlay = nil,
  debug = nil,
}

---@param config CopilotChat.config.shared
---@return CopilotChat.select.selection?
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
    return config.selection(state.source)
  end

  return nil
end

--- Highlights the selection in the source buffer.
---@param clear boolean
---@param config CopilotChat.config.shared
local function highlight_selection(clear, config)
  local selection_ns = vim.api.nvim_create_namespace('copilot-chat-selection')
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    vim.api.nvim_buf_clear_namespace(buf, selection_ns, 0, -1)
  end

  if clear or not config.highlight_selection then
    return
  end

  local selection = get_selection(config)
  if
    not selection
    or not utils.buf_valid(selection.bufnr)
    or not selection.start_line
    or not selection.end_line
  then
    return
  end

  vim.api.nvim_buf_set_extmark(selection.bufnr, selection_ns, selection.start_line - 1, 0, {
    hl_group = 'CopilotChatSelection',
    end_row = selection.end_line,
    strict = false,
  })
end

--- Updates the selection based on previous window
---@param config CopilotChat.config.shared
local function update_selection(config)
  local prev_winnr = vim.fn.win_getid(vim.fn.winnr('#'))
  if prev_winnr ~= state.chat.winnr and vim.fn.win_gettype(prev_winnr) == '' then
    state.source = {
      bufnr = vim.api.nvim_win_get_buf(prev_winnr),
      winnr = prev_winnr,
    }
  end

  highlight_selection(false, config)
end

---@param config CopilotChat.config.shared
---@return CopilotChat.ui.Diff.Diff?
local function get_diff(config)
  local block = state.chat:get_closest_block()

  -- If no block found, return nil
  if not block then
    return nil
  end

  -- Initialize variables with selection if available
  local header = block.header
  local selection = get_selection(config)
  local reference = selection and selection.content
  local start_line = selection and selection.start_line
  local end_line = selection and selection.end_line
  local filename = selection and selection.filename
  local filetype = selection and selection.filetype
  local bufnr = selection and selection.bufnr

  -- If we have header info, use it as source of truth
  if header.start_line and header.end_line then
    -- Try to find matching buffer and window
    bufnr = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local win_buf = vim.api.nvim_win_get_buf(win)
      if utils.filename_same(vim.api.nvim_buf_get_name(win_buf), header.filename) then
        bufnr = win_buf
        break
      end
    end

    filename = header.filename
    filetype = header.filetype or vim.filetype.match({ filename = filename })
    start_line = header.start_line
    end_line = header.end_line

    -- If we found a valid buffer, get the reference content
    if bufnr and utils.buf_valid(bufnr) then
      reference =
        table.concat(vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false), '\n')
      filetype = vim.bo[bufnr].filetype
    end
  end

  -- If we are missing info, there is no diff to be made
  if not start_line or not end_line or not filename then
    return nil
  end

  return {
    change = block.content,
    reference = reference or '',
    filetype = filetype or '',
    filename = filename,
    start_line = start_line,
    end_line = end_line,
    bufnr = bufnr,
  }
end

---@param winnr number
---@param bufnr number
---@param start_line number
---@param end_line number
---@param config CopilotChat.config.shared
local function jump_to_diff(winnr, bufnr, start_line, end_line, config)
  pcall(vim.api.nvim_win_set_cursor, winnr, { start_line, 0 })
  pcall(vim.api.nvim_buf_set_mark, bufnr, '<', start_line, 0, {})
  pcall(vim.api.nvim_buf_set_mark, bufnr, '>', end_line, 0, {})
  pcall(vim.api.nvim_buf_set_mark, bufnr, '[', start_line, 0, {})
  pcall(vim.api.nvim_buf_set_mark, bufnr, ']', end_line, 0, {})
  update_selection(config)
end

---@param diff CopilotChat.ui.Diff.Diff?
---@param config CopilotChat.config.shared
local function apply_diff(diff, config)
  if not diff or not diff.bufnr then
    return
  end

  local winnr = vim.fn.win_findbuf(diff.bufnr)[1]
  if not winnr then
    return
  end

  local lines = vim.split(diff.change, '\n', { trimempty = false })
  vim.api.nvim_buf_set_lines(diff.bufnr, diff.start_line - 1, diff.end_line, false, lines)
  jump_to_diff(winnr, diff.bufnr, diff.start_line, diff.start_line + #lines - 1, config)
end

---@param prompt string
---@param config CopilotChat.config.shared
---@return string, CopilotChat.config
local function resolve_prompts(prompt, config)
  local prompts_to_use = M.prompts()
  local depth = 0
  local MAX_DEPTH = 10

  local function resolve(inner_prompt, inner_config)
    if depth >= MAX_DEPTH then
      return inner_prompt, inner_config
    end
    depth = depth + 1

    inner_prompt = string.gsub(inner_prompt, '/' .. WORD, function(match)
      local p = prompts_to_use[match]
      if p then
        local resolved_prompt, resolved_config = resolve(p.prompt or '', p)
        inner_config = vim.tbl_deep_extend('force', inner_config, resolved_config)
        return resolved_prompt
      end

      return '/' .. match
    end)

    depth = depth - 1
    return inner_prompt, inner_config
  end

  return resolve(prompt, config)
end

---@param prompt string
---@param config CopilotChat.config.shared
---@return table<CopilotChat.context.embed>, string
local function resolve_embeddings(prompt, config)
  local contexts = {}
  local function parse_context(prompt_context)
    local split = vim.split(prompt_context, ':')
    local context_name = table.remove(split, 1)
    local context_input = vim.trim(table.concat(split, ':'))
    if M.config.contexts[context_name] then
      table.insert(contexts, {
        name = context_name,
        input = (context_input ~= '' and context_input or nil),
      })

      return true
    end

    return false
  end

  prompt = prompt:gsub('#' .. WORD, function(match)
    if parse_context(match) then
      return ''
    end
    return '#' .. match
  end)

  if config.context then
    if type(config.context) == 'table' then
      ---@diagnostic disable-next-line: param-type-mismatch
      for _, config_context in ipairs(config.context) do
        parse_context(config_context)
      end
    else
      parse_context(config.context)
    end
  end

  local embeddings = utils.ordered_map()
  for _, context_data in ipairs(contexts) do
    local context_value = M.config.contexts[context_data.name]
    for _, embedding in ipairs(context_value.resolve(context_data.input, state.source or {})) do
      if embedding then
        embeddings:set(embedding.filename, embedding)
      end
    end
  end

  return embeddings:values(), prompt
end

local function resolve_agent(prompt, config)
  local agents = vim.tbl_keys(state.copilot:list_agents())
  local selected_agent = config.agent
  prompt = prompt:gsub('@' .. WORD, function(match)
    if vim.tbl_contains(agents, match) then
      selected_agent = match
      return ''
    end
    return '@' .. match
  end)

  return selected_agent, prompt
end

local function resolve_model(prompt, config)
  local models = vim.tbl_keys(state.copilot:list_models())
  local selected_model = config.model
  prompt = prompt:gsub('%$' .. WORD, function(match)
    if vim.tbl_contains(models, match) then
      selected_model = match
      return ''
    end
    return '$' .. match
  end)

  return selected_model, prompt
end

---@param start_of_chat boolean?
local function finish(start_of_chat)
  if not start_of_chat then
    state.chat:append('\n\n')
  end

  state.chat:append(M.config.question_header .. M.config.separator .. '\n\n')

  -- Reinsert sticky prompts from last prompt
  if state.last_prompt then
    local has_sticky = false
    local lines = vim.split(state.last_prompt, '\n')
    for _, line in ipairs(lines) do
      if vim.startswith(line, '> ') then
        state.chat:append(line .. '\n')
        has_sticky = true
      end
    end
    if has_sticky then
      state.chat:append('\n')
    end
  end

  state.chat:finish()
end

---@param err string|table|nil
---@param append_newline boolean?
local function show_error(err, append_newline)
  err = err or 'Unknown error'

  if type(err) == 'string' then
    local message = err:match('^[^:]+:[^:]+:(.+)') or err
    message = message:gsub('^%s*', '')
    err = message
  else
    err = utils.make_string(err)
  end

  if append_newline then
    state.chat:append('\n')
  end

  state.chat:append(M.config.error_header .. '\n```error\n' .. err .. '\n```')
  finish()
end

--- Map a key to a function.
---@param name string
---@param bufnr number
---@param fn function
local function map_key(name, bufnr, fn)
  local key = M.config.mappings[name]
  if not key then
    return
  end
  if key.normal and key.normal ~= '' then
    vim.keymap.set(
      'n',
      key.normal,
      fn,
      { buffer = bufnr, nowait = true, desc = PLUGIN_NAME .. ' ' .. name:gsub('_', ' ') }
    )
  end
  if key.insert and key.insert ~= '' then
    vim.keymap.set('i', key.insert, function()
      -- If in insert mode and menu visible, use original key
      if vim.fn.pumvisible() == 1 then
        local used_key = key.insert == M.config.mappings.complete.insert and '<C-y>' or key.insert
        if used_key then
          vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes(used_key, true, false, true),
            'n',
            false
          )
        end
      else
        fn()
      end
    end, { buffer = bufnr, desc = PLUGIN_NAME .. ' ' .. name:gsub('_', ' ') })
  end
end

--- Get the info for a key.
---@param name string
---@param surround string|nil
---@return string
local function key_to_info(name, surround)
  local key = M.config.mappings[name]
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

        local value_str = tostring(value)
        vim.api.nvim_buf_set_text(bufnr, row - 1, col, row - 1, col, { value_str })
        vim.api.nvim_win_set_cursor(0, { row, col + #value_str })
      end, state.source or {})
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
      local kind = ''
      local info = ''
      if prompt.prompt then
        kind = 'user'
        info = prompt.prompt
      elseif prompt.system_prompt then
        kind = 'system'
        info = prompt.system_prompt
      end

      items[#items + 1] = {
        word = '/' .. name,
        kind = kind,
        info = info,
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
      if a.kind == b.kind then
        return a.word < b.word
      end
      return a.kind < b.kind
    end)

    async.util.scheduler()
    callback(items)
  end)
end

--- Get the prompts to use.
---@return table<string, CopilotChat.config.prompt>
function M.prompts()
  local prompts_to_use = {}

  for name, prompt in pairs(prompts) do
    prompts_to_use[name] = {
      system_prompt = prompt,
    }
  end

  for name, prompt in pairs(M.config.prompts) do
    local val = prompt
    if type(prompt) == 'string' then
      val = {
        prompt = prompt,
      }
    end

    prompts_to_use[name] = val
  end

  return prompts_to_use
end

--- Open the chat window.
---@param config CopilotChat.config.shared?
function M.open(config)
  -- If we are already in chat window, do nothing
  if state.chat:active() then
    return
  end

  config = vim.tbl_deep_extend('force', M.config, config or {})
  if config.headless then
    return
  end

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
---@param config CopilotChat.config.shared?
function M.toggle(config)
  if state.chat:visible() then
    M.close()
  else
    M.open(config)
  end
end

--- Get the last response.
--- @returns string
function M.response()
  return state.last_response
end

--- Select default Copilot GPT model.
function M.select_model()
  async.run(function()
    local models = vim.tbl_keys(state.copilot:list_models())
    models = vim.tbl_map(function(model)
      if model == M.config.model then
        return model .. ' (selected)'
      end

      return model
    end, models)

    async.util.scheduler()
    vim.ui.select(models, {
      prompt = 'Select a model> ',
    }, function(choice)
      if choice then
        M.config.model = choice:gsub(' %(selected%)', '')
      end
    end)
  end)
end

--- Select default Copilot agent.
function M.select_agent()
  async.run(function()
    local agents = vim.tbl_keys(state.copilot:list_agents())
    agents = vim.tbl_map(function(agent)
      if agent == M.config.agent then
        return agent .. ' (selected)'
      end

      return agent
    end, agents)

    async.util.scheduler()
    vim.ui.select(agents, {
      prompt = 'Select an agent> ',
    }, function(choice)
      if choice then
        M.config.agent = choice:gsub(' %(selected%)', '')
      end
    end)
  end)
end

--- Ask a question to the Copilot model.
---@param prompt string?
---@param config CopilotChat.config.shared?
function M.ask(prompt, config)
  M.open(config)

  prompt = vim.trim(prompt or '')
  if prompt == '' then
    return
  end

  vim.diagnostic.reset(vim.api.nvim_create_namespace('copilot_diagnostics'))
  config = vim.tbl_deep_extend('force', state.chat.config, config or {})
  config = vim.tbl_deep_extend('force', M.config, config or {})

  if not config.headless then
    if config.clear_chat_on_new_prompt then
      M.stop(true)
    elseif state.copilot:stop() then
      finish()
    end

    state.last_prompt = prompt
    state.chat:clear_prompt()
    state.chat:append('\n\n' .. prompt)
    state.chat:append('\n\n' .. config.answer_header .. config.separator .. '\n\n')
  end

  -- Resolve prompt references
  local prompt, config = resolve_prompts(prompt, config)
  local system_prompt = config.system_prompt

  -- Remove sticky prefix
  prompt = vim.trim(table.concat(
    vim.tbl_map(function(l)
      return l:gsub('^>%s+', '')
    end, vim.split(prompt, '\n')),
    '\n'
  ))

  -- Retrieve the selection
  local selection = get_selection(config)

  local ok, err = pcall(async.run, function()
    local embeddings, prompt = resolve_embeddings(prompt, config)
    local selected_agent, prompt = resolve_agent(prompt, config)
    local selected_model, prompt = resolve_model(prompt, config)

    local has_output = false
    local query_ok, filtered_embeddings =
      pcall(context.filter_embeddings, state.copilot, prompt, embeddings)

    if not query_ok then
      async.util.scheduler()
      log.error(filtered_embeddings)
      if not config.headless then
        show_error(filtered_embeddings, has_output)
      end
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
        no_history = config.headless,
        on_progress = vim.schedule_wrap(function(token)
          if not config.headless then
            state.chat:append(token)
          end
          has_output = true
        end),
      })

    async.util.scheduler()

    if not ask_ok then
      log.error(response)
      if not config.headless then
        show_error(response, has_output)
      end
      return
    end

    if not response then
      return
    end

    if not config.headless then
      state.last_response = response
      state.chat.token_count = token_count
      state.chat.token_max_count = token_max_count
    end

    if not config.headless then
      finish()
    end
    if config.callback then
      config.callback(response, state.source)
    end
  end)

  if not ok then
    log.error(err)
    if not config.headless then
      show_error(err)
    end
  end
end

--- Stop current copilot output and optionally reset the chat ten show the help message.
---@param reset boolean?
function M.stop(reset)
  if reset then
    state.copilot:reset()
    state.chat:clear()
    state.last_prompt = nil
    state.last_response = nil
  else
    state.copilot:stop()
  end

  finish(reset)
end

--- Reset the chat window and show the help message.
function M.reset()
  M.stop(true)
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

  finish(#history == 0)
end

--- Set the log level
---@param level string
function M.log_level(level)
  M.config.log_level = level
  M.config.debug = level == 'debug'
  local logfile = string.format('%s/%s.log', vim.fn.stdpath('state'), PLUGIN_NAME)
  log.new({
    plugin = PLUGIN_NAME,
    level = level,
    outfile = logfile,
  }, true)
  log.logfile = logfile
end

--- Set up the plugin
---@param config CopilotChat.config?
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

        if name == 'show_system_prompt' then
          utils.deprecate('config.mappings.' .. name, 'config.mappings.show_info')
        end

        if name == 'show_user_context' or name == 'show_user_selection' then
          utils.deprecate('config.mappings.' .. name, 'config.mappings.show_context')
        end
      end
    end

    if config['yank_diff_register'] then
      utils.deprecate('config.yank_diff_register', 'config.mappings.yank_diff.register')
      config.mappings.yank_diff.register = config['yank_diff_register']
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

  vim.api.nvim_set_hl(0, 'CopilotChatSpinner', { link = 'DiagnosticInfo', default = true })
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

  local overlay_help = key_to_info('close')
  local diff_help = key_to_info('accept_diff')
  if overlay_help ~= '' and diff_help ~= '' then
    diff_help = diff_help .. '\n' .. overlay_help
  end

  if state.overlay then
    state.overlay:delete()
  end
  state.overlay = Overlay('copilot-overlay', overlay_help, function(bufnr)
    map_key('close', bufnr, function()
      state.overlay:restore(state.chat.winnr, state.chat.bufnr)
    end)
  end)

  if not state.debug then
    state.debug = Debug()
  end

  if state.diff then
    state.diff:delete()
  end
  state.diff = Diff(diff_help, function(bufnr)
    map_key('close', bufnr, function()
      state.diff:restore(state.chat.winnr, state.chat.bufnr)
    end)

    map_key('accept_diff', bufnr, function()
      apply_diff(state.diff:get_diff(), state.chat.config)
    end)
  end)

  if state.chat then
    state.chat:close(state.source and state.source.bufnr or nil)
    state.chat:delete()
  end
  state.chat = Chat(
    M.config.question_header,
    M.config.answer_header,
    M.config.separator,
    key_to_info('show_help'),
    function(bufnr)
      map_key('show_help', bufnr, function()
        local chat_help = '**`Special tokens`**\n'
        chat_help = chat_help .. '`@<agent>` to select an agent\n'
        chat_help = chat_help .. '`#<context>` to select a context\n'
        chat_help = chat_help .. '`#<context>:<input>` to select input for context\n'
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
            local info = key_to_info(name, '`')
            if info ~= '' then
              chat_help = chat_help .. info .. '\n'
            end
          end
        end
        state.overlay:show(chat_help, state.chat.winnr, 'markdown')
      end)

      map_key('reset', bufnr, M.reset)
      map_key('close', bufnr, M.close)
      map_key('complete', bufnr, trigger_complete)

      map_key('submit_prompt', bufnr, function()
        local section = state.chat:get_closest_section()
        if not section or section.answer then
          return
        end

        M.ask(section.content)
      end)

      map_key('toggle_sticky', bufnr, function()
        local section = state.chat:get_closest_section()
        if not section or section.answer then
          return
        end

        local current_line = vim.trim(vim.api.nvim_get_current_line())
        if current_line == '' then
          return
        end

        local cursor = vim.api.nvim_win_get_cursor(0)
        local cur_line = cursor[1]
        vim.api.nvim_buf_set_lines(bufnr, cur_line - 1, cur_line, false, {})

        if vim.startswith(current_line, '> ') then
          return
        end

        local lines = vim.split(section.content, '\n')
        local insert_line = 1
        local first_one = true

        for i = insert_line, #lines do
          local line = lines[i]
          if line and vim.trim(line) ~= '' then
            if vim.startswith(line, '> ') then
              first_one = false
            else
              break
            end
          elseif i >= 2 then
            break
          end

          insert_line = insert_line + 1
        end

        insert_line = section.start_line + insert_line - 1
        local to_insert = first_one and { '> ' .. current_line, '' } or { '> ' .. current_line }
        vim.api.nvim_buf_set_lines(bufnr, insert_line - 1, insert_line - 1, false, to_insert)
        vim.api.nvim_win_set_cursor(0, cursor)
      end)

      map_key('accept_diff', bufnr, function()
        apply_diff(get_diff(state.chat.config), state.chat.config)
      end)

      map_key('jump_to_diff', bufnr, function()
        if
          not state.source
          or not state.source.winnr
          or not vim.api.nvim_win_is_valid(state.source.winnr)
        then
          return
        end

        local diff = get_diff(state.chat.config)
        if not diff then
          return
        end

        local diff_bufnr = diff.bufnr

        -- If buffer is not found, try to load it
        if not diff_bufnr then
          diff_bufnr = vim.fn.bufadd(diff.filename)
          vim.fn.bufload(diff_bufnr)
        end

        state.source.bufnr = diff_bufnr
        vim.api.nvim_win_set_buf(state.source.winnr, diff_bufnr)

        jump_to_diff(
          state.source.winnr,
          diff_bufnr,
          diff.start_line,
          diff.end_line,
          state.chat.config
        )
      end)

      map_key('quickfix_diffs', bufnr, function()
        local selection = get_selection(state.chat.config)
        local items = {}

        for _, section in ipairs(state.chat.sections) do
          for _, block in ipairs(section.blocks) do
            local header = block.header

            if not header.start_line and selection then
              header.filename = selection.filename .. ' (selection)'
              header.start_line = selection.start_line
              header.end_line = selection.end_line
            end

            local text = string.format('%s (%s)', header.filename, header.filetype)
            if header.start_line and header.end_line then
              text = text .. string.format(' [lines %d-%d]', header.start_line, header.end_line)
            end

            table.insert(items, {
              bufnr = bufnr,
              lnum = block.start_line,
              end_lnum = block.end_line,
              text = text,
            })
          end
        end

        vim.fn.setqflist(items)
        vim.cmd('copen')
      end)

      map_key('yank_diff', bufnr, function()
        local diff = get_diff(state.chat.config)
        if not diff then
          return
        end

        vim.fn.setreg(M.config.mappings.yank_diff.register, diff.change)
      end)

      map_key('show_diff', bufnr, function()
        local diff = get_diff(state.chat.config)
        if not diff then
          return
        end

        state.diff:show(diff, state.chat.winnr)
      end)

      map_key('show_info', bufnr, function()
        local section = state.chat:get_closest_section()
        if not section or section.answer then
          return
        end

        local lines = {}
        local prompt, config = resolve_prompts(section.content, state.chat.config)
        local system_prompt = config.system_prompt

        async.run(function()
          local selected_agent = resolve_agent(prompt, config)
          local selected_model = resolve_model(prompt, config)

          if selected_model then
            table.insert(lines, '**Model**')
            table.insert(lines, '```')
            table.insert(lines, selected_model)
            table.insert(lines, '```')
            table.insert(lines, '')
          end

          if selected_agent then
            table.insert(lines, '**Agent**')
            table.insert(lines, '```')
            table.insert(lines, selected_agent)
            table.insert(lines, '```')
            table.insert(lines, '')
          end

          if system_prompt then
            table.insert(lines, '**System Prompt**')
            table.insert(lines, '```')
            for _, line in ipairs(vim.split(vim.trim(system_prompt), '\n')) do
              table.insert(lines, line)
            end
            table.insert(lines, '```')
            table.insert(lines, '')
          end

          async.util.scheduler()
          state.overlay:show(
            vim.trim(table.concat(lines, '\n')) .. '\n',
            state.chat.winnr,
            'markdown'
          )
        end)
      end)

      map_key('show_context', bufnr, function()
        local section = state.chat:get_closest_section()
        if not section or section.answer then
          return
        end

        local lines = {}

        local selection = get_selection(state.chat.config)
        if selection then
          table.insert(lines, '**Selection**')
          table.insert(lines, '```' .. selection.filetype)
          for _, line in ipairs(vim.split(selection.content, '\n')) do
            table.insert(lines, line)
          end
          table.insert(lines, '```')
          table.insert(lines, '')
        end

        async.run(function()
          local embeddings = {}
          if section and not section.answer then
            embeddings = resolve_embeddings(section.content, state.chat.config)
          end

          for _, embedding in ipairs(embeddings) do
            local embed_lines = vim.split(embedding.content, '\n')
            local preview = vim.list_slice(embed_lines, 1, math.min(10, #embed_lines))
            local header = string.format('**%s** (%s lines)', embedding.filename, #embed_lines)
            if #embed_lines > 10 then
              header = header .. ' (truncated)'
            end

            table.insert(lines, header)
            table.insert(lines, '```' .. embedding.filetype)
            for _, line in ipairs(preview) do
              table.insert(lines, line)
            end
            table.insert(lines, '```')
            table.insert(lines, '')
          end

          async.util.scheduler()
          state.overlay:show(
            vim.trim(table.concat(lines, '\n')) .. '\n',
            state.chat.winnr,
            'markdown'
          )
        end)
      end)

      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufLeave' }, {
        buffer = bufnr,
        callback = function(ev)
          local is_enter = ev.event == 'BufEnter'

          if is_enter then
            update_selection(state.chat.config)
          else
            highlight_selection(true, state.chat.config)
          end
        end,
      })

      if M.config.insert_at_end then
        vim.api.nvim_create_autocmd({ 'InsertEnter' }, {
          buffer = bufnr,
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
              utils.debounce('complete', trigger_complete, 100)
            end
          end,
        })

        -- Add popup and noinsert completeopt if not present
        if vim.fn.has('nvim-0.11.0') == 1 then
          local completeopt = vim.opt.completeopt:get()
          local updated = false
          if not vim.tbl_contains(completeopt, 'noinsert') then
            updated = true
            table.insert(completeopt, 'noinsert')
          end
          if not vim.tbl_contains(completeopt, 'popup') then
            updated = true
            table.insert(completeopt, 'popup')
          end
          if updated then
            vim.bo[bufnr].completeopt = table.concat(completeopt, ',')
          end
        end
      end

      finish(true)
    end
  )

  for name, prompt in pairs(M.prompts()) do
    if prompt.prompt then
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
        desc = prompt.description or (PLUGIN_NAME .. ' ' .. name),
      })

      if prompt.mapping then
        vim.keymap.set({ 'n', 'v' }, prompt.mapping, function()
          M.ask(prompt.prompt, prompt)
        end, { desc = prompt.description or (PLUGIN_NAME .. ' ' .. name) })
      end
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
    state.debug:open()
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

  -- Store the current directory to window when directory changes
  -- I dont think there is a better way to do this that functions
  -- with "rooter" plugins, LSP and stuff as vim.fn.getcwd() when
  -- i pass window number inside doesnt work
  vim.api.nvim_create_autocmd({ 'VimEnter', 'WinEnter', 'DirChanged' }, {
    group = vim.api.nvim_create_augroup('CopilotChat', {}),
    callback = function()
      vim.w.cchat_cwd = vim.fn.getcwd()
    end,
  })
end

return M
