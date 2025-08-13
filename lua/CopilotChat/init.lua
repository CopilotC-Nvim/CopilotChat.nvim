local async = require('plenary.async')
local log = require('plenary.log')
local functions = require('CopilotChat.functions')
local client = require('CopilotChat.client')
local constants = require('CopilotChat.constants')
local notify = require('CopilotChat.notify')
local utils = require('CopilotChat.utils')

local WORD = '([^%s:]+)'
local WORD_NO_INPUT = '([^%s]+)'
local WORD_WITH_INPUT_QUOTED = WORD .. ':`([^`]+)`'
local WORD_WITH_INPUT_UNQUOTED = WORD .. ':?([^%s`]*)'
local BLOCK_OUTPUT_FORMAT = '```%s\n%s\n```'

---@class CopilotChat
---@field config CopilotChat.config.Config
---@field chat CopilotChat.ui.chat.Chat
local M = setmetatable({}, {
  __index = function(t, key)
    if key == 'config' then
      return require('CopilotChat.config')
    end
    return rawget(t, key)
  end,
})

--- @class CopilotChat.source
--- @field bufnr number
--- @field winnr number
--- @field cwd fun():string

--- @class CopilotChat.state
--- @field source CopilotChat.source?
--- @field sticky string[]?
local state = {
  -- Current state tracking
  source = nil,

  -- Last state tracking
  sticky = nil,
}

--- Insert sticky values from config into prompt
---@param prompt string
---@param config CopilotChat.config.Shared
local function insert_sticky(prompt, config)
  local existing_prompt = M.chat:get_message(constants.ROLE.USER)
  local combined_prompt = (existing_prompt and existing_prompt.content or '') .. '\n' .. (prompt or '')
  local lines = vim.split(prompt or '', '\n')
  local stickies = utils.ordered_map()

  local sticky_indices = {}
  local in_code_block = false
  for _, line in ipairs(vim.split(combined_prompt, '\n')) do
    if line:match('^```') then
      in_code_block = not in_code_block
    end
    if vim.startswith(line, '> ') and not in_code_block then
      stickies:set(vim.trim(line:sub(3)), true)
    end
  end
  for i, line in ipairs(lines) do
    if vim.startswith(line, '> ') then
      table.insert(sticky_indices, i)
    end
  end
  for i = #sticky_indices, 1, -1 do
    table.remove(lines, sticky_indices[i])
  end

  lines = vim.split(vim.trim(table.concat(lines, '\n')), '\n')

  if config.remember_as_sticky and config.model and config.model ~= M.config.model then
    stickies:set('$' .. config.model, true)
  end

  if config.remember_as_sticky and config.tools and not vim.deep_equal(config.tools, M.config.tools) then
    for _, tool in ipairs(utils.to_table(config.tools)) do
      stickies:set('@' .. tool, true)
    end
  end

  if
    config.remember_as_sticky
    and config.system_prompt
    and config.system_prompt ~= M.config.system_prompt
    and M.config.prompts[config.system_prompt]
  then
    stickies:set('/' .. config.system_prompt, true)
  end

  if config.sticky and not vim.deep_equal(config.sticky, M.config.sticky) then
    for _, sticky in ipairs(utils.to_table(config.sticky)) do
      stickies:set(sticky, true)
    end
  end

  -- Insert stickies at start of prompt
  local prompt_lines = {}
  for _, sticky in ipairs(stickies:keys()) do
    if sticky ~= '' then
      table.insert(prompt_lines, '> ' .. sticky)
    end
  end
  if #prompt_lines > 0 then
    table.insert(prompt_lines, '')
  end
  for _, line in ipairs(lines) do
    table.insert(prompt_lines, line)
  end
  if #lines == 0 then
    table.insert(prompt_lines, '')
  end

  return table.concat(prompt_lines, '\n')
end

local function store_sticky(prompt)
  local sticky = {}
  local in_code_block = false
  for _, line in ipairs(vim.split(prompt, '\n')) do
    if line:match('^```') then
      in_code_block = not in_code_block
    end
    if vim.startswith(line, '> ') and not in_code_block then
      table.insert(sticky, line:sub(3))
    end
  end
  state.sticky = sticky
end

--- Update the highlights for chat buffer
local function update_highlights()
  local selection_ns = vim.api.nvim_create_namespace('copilot-chat-selection')
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    vim.api.nvim_buf_clear_namespace(buf, selection_ns, 0, -1)
  end

  if M.chat.config.highlight_selection and M.chat:focused() then
    local selection = M.get_selection()
    if not selection or not utils.buf_valid(selection.bufnr) or not selection.start_line or not selection.end_line then
      return
    end

    vim.api.nvim_buf_set_extmark(selection.bufnr, selection_ns, selection.start_line - 1, 0, {
      hl_group = 'CopilotChatSelection',
      end_row = selection.end_line,
      strict = false,
    })
  end
end

--- List available models.
--- @return CopilotChat.client.Model[]
local function list_models()
  local models = client:models()
  local result = vim.tbl_keys(models)

  table.sort(result, function(a, b)
    a = models[a]
    b = models[b]
    if a.provider ~= b.provider then
      return a.provider < b.provider
    end
    return a.id < b.id
  end)

  return vim.tbl_map(function(id)
    return models[id]
  end, result)
end

--- List available prompts.
---@return table<string, CopilotChat.config.prompts.Prompt>
local function list_prompts()
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

--- Finish writing to chat buffer.
---@param start_of_chat boolean?
local function finish(start_of_chat)
  if start_of_chat then
    local sticky = {}
    if M.config.sticky then
      for _, sticky_line in ipairs(utils.to_table(M.config.sticky)) do
        table.insert(sticky, sticky_line)
      end
    end
    state.sticky = sticky
  end

  local prompt_content = ''
  local assistant_message = M.chat:get_message(constants.ROLE.ASSISTANT)
  local tool_calls = assistant_message and assistant_message.tool_calls or {}

  if not utils.empty(state.sticky) then
    for _, sticky in ipairs(state.sticky) do
      prompt_content = prompt_content .. '> ' .. sticky .. '\n'
    end
    prompt_content = prompt_content .. '\n'
  end

  if not utils.empty(tool_calls) then
    for _, tool_call in ipairs(tool_calls) do
      prompt_content = prompt_content .. string.format('#%s:%s\n', tool_call.name, tool_call.id)
    end
    prompt_content = prompt_content .. '\n'
  end

  M.chat:add_message({
    role = constants.ROLE.USER,
    content = prompt_content,
  })

  M.chat:finish()
end

--- Show an error in the chat window.
---@param config CopilotChat.config.Shared
---@param cb function
---@return any
local function handle_error(config, cb)
  return function()
    local ok, out = pcall(cb)
    if ok then
      return out
    end

    log.error(out)
    if config.headless then
      return
    end

    utils.schedule_main()
    out = out or 'Unknown error'
    out = utils.make_string(out)

    M.chat:add_message({
      role = constants.ROLE.ASSISTANT,
      content = '\n' .. string.format(BLOCK_OUTPUT_FORMAT, 'error', out) .. '\n',
    })

    finish()
  end
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
      key.callback(state.source)
    end
  end

  if key.normal and key.normal ~= '' then
    vim.keymap.set(
      'n',
      key.normal,
      fn,
      { buffer = bufnr, nowait = true, desc = constants.PLUGIN_NAME .. ' ' .. name:gsub('_', ' ') }
    )
  end
  if key.insert and key.insert ~= '' then
    vim.keymap.set('i', key.insert, function()
      -- If in insert mode and menu visible, use original key
      if vim.fn.pumvisible() == 1 then
        local used_key = key.insert == M.config.mappings.complete.insert and '<C-y>' or key.insert
        if used_key then
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(used_key, true, false, true), 'n', false)
        end
      else
        fn()
      end
    end, { buffer = bufnr, desc = constants.PLUGIN_NAME .. ' ' .. name:gsub('_', ' ') })
  end
end

--- Updates the source buffer based on previous or current window.
local function update_source()
  local use_prev_window = M.chat:focused()
  M.set_source(use_prev_window and vim.fn.win_getid(vim.fn.winnr('#')) or vim.api.nvim_get_current_win())
end

--- Call and resolve function calls from the prompt.
---@param prompt string?
---@param config CopilotChat.config.Shared?
---@return table<CopilotChat.client.Tool>, table<CopilotChat.client.Resource>, table, string
---@async
function M.resolve_functions(prompt, config)
  config, prompt = M.resolve_prompt(prompt, config)

  local tools = {}
  for _, tool in ipairs(functions.parse_tools(M.config.functions)) do
    tools[tool.name] = tool
  end

  local enabled_tools = {}
  local resolved_resources = {}
  local resolved_tools = {}
  local matches = utils.to_table(config.tools)
  local tool_calls = {}
  for _, message in ipairs(M.chat.messages) do
    if message.tool_calls then
      for _, tool_call in ipairs(message.tool_calls) do
        table.insert(tool_calls, tool_call)
      end
    end
  end

  -- Check for @tool pattern to find enabled tools
  prompt = prompt:gsub('@' .. WORD, function(match)
    for name, tool in pairs(M.config.functions) do
      if name == match or tool.group == match then
        table.insert(matches, match)
        return ''
      end
    end
    return '@' .. match
  end)
  for _, match in ipairs(matches) do
    for name, tool in pairs(M.config.functions) do
      if name == match or tool.group == match then
        table.insert(enabled_tools, tools[name])
      end
    end
  end

  local matches = utils.ordered_map()

  -- Check for #word:`input` pattern
  for word, input in prompt:gmatch('#' .. WORD_WITH_INPUT_QUOTED) do
    local pattern = string.format('#%s:`%s`', word, input)
    matches:set(pattern, {
      word = word,
      input = input,
    })
  end

  -- Check for #word:input pattern
  for word, input in prompt:gmatch('#' .. WORD_WITH_INPUT_UNQUOTED) do
    local pattern = utils.empty(input) and string.format('#%s', word) or string.format('#%s:%s', word, input)
    matches:set(pattern, {
      word = word,
      input = input,
    })
  end

  -- Check for ##word:input pattern
  for word in prompt:gmatch('##' .. WORD_NO_INPUT) do
    local pattern = string.format('##%s', word)
    matches:set(pattern, {
      word = word,
    })
  end

  -- Resolve each function reference
  local function expand_function(name, input)
    notify.publish(notify.STATUS, 'Running function: ' .. name)

    local tool_id = nil
    if not utils.empty(tool_calls) then
      for _, tool_call in ipairs(tool_calls) do
        if tool_call.name == name and vim.trim(tool_call.id) == vim.trim(input) then
          input = utils.empty(tool_call.arguments) and {} or utils.json_decode(tool_call.arguments)
          tool_id = tool_call.id
          break
        end
      end
    end

    local tool = M.config.functions[name]
    if not tool then
      -- Check if input matches uri
      for tool_name, tool_spec in pairs(M.config.functions) do
        if tool_spec.uri then
          local match = functions.match_uri(name, tool_spec.uri)
          if match then
            name = tool_name
            tool = tool_spec
            input = match
            break
          end
        end
      end
    end
    if not tool then
      return nil
    end
    if not tool_id and not tool.uri then
      return nil
    end

    local schema = tools[name] and tools[name].schema or nil
    local result = ''
    local ok, output = pcall(tool.resolve, functions.parse_input(input, schema), state.source or {}, prompt)
    if not ok then
      result = string.format(BLOCK_OUTPUT_FORMAT, 'error', utils.make_string(output))
    else
      for _, content in ipairs(output) do
        if content then
          local content_out = nil
          if content.uri then
            content_out = '##' .. content.uri
            table.insert(resolved_resources, content)
            if tool_id then
              table.insert(state.sticky, content_out)
            end
          else
            content_out = string.format(BLOCK_OUTPUT_FORMAT, utils.mimetype_to_filetype(content.mimetype), content.data)
          end

          if not utils.empty(result) then
            result = result .. '\n'
          end
          result = result .. content_out
        end
      end
    end

    if tool_id then
      table.insert(resolved_tools, {
        id = tool_id,
        result = result,
      })

      return nil
    end

    return result
  end

  -- Resolve and process all tools
  for _, pattern in ipairs(matches:keys()) do
    if not utils.empty(pattern) then
      local match = matches:get(pattern)
      local out = expand_function(match.word, match.input) or pattern
      out = out:gsub('%%', '%%%%') -- Escape percent signs for gsub
      prompt = prompt:gsub(vim.pesc(pattern), out, 1)
    end
  end

  return enabled_tools, resolved_resources, resolved_tools, prompt
end

--- Resolve the final prompt and config from prompt template.
---@param prompt string?
---@param config CopilotChat.config.Shared?
---@return CopilotChat.config.prompts.Prompt, string
function M.resolve_prompt(prompt, config)
  if not prompt then
    local message = M.chat:get_message(constants.ROLE.USER)
    if message then
      prompt = message.content
    end
  end

  local prompts_to_use = list_prompts()
  local depth = 0
  local MAX_DEPTH = 10

  local function resolve(inner_config, inner_prompt)
    if depth >= MAX_DEPTH then
      return inner_config, inner_prompt
    end
    depth = depth + 1

    inner_prompt = string.gsub(inner_prompt, '/' .. WORD, function(match)
      local p = prompts_to_use[match]
      if p then
        local resolved_config, resolved_prompt = resolve(p, p.prompt or '')
        inner_config = vim.tbl_deep_extend('force', inner_config, resolved_config)
        return resolved_prompt
      end

      return '/' .. match
    end)

    depth = depth - 1
    return inner_config, inner_prompt
  end

  local function resolve_system_prompt(system_prompt)
    if type(system_prompt) == 'function' then
      local ok, result = pcall(system_prompt)
      if not ok then
        log.warn('Failed to resolve system prompt function: ' .. result)
        return nil
      end
      return result
    end

    return system_prompt
  end

  config = vim.tbl_deep_extend('force', M.config, config or {})
  config, prompt = resolve(config, prompt or '')

  if config.system_prompt then
    config.system_prompt = resolve_system_prompt(config.system_prompt)

    if M.config.prompts[config.system_prompt] then
      -- Name references are good for making system prompt auto sticky
      config.system_prompt = M.config.prompts[config.system_prompt].system_prompt
    end

    config.system_prompt = config.system_prompt .. '\n' .. M.config.prompts.COPILOT_BASE.system_prompt
    config.system_prompt = config.system_prompt:gsub('{OS_NAME}', jit.os)
    config.system_prompt = config.system_prompt:gsub('{LANGUAGE}', config.language)
    if state.source then
      config.system_prompt = config.system_prompt:gsub('{DIR}', state.source.cwd())
    end
  end

  return config, prompt
end

--- Resolve the model from the prompt.
---@param prompt string?
---@param config CopilotChat.config.Shared?
---@return string, string
---@async
function M.resolve_model(prompt, config)
  config, prompt = M.resolve_prompt(prompt, config)

  local models = vim.tbl_map(function(model)
    return model.id
  end, list_models())

  local selected_model = config.model or ''
  prompt = prompt:gsub('%$' .. WORD, function(match)
    if vim.tbl_contains(models, match) then
      selected_model = match
      return ''
    end
    return '$' .. match
  end)

  return selected_model, prompt
end

--- Get the current source buffer and window.
function M.get_source()
  return state.source
end

--- Sets the source to the given window.
---@param source_winnr number
---@return boolean if the source was set
function M.set_source(source_winnr)
  local source_bufnr = vim.api.nvim_win_get_buf(source_winnr)

  -- Check if the window is valid to use as a source
  if source_winnr ~= M.chat.winnr and source_bufnr ~= M.chat.bufnr and vim.fn.win_gettype(source_winnr) == '' then
    state.source = {
      bufnr = source_bufnr,
      winnr = source_winnr,
      cwd = function()
        local ok, dir = pcall(function()
          return vim.w[source_winnr].cchat_cwd
        end)
        if not ok or not dir or dir == '' then
          return '.'
        end
        return dir
      end,
    }

    return true
  end

  return false
end

--- Get the selection from the source buffer.
---@return CopilotChat.select.Selection?
function M.get_selection()
  local config = vim.tbl_deep_extend('force', M.config, M.chat.config)
  local selection = config.selection
  local bufnr = state.source and state.source.bufnr
  local winnr = state.source and state.source.winnr

  if selection and utils.buf_valid(bufnr) and winnr and vim.api.nvim_win_is_valid(winnr) then
    return selection(state.source)
  end

  return nil
end

--- Sets the selection to specific lines in buffer.
---@param bufnr number
---@param start_line number
---@param end_line number
---@param clear boolean?
function M.set_selection(bufnr, start_line, end_line, clear)
  if not utils.buf_valid(bufnr) then
    return
  end

  if clear then
    for _, mark in ipairs({ '<', '>', '[', ']' }) do
      pcall(vim.api.nvim_buf_del_mark, bufnr, mark)
    end
    update_highlights()
    return
  end

  local winnr = vim.fn.win_findbuf(bufnr)[1]
  if not winnr and state.source then
    winnr = state.source.winnr
  end
  if not winnr then
    return
  end

  pcall(vim.api.nvim_buf_set_mark, bufnr, '<', start_line, 0, {})
  pcall(vim.api.nvim_buf_set_mark, bufnr, '>', end_line, 0, {})
  pcall(vim.api.nvim_buf_set_mark, bufnr, '[', start_line, 0, {})
  pcall(vim.api.nvim_buf_set_mark, bufnr, ']', end_line, 0, {})
  pcall(vim.api.nvim_win_set_cursor, winnr, { start_line, 0 })
  update_highlights()
end

--- Open the chat window.
---@param config CopilotChat.config.Shared?
function M.open(config)
  config = vim.tbl_deep_extend('force', M.config, config or {})
  utils.return_to_normal_mode()

  M.chat:open(config)

  -- Add sticky values from provided config when opening the chat
  local message = M.chat:get_message(constants.ROLE.USER)
  if message then
    local prompt = insert_sticky(message.content, config)
    if prompt then
      M.chat:add_message({
        role = constants.ROLE.USER,
        content = '\n' .. prompt,
      }, true)
    end
  end

  M.chat:follow()
  M.chat:focus()
end

--- Close the chat window.
function M.close()
  M.chat:close(state.source and state.source.bufnr or nil)
end

--- Toggle the chat window.
---@param config CopilotChat.config.Shared?
function M.toggle(config)
  if M.chat:visible() then
    M.close()
  else
    M.open(config)
  end
end

--- Select default Copilot GPT model.
function M.select_model()
  async.run(function()
    local models = list_models()
    local choices = vim.tbl_map(function(model)
      return {
        id = model.id,
        name = model.name,
        provider = model.provider,
        streaming = model.streaming,
        tools = model.tools,
        reasoning = model.reasoning,
        selected = model.id == M.config.model,
      }
    end, models)

    utils.schedule_main()
    vim.ui.select(choices, {
      prompt = 'Select a model> ',
      format_item = function(item)
        local indicators = {}
        local out = item.name

        if item.selected then
          out = '* ' .. out
        end

        if item.provider then
          table.insert(indicators, item.provider)
        end
        if item.streaming then
          table.insert(indicators, 'streaming')
        end
        if item.tools then
          table.insert(indicators, 'tools')
        end
        if item.reasoning then
          table.insert(indicators, 'reasoning')
        end

        if #indicators > 0 then
          out = out .. ' [' .. table.concat(indicators, ', ') .. ']'
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

--- Select a prompt template to use.
---@param config CopilotChat.config.Shared?
function M.select_prompt(config)
  local prompts = list_prompts()
  local keys = vim.tbl_keys(prompts)
  table.sort(keys)

  local choices = vim
    .iter(keys)
    :map(function(name)
      return {
        name = name,
        description = prompts[name].description,
        prompt = prompts[name].prompt,
      }
    end)
    :filter(function(choice)
      return choice.prompt
    end)
    :totable()

  vim.ui.select(choices, {
    prompt = 'Select prompt action> ',
    format_item = function(item)
      return string.format('%s: %s', item.name, item.description or item.prompt:gsub('\n', ' '))
    end,
  }, function(choice)
    if choice then
      M.ask(prompts[choice.name].prompt, vim.tbl_extend('force', prompts[choice.name], config or {}))
    end
  end)
end

--- Ask a question to the Copilot model.
---@param prompt string?
---@param config CopilotChat.config.Shared?
function M.ask(prompt, config)
  prompt = prompt or ''
  if prompt == '' then
    return
  end

  vim.diagnostic.reset(vim.api.nvim_create_namespace('copilot-chat-diagnostics'))
  config = vim.tbl_deep_extend('force', M.config, config or {})
  local schedule = function(cb)
    return cb()
  end

  -- Stop previous conversation and open window
  if not config.headless then
    if config.clear_chat_on_new_prompt then
      M.stop(true)
    elseif client:stop() then
      finish()
    end
    if not M.chat:focused() then
      M.open(config)
      schedule = vim.schedule
    end
  else
    update_source()
  end

  -- Resolve prompt after window is opened
  prompt = insert_sticky(prompt, config)
  prompt = vim.trim(prompt)

  -- After opening window we need to schedule to next cycle so everything properly resolves
  schedule(function()
    -- Prepare chat
    if not config.headless then
      store_sticky(prompt)
      M.chat:start()
      M.chat:append('\n')
    end

    -- Resolve prompt references
    config, prompt = M.resolve_prompt(prompt, config)
    local system_prompt = config.system_prompt or ''

    -- Remove sticky prefix
    prompt = table.concat(
      vim.tbl_map(function(l)
        return l:gsub('^>%s+', '')
      end, vim.split(prompt, '\n')),
      '\n'
    )

    -- Retrieve the selection
    local selection = M.get_selection()

    async.run(handle_error(config, function()
      local selected_tools, resolved_resources, resolved_tools, prompt = M.resolve_functions(prompt, config)
      local selected_model, prompt = M.resolve_model(prompt, config)

      prompt = vim.trim(prompt)

      if not config.headless then
        utils.schedule_main()
        local assistant_message = M.chat:get_message(constants.ROLE.ASSISTANT)
        if assistant_message and assistant_message.tool_calls then
          local handled_ids = {}
          for _, tool in ipairs(resolved_tools) do
            handled_ids[tool.id] = true
          end

          -- If we skipped any tool calls, send that as result
          for _, tool_call in ipairs(assistant_message.tool_calls) do
            if not handled_ids[tool_call.id] then
              table.insert(resolved_tools, {
                id = tool_call.id,
                result = string.format(BLOCK_OUTPUT_FORMAT, 'error', 'User skipped this function call.'),
              })
              handled_ids[tool_call.id] = true
            end
          end
        end

        if not utils.empty(resolved_tools) then
          -- If we are handling tools, replace user message with tool results
          M.chat:remove_message(constants.ROLE.USER)
          for _, tool in ipairs(resolved_tools) do
            M.chat:add_message({
              id = tool.id,
              role = constants.ROLE.TOOL,
              tool_call_id = tool.id,
              content = '\n' .. tool.result .. '\n',
            })
          end
        else
          -- Otherwise just replace the user message with resolved prompt
          M.chat:add_message({
            role = constants.ROLE.USER,
            content = '\n' .. prompt .. '\n',
          }, true)
        end
      end

      if utils.empty(prompt) and utils.empty(resolved_tools) then
        if not config.headless then
          M.chat:remove_message(constants.ROLE.USER)
          finish()
        end
        return
      end

      local ask_response = client.ask(client, prompt, {
        headless = config.headless,
        history = M.chat.messages,
        selection = selection,
        resources = resolved_resources,
        tools = selected_tools,
        system_prompt = system_prompt,
        model = selected_model,
        temperature = config.temperature,
        on_progress = vim.schedule_wrap(function(message)
          if not config.headless then
            M.chat:add_message(message)
          end
        end),
      })

      -- If there was no error and no response, it means job was cancelled
      if ask_response == nil then
        return
      end

      local response = ask_response.message
      local token_count = ask_response.token_count
      local token_max_count = ask_response.token_max_count

      -- Call the callback function
      if config.callback then
        utils.schedule_main()
        config.callback(response, state.source)
      end

      if not config.headless then
        response.content = vim.trim(response.content)
        if utils.empty(response.content) then
          response.content = ''
        else
          response.content = '\n' .. response.content .. '\n'
        end

        utils.schedule_main()
        M.chat:add_message(response, true)
        M.chat.token_count = token_count
        M.chat.token_max_count = token_max_count
        finish()
      end
    end))
  end)
end

--- Stop current copilot output and optionally reset the chat ten show the help message.
---@param reset boolean?
function M.stop(reset)
  local stopped = client:stop()

  if reset then
    M.chat:clear()
    vim.diagnostic.reset(vim.api.nvim_create_namespace('copilot-chat-diagnostics'))

    -- Clear the selection
    if state.source then
      M.set_selection(state.source.bufnr, 0, 0, true)
    end
  end

  if stopped or reset then
    finish(reset)
  end
end

--- Reset the chat window and show the help message.
function M.reset()
  M.stop(true)
end

--- Save the chat history to a file.
---@param name string?
---@param history_path string?
function M.save(name, history_path)
  if not name or name == '' then
    name = 'default'
  end

  history_path = history_path or M.config.history_path
  if not history_path then
    return
  end

  local history = vim.deepcopy(M.chat.messages)
  for _, message in ipairs(history) do
    message.section = nil
  end
  history_path = vim.fs.normalize(history_path)
  vim.fn.mkdir(history_path, 'p')
  history_path = history_path .. '/' .. name .. '.json'
  local file = io.open(history_path, 'w')
  if not file then
    log.error('Failed to save history to ' .. history_path)
    return
  end
  file:write(vim.json.encode(history))
  file:close()

  log.info('Saved history to ' .. history_path)
end

--- Load the chat history from a file.
---@param name string?
---@param history_path string?
function M.load(name, history_path)
  if not name or name == '' then
    name = 'default'
  end

  history_path = history_path or M.config.history_path
  if not history_path then
    return
  end

  history_path = vim.fs.normalize(history_path) .. '/' .. name .. '.json'
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

  log.info('Loaded history from ' .. history_path)

  M.stop(true)
  for _, message in ipairs(history) do
    M.chat:add_message(message)
  end

  finish(#history == 0)
end

--- Set the log level
---@param level string
function M.log_level(level)
  M.config.log_level = level
  M.config.debug = level == 'debug'

  log.new({
    plugin = constants.PLUGIN_NAME,
    level = level,
    outfile = M.config.log_path,
    fmt_msg = function(is_console, mode_name, src_path, src_line, msg)
      local nameupper = mode_name:upper()
      if is_console then
        return string.format('[%s] %s', nameupper, msg)
      else
        local lineinfo = src_path .. ':' .. src_line
        return string.format('[%-6s%s] %s: %s\n', nameupper, os.date(), lineinfo, msg)
      end
    end,
  }, true)
end

--- Set up the plugin
---@param config CopilotChat.config.Config?
function M.setup(config)
  -- Little bit of update magic
  for k, v in pairs(vim.tbl_deep_extend('force', M.config, config or {})) do
    M.config[k] = v
  end

  -- Save proxy and insecure settings
  utils.curl_store_args({
    insecure = M.config.allow_insecure,
    proxy = M.config.proxy,
  })

  -- Load the providers
  client:stop()
  client:add_providers(function()
    return M.config.providers
  end)

  if M.config.debug then
    M.log_level('debug')
  else
    M.log_level(M.config.log_level)
  end

  if not M.config.separator or M.config.separator == '' then
    log.warn(
      'Empty separator is not allowed, using default separator instead. Set `separator` in config to change this.'
    )
    M.config.separator = '---'
  end

  if M.chat then
    M.chat:close(state.source and state.source.bufnr or nil)
    M.chat:delete()
  end
  M.chat = require('CopilotChat.ui.chat')(M.config, function(bufnr)
    for name, _ in pairs(M.config.mappings) do
      map_key(name, bufnr)
    end

    require('CopilotChat.completion').enable(bufnr, M.config.chat_autocomplete)

    vim.api.nvim_create_autocmd({ 'BufEnter', 'BufLeave' }, {
      buffer = bufnr,
      callback = function(ev)
        if ev.event == 'BufEnter' then
          update_source()
        end

        vim.schedule(update_highlights)
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

    finish(true)
  end)

  for name, prompt in pairs(list_prompts()) do
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
        desc = prompt.description or (constants.PLUGIN_NAME .. ' ' .. name),
      })

      if prompt.mapping then
        vim.keymap.set({ 'n', 'v' }, prompt.mapping, function()
          M.ask(prompt.prompt, prompt)
        end, { desc = prompt.description or (constants.PLUGIN_NAME .. ' ' .. name) })
      end
    end
  end
end

return M
