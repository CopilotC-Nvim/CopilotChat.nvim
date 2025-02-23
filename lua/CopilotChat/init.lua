local async = require('plenary.async')
local log = require('plenary.log')
local context = require('CopilotChat.context')
local client = require('CopilotChat.client')
local utils = require('CopilotChat.utils')

local M = {}
local PLUGIN_NAME = 'CopilotChat'
local WORD = '([^%s]+)'

--- @class CopilotChat.source
--- @field bufnr number
--- @field winnr number

--- @class CopilotChat.state
--- @field source CopilotChat.source?
--- @field last_prompt string?
--- @field last_response string?
--- @field highlights_loaded boolean
--- @field chat CopilotChat.ui.Chat?
--- @field diff CopilotChat.ui.Diff?
--- @field overlay CopilotChat.ui.Overlay?
local state = {
  -- Current state tracking
  source = nil,

  -- Last state tracking
  last_prompt = nil,
  last_response = nil,
  highlights_loaded = false,

  -- Overlays
  chat = nil,
  diff = nil,
  overlay = nil,
}

--- Update the highlights in chat buffer
local function update_highlights()
  if state.highlights_loaded then
    return
  end

  M.complete_items(function(items)
    for _, item in ipairs(items) do
      local pattern = vim.fn.escape(item.word, '.-$^*[]')
      if vim.startswith(item.word, '#') then
        vim.cmd('syntax match CopilotChatKeyword "' .. pattern .. '\\(:.\\+\\)\\?" containedin=ALL')
      else
        vim.cmd('syntax match CopilotChatKeyword "' .. pattern .. '" containedin=ALL')
      end
    end

    vim.cmd('syntax match CopilotChatInput ":\\(.\\+\\)" contained containedin=CopilotChatKeyword')
    state.highlights_loaded = true
  end)
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

  local selection = M.get_selection(config)
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

---@param start_of_chat boolean?
local function finish(start_of_chat)
  if not start_of_chat then
    state.chat:append('\n\n')
  end

  state.chat:append(M.config.question_header .. M.config.separator .. '\n\n')

  -- Add default sticky prompts after reset
  if start_of_chat then
    if M.config.sticky then
      local last_prompt = state.last_prompt or ''

      if type(M.config.sticky) == 'table' then
        ---@diagnostic disable-next-line: param-type-mismatch
        for _, sticky in ipairs(M.config.sticky) do
          last_prompt = last_prompt .. '\n> ' .. sticky
        end
      else
        last_prompt = last_prompt .. '\n> ' .. M.config.sticky
      end

      state.last_prompt = last_prompt
    end
  end

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
    while true do
      local new_err = err:gsub('^[^:]+:%d+: ', '')
      if new_err == err then
        break
      end
      err = new_err
    end
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
---@param fn function?
local function map_key(name, bufnr, fn)
  local key = M.config.mappings[name]
  if not key then
    return
  end

  if not fn then
    fn = function()
      key.callback(state.overlay, state.diff, state.chat, state.source)
    end
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

--- Updates the selection based on previous window
---@param config CopilotChat.config.shared
function M.update_selection(config)
  local prev_winnr = vim.fn.win_getid(vim.fn.winnr('#'))
  if prev_winnr ~= state.chat.winnr and vim.fn.win_gettype(prev_winnr) == '' then
    state.source = {
      bufnr = vim.api.nvim_win_get_buf(prev_winnr),
      winnr = prev_winnr,
    }
  end

  highlight_selection(false, config)
end

--- Resolve the prompts from the prompt.
---@param prompt string
---@param config CopilotChat.config.shared
---@return string, CopilotChat.config
function M.resolve_prompts(prompt, config)
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

--- Resolve the embeddings from the prompt.
---@param prompt string
---@param config CopilotChat.config.shared
---@return table<CopilotChat.context.embed>, string
function M.resolve_embeddings(prompt, config)
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
    for _, embedding in
      ipairs(context_value.resolve(context_data.input, state.source or {}, prompt))
    do
      if embedding then
        embeddings:set(embedding.filename, embedding)
      end
    end
  end

  return embeddings:values(), prompt
end

--- Resolve the agent from the prompt.
---@param prompt string
---@param config CopilotChat.config.shared
function M.resolve_agent(prompt, config)
  local agents = vim.tbl_map(function(agent)
    return agent.id
  end, client:list_agents())

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

--- Resolve the model from the prompt.
---@param prompt string
---@param config CopilotChat.config.shared
function M.resolve_model(prompt, config)
  local models = vim.tbl_map(function(model)
    return model.id
  end, client:list_models())

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

--- Get the selection from the source buffer.
---@param config CopilotChat.config.shared
---@return CopilotChat.select.selection?
function M.get_selection(config)
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

--- Trigger the completion for the chat window.
---@param with_context boolean?
function M.trigger_complete(with_context)
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

  if with_context and vim.startswith(prefix, '#') and vim.endswith(prefix, ':') then
    local found_context = M.config.contexts[prefix:sub(2, -2)]
    if found_context and found_context.input then
      async.run(function()
        found_context.input(function(value)
          if not value then
            return
          end

          local value_str = tostring(value)
          vim.api.nvim_buf_set_text(bufnr, row - 1, col, row - 1, col, { value_str })
          vim.api.nvim_win_set_cursor(0, { row, col + #value_str })
        end, state.source or {})
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
    local models = client:list_models()
    local agents = client:list_agents()
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
        abbr = name,
        kind = kind,
        info = info,
        menu = prompt.description or '',
        icase = 1,
        dup = 0,
        empty = 0,
      }
    end

    for _, model in ipairs(models) do
      items[#items + 1] = {
        word = '$' .. model.id,
        abbr = model.id,
        kind = model.provider,
        menu = model.name,
        icase = 1,
        dup = 0,
        empty = 0,
      }
    end

    for _, agent in pairs(agents) do
      items[#items + 1] = {
        word = '@' .. agent.id,
        abbr = agent.id,
        kind = agent.provider,
        info = agent.description,
        menu = agent.name,
        icase = 1,
        dup = 0,
        empty = 0,
      }
    end

    for name, value in pairs(M.config.contexts) do
      items[#items + 1] = {
        word = '#' .. name,
        abbr = name,
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
    state.source = {
      bufnr = vim.api.nvim_get_current_buf(),
      winnr = vim.api.nvim_get_current_win(),
    }
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
    local models = client:list_models()
    local choices = vim.tbl_map(function(model)
      return {
        id = model.id,
        name = model.name,
        provider = model.provider,
        selected = model.id == M.config.model,
      }
    end, models)

    async.util.scheduler()
    vim.ui.select(choices, {
      prompt = 'Select a model> ',
      format_item = function(item)
        local out = string.format('%s (%s)', item.id, item.provider)
        if item.selected then
          out = '* ' .. out
        end
        return out
      end,
    }, function(choice)
      if choice then
        M.config.model = choice.id
      end
    end)
  end)
end

--- Select default Copilot agent.
function M.select_agent()
  async.run(function()
    local agents = client:list_agents()
    local choices = vim.tbl_map(function(agent)
      return {
        id = agent.id,
        name = agent.name,
        provider = agent.provider,
        selected = agent.id == M.config.agent,
      }
    end, agents)

    async.util.scheduler()
    vim.ui.select(choices, {
      prompt = 'Select an agent> ',
      format_item = function(item)
        local out = string.format('%s (%s)', item.id, item.provider)
        if item.selected then
          out = '* ' .. out
        end
        return out
      end,
    }, function(choice)
      if choice then
        M.config.agent = choice.id
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

  vim.diagnostic.reset(vim.api.nvim_create_namespace('copilot-chat-diagnostics'))
  config = vim.tbl_deep_extend('force', state.chat.config, config or {})
  config = vim.tbl_deep_extend('force', M.config, config or {})

  if not config.headless then
    if config.clear_chat_on_new_prompt then
      M.stop(true)
    elseif client:stop() then
      finish()
    end

    state.last_prompt = prompt
    state.chat:clear_prompt()
    state.chat:append('\n\n' .. prompt)
    state.chat:append('\n\n' .. config.answer_header .. config.separator .. '\n\n')
  end

  -- Resolve prompt references
  local prompt, config = M.resolve_prompts(prompt, config)
  local system_prompt = config.system_prompt or ''

  -- Remove sticky prefix
  prompt = vim.trim(table.concat(
    vim.tbl_map(function(l)
      return l:gsub('^>%s+', '')
    end, vim.split(prompt, '\n')),
    '\n'
  ))

  -- Retrieve the selection
  local selection = M.get_selection(config)

  local ok, err = pcall(async.run, function()
    local selected_agent, prompt = M.resolve_agent(prompt, config)
    local selected_model, prompt = M.resolve_model(prompt, config)
    local embeddings, prompt = M.resolve_embeddings(prompt, config)

    local has_output = false
    local query_ok, filtered_embeddings =
      pcall(context.filter_embeddings, prompt, selected_model, config.headless, embeddings)

    if not query_ok then
      async.util.scheduler()
      log.error(filtered_embeddings)
      if not config.headless then
        show_error(filtered_embeddings, has_output)
      end
      return
    end

    local ask_ok, response, references, token_count, token_max_count =
      pcall(client.ask, client, prompt, {
        headless = config.headless,
        selection = selection,
        embeddings = filtered_embeddings,
        system_prompt = system_prompt,
        model = selected_model,
        agent = selected_agent,
        temperature = config.temperature,
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
      state.chat.references = references
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
    client:reset()
    state.chat:clear()
    state.last_prompt = nil
    state.last_response = nil

    -- Clear the selection
    if state.source and utils.buf_valid(state.source.bufnr) then
      for _, mark in ipairs({ '<', '>', '[', ']' }) do
        pcall(vim.api.nvim_buf_del_mark, state.source.bufnr, mark)
      end
      highlight_selection(true, state.chat.config)
    end
  else
    client:stop()
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
  if not history_path then
    return
  end

  local history = vim.json.encode(client.history)
  history_path = vim.fn.expand(history_path)
  vim.fn.mkdir(history_path, 'p')
  history_path = history_path .. '/' .. name .. '.json'
  local file = io.open(history_path, 'w')
  if not file then
    log.error('Failed to save history to ' .. history_path)
    return
  end
  file:write(history)
  file:close()

  log.info('Saved history to ' .. history_path)
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

  history_path = vim.fn.expand(history_path) .. '/' .. name .. '.json'
  local file = io.open(history_path, 'r')
  if not file then
    return
  end
  local history = file:read('*a')
  file:close()
  history = vim.json.decode(history, {
    luanil = {
      array = true,
      object = true,
    },
  })

  client:reset()
  state.chat:clear()
  state.chat:load_history(history)
  log.info('Loaded history from ' .. history_path)

  if #history > 0 then
    local last = history[#history]
    if last and last.role == 'user' then
      state.chat:append('\n\n')
      state.chat:finish()
      return
    end
  end

  finish(#history == 0)
end

--- Set the log level
---@param level string
function M.log_level(level)
  M.config.log_level = level
  M.config.debug = level == 'debug'

  log.new({
    plugin = PLUGIN_NAME,
    level = level,
    outfile = M.config.log_path,
  }, true)
end

--- Set up the plugin
---@param config CopilotChat.config?
function M.setup(config)
  M.config = vim.tbl_deep_extend('force', require('CopilotChat.config'), config or {})

  -- Save proxy and insecure settings
  utils.curl_store_args({
    insecure = M.config.allow_insecure,
    proxy = M.config.proxy,
  })

  -- Load the providers
  client:stop()
  client:load_providers(M.config.providers)

  if M.config.debug then
    M.log_level('debug')
  else
    M.log_level(M.config.log_level)
  end

  vim.api.nvim_set_hl(0, 'CopilotChatStatus', { link = 'DiagnosticHint', default = true })
  vim.api.nvim_set_hl(0, 'CopilotChatHelp', { link = 'DiagnosticInfo', default = true })
  vim.api.nvim_set_hl(0, 'CopilotChatKeyword', { link = 'Keyword', default = true })
  vim.api.nvim_set_hl(0, 'CopilotChatInput', { link = 'Special', default = true })
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

  state.highlights_loaded = false

  local overlay_help = utils.key_to_info('close', M.config.mappings.close)
  if state.overlay then
    state.overlay:delete()
  end
  state.overlay = require('CopilotChat.ui.overlay')('copilot-overlay', overlay_help, function(bufnr)
    map_key('close', bufnr, function()
      state.overlay:restore(state.chat.winnr, state.chat.bufnr)
    end)
  end)

  if state.diff then
    state.diff:delete()
  end
  state.diff = require('CopilotChat.ui.diff')(overlay_help, function(bufnr)
    map_key('close', bufnr, function()
      state.diff:restore(state.chat.winnr, state.chat.bufnr)
    end)
  end)

  if state.chat then
    state.chat:close(state.source and state.source.bufnr or nil)
    state.chat:delete()
  end
  state.chat = require('CopilotChat.ui.chat')(
    M.config.question_header,
    M.config.answer_header,
    M.config.separator,
    utils.key_to_info('show_help', M.config.mappings.show_help),
    function(bufnr)
      for name, _ in pairs(M.config.mappings) do
        map_key(name, bufnr)
      end

      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufLeave' }, {
        buffer = bufnr,
        callback = function(ev)
          local is_enter = ev.event == 'BufEnter'

          if is_enter then
            update_highlights()
            M.update_selection(state.chat.config)
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
              utils.debounce('complete', M.trigger_complete, 100)
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
