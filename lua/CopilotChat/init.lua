local async = require('plenary.async')
local log = require('plenary.log')
local tools = require('CopilotChat.tools')
local client = require('CopilotChat.client')
local notify = require('CopilotChat.notify')
local utils = require('CopilotChat.utils')

local PLUGIN_NAME = 'CopilotChat'
local WORD = '([^%s:]+)'
local WORD_WITH_INPUT_QUOTED = WORD .. ':`([^`]+)`'
local WORD_WITH_INPUT_UNQUOTED = WORD .. ':?([^%s`]*)'
local TOOL_OUTPUT_FORMAT = '```%s tool=%s id=%s\n%s\n```'
local REFERENCE_FORMAT = '#%s:`%s`'

---@class CopilotChat
---@field config CopilotChat.config.Config
---@field chat CopilotChat.ui.chat.Chat
local M = {}

--- @class CopilotChat.source
--- @field bufnr number
--- @field winnr number
--- @field cwd fun():string

--- @class CopilotChat.state
--- @field source CopilotChat.source?
--- @field sticky string[]?
--- @field highlights_loaded boolean
local state = {
  -- Current state tracking
  source = nil,

  -- Last state tracking
  sticky = nil,
  highlights_loaded = false,
}

--- Insert sticky values from config into prompt
---@param prompt string
---@param config CopilotChat.config.Shared
local function insert_sticky(prompt, config)
  local lines = vim.split(prompt or '', '\n')
  local stickies = utils.ordered_map()

  local sticky_indices = {}
  for i, line in ipairs(lines) do
    if vim.startswith(line, '> ') then
      table.insert(sticky_indices, i)
      stickies:set(vim.trim(line:sub(3)), true)
    end
  end
  for i = #sticky_indices, 1, -1 do
    table.remove(lines, sticky_indices[i])
  end

  lines = vim.split(vim.trim(table.concat(lines, '\n')), '\n')

  if config.remember_as_sticky and config.model and config.model ~= M.config.model then
    stickies:set('$' .. config.model, true)
  end

  if config.remember_as_sticky and config.group and not vim.deep_equal(config.group, M.config.group) then
    if type(config.group) == 'table' then
      ---@diagnostic disable-next-line: param-type-mismatch
      for _, group in ipairs(config.group) do
        stickies:set('@' .. group, true)
      end
    else
      stickies:set('@' .. config.group, true)
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
    if type(config.sticky) == 'table' then
      ---@diagnostic disable-next-line: param-type-mismatch
      for _, sticky in ipairs(config.sticky) do
        stickies:set(sticky, true)
      end
    else
      stickies:set(config.sticky, true)
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

  if state.highlights_loaded then
    return
  end

  async.run(function()
    local items = M.complete_items()
    utils.schedule_main()

    for _, item in ipairs(items) do
      vim.cmd('syntax match CopilotChatKeyword "' .. vim.fn.escape(item.word, '.-$^*[]') .. '" containedin=ALL')
    end

    state.highlights_loaded = true
  end)
end

--- Finish writing to chat buffer.
---@param start_of_chat boolean?
local function finish(start_of_chat)
  if start_of_chat then
    local sticky = {}
    if M.config.sticky then
      if type(M.config.sticky) == 'table' then
        ---@diagnostic disable-next-line: param-type-mismatch
        for _, sticky_line in ipairs(M.config.sticky) do
          table.insert(sticky, sticky_line)
        end
      else
        table.insert(sticky, M.config.sticky)
      end
    end
    state.sticky = sticky
  else
    M.chat:append('\n\n')
  end

  M.chat:append(M.config.question_header .. M.config.separator .. '\n\n')

  if not utils.empty(M.chat.tool_calls) then
    for _, tool_call in ipairs(M.chat.tool_calls) do
      M.chat:append(string.format('#%s:%s\n', tool_call.name, tool_call.id))
    end
    M.chat:append('\n')
  end

  if not utils.empty(state.sticky) then
    for _, sticky in ipairs(state.sticky) do
      M.chat:append('> ' .. sticky .. '\n')
    end
    M.chat:append('\n')
  end

  M.chat:finish()
end

--- Show an error in the chat window.
---@param err string|table|nil
local function show_error(err)
  err = err or 'Unknown error'
  err = utils.make_string(err)
  M.chat:append('\n' .. M.config.error_header .. '\n```error\n' .. err .. '\n```')
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
      key.callback(state.source)
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
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(used_key, true, false, true), 'n', false)
        end
      else
        fn()
      end
    end, { buffer = bufnr, desc = PLUGIN_NAME .. ' ' .. name:gsub('_', ' ') })
  end
end

--- Updates the source buffer based on previous or current window.
local function update_source()
  local use_prev_window = M.chat:focused()
  M.set_source(use_prev_window and vim.fn.win_getid(vim.fn.winnr('#')) or vim.api.nvim_get_current_win())
end

--- Call and resolve tools from the prompt.
---@param prompt string?
---@param config CopilotChat.config.Shared?
---@param resolved_tools table<string, CopilotChat.config.tools.Tool>
---@return table<CopilotChat.client.Resource>, string
---@async
local function call_tools(prompt, config, resolved_tools)
  config, prompt = M.resolve_prompt(prompt, config)

  local resources = {}
  local tool_matches = utils.ordered_map()

  -- Check for #word:`input` pattern
  for word, input in prompt:gmatch('#' .. WORD_WITH_INPUT_QUOTED) do
    local pattern = string.format('#%s:`%s`', word, input)
    tool_matches:set(pattern, {
      word = word,
      input = input,
    })
  end

  -- Check for #word:input pattern
  for word, input in prompt:gmatch('#' .. WORD_WITH_INPUT_UNQUOTED) do
    local pattern = utils.empty(input) and string.format('#%s', word) or string.format('#%s:%s', word, input)
    tool_matches:set(pattern, {
      word = word,
      input = input,
    })
  end

  -- Resolve each tool reference
  local function expand_tool(name, input)
    notify.publish(notify.STATUS, 'Running tool: ' .. name)

    local tool_id = nil
    if not utils.empty(M.chat.tool_calls) then
      for _, tool_call in ipairs(M.chat.tool_calls) do
        if tool_call.name == name and vim.trim(tool_call.id) == vim.trim(input) then
          input = utils.empty(tool_call.arguments) and {} or utils.json_decode(tool_call.arguments)
          tool_id = tool_call.id
          break
        end
      end
    end

    local tool = resolved_tools[name]
    if not tool and not tool_id then
      -- If we are using tool directly, ignore grouping
      tool = M.config.tools[name]
    end
    if not tool then
      return nil
    end

    local ok, output = pcall(tool.resolve, tools.parse_input(input, tool.schema), state.source or {}, prompt)
    if not ok then
      return string.format(TOOL_OUTPUT_FORMAT, 'error', name, tool_id or '', utils.make_string(output)) .. '\n'
    end

    local result = ''
    for _, content in ipairs(output) do
      if content then
        if content.type == 'resource' then
          table.insert(resources, content)
          local reference_type = vim.startswith(content.uri, 'file://') and 'file' or 'url'
          local filename = utils.uri_to_filename(content.uri)
          if not utils.empty(result) then
            result = result .. '\n'
          end
          local reference = string.format(REFERENCE_FORMAT, reference_type, filename)
          result = result .. reference
          if tool_id then
            table.insert(state.sticky, reference)
          end
        else
          if not utils.empty(result) then
            result = result .. '\n'
          end
          result = result .. string.format(TOOL_OUTPUT_FORMAT, content.type, name, tool_id or '', content.data)
        end
      end
    end

    return result
  end

  -- Resolve and process all tools
  for _, pattern in ipairs(tool_matches:keys()) do
    local match = tool_matches:get(pattern)
    local out = expand_tool(match.word, match.input) or pattern
    prompt = prompt:gsub(vim.pesc(pattern), out, 1)
  end

  return resources, prompt
end

--- Resolve the final prompt and config from prompt template.
---@param prompt string?
---@param config CopilotChat.config.Shared?
---@return CopilotChat.config.prompts.Prompt, string
function M.resolve_prompt(prompt, config)
  if not prompt then
    local section = M.chat:get_prompt()
    if section then
      prompt = section.content
    end
  end

  local prompts_to_use = M.prompts()
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

  config = vim.tbl_deep_extend('force', M.config, config or {})
  config, prompt = resolve(config, prompt or '')
  if prompts_to_use[config.system_prompt] then
    config.system_prompt = prompts_to_use[config.system_prompt].system_prompt
  end

  if config.system_prompt then
    config.system_prompt = config.system_prompt:gsub('{OS_NAME}', vim.uv.os_uname().sysname)
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
  end, client:list_models())

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

--- Resolve the tools from the prompt.
---@param prompt string?
---@param config CopilotChat.config.Shared?
---@return table<string, CopilotChat.config.tools.Tool>, string
function M.resolve_tools(prompt, config)
  config, prompt = M.resolve_prompt(prompt, config)

  local groups = {}
  if config.group then
    if type(config.group) == 'table' then
      ---@diagnostic disable-next-line: param-type-mismatch
      vim.list_extend(groups, config.group)
    else
      table.insert(groups, config.group)
    end
  end

  prompt = prompt:gsub('@' .. WORD, function(match)
    local group = vim
      .iter(vim.tbl_values(M.config.tools))
      :filter(function(tool)
        return tool.group == match
      end)
      :next()

    if group then
      table.insert(groups, match)
      return ''
    end
    return '@' .. match
  end)

  local out = {}
  for _, group in ipairs(groups) do
    for name, tool in pairs(M.config.tools) do
      if not tool.group or tool.group == group then
        out[name] = tool
      end
    end
  end
  return out, prompt
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
        local dir = vim.w[source_winnr].cchat_cwd
        if not dir or dir == '' then
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

--- Trigger the completion for the chat window.
---@param without_input boolean?
function M.trigger_complete(without_input)
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

  if not without_input and vim.startswith(prefix, '#') and vim.endswith(prefix, ':') then
    local found_tool = M.config.tools[prefix:sub(2, -2)]
    if found_tool and found_tool.schema then
      async.run(function()
        local value = tools.enter_input(found_tool.schema, state.source)
        if not value then
          return
        end

        utils.schedule_main()
        vim.api.nvim_buf_set_text(bufnr, row - 1, col, row - 1, col, { value })
        vim.api.nvim_win_set_cursor(0, { row, col + #value })
      end)
    end

    return
  end

  async.run(function()
    local items = M.complete_items()
    utils.schedule_main()

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
---@return table
---@async
function M.complete_items()
  local models = client:list_models()
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

  local all_groups = {}
  for name, tool in pairs(M.config.tools) do
    if tool.group then
      all_groups[tool.group] = all_groups[tool.group] or {}
      all_groups[tool.group][name] = tool
    end
  end
  for name, group in pairs(all_groups) do
    local group_tools = vim.tbl_keys(group)
    items[#items + 1] = {
      word = '@' .. name,
      abbr = name,
      kind = 'group',
      info = table.concat(group_tools, '\n'),
      menu = string.format('%s tools', #group_tools),
      icase = 1,
      dup = 0,
      empty = 0,
    }
  end

  local tools_to_use = tools.parse_tools(M.config.tools)
  for _, tool in pairs(tools_to_use) do
    items[#items + 1] = {
      word = '#' .. tool.name,
      abbr = tool.name,
      kind = M.config.tools[tool.name].group,
      info = vim.inspect(tool.schema),
      menu = vim.trim(tool.description or ''),
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

  return items
end

--- Get the prompts to use.
---@return table<string, CopilotChat.config.prompts.Prompt>
function M.prompts()
  local prompts_to_use = {}

  for name, prompt in pairs(M.config.prompts) do
    local val = prompt
    if type(prompt) == 'string' then
      val = {
        prompt = prompt,
      }
    end

    if val.system_prompt and M.config.prompts[val.system_prompt] then
      val.system_prompt = M.config.prompts[val.system_prompt].system_prompt
    end

    prompts_to_use[name] = val
  end

  return prompts_to_use
end

--- Open the chat window.
---@param config CopilotChat.config.Shared?
function M.open(config)
  config = vim.tbl_deep_extend('force', M.config, config or {})
  utils.return_to_normal_mode()

  M.chat:open(config)

  local section = M.chat:get_prompt()
  if section then
    local prompt = insert_sticky(section.content, config)
    if prompt then
      M.chat:set_prompt(prompt)
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
    local models = client:list_models()
    local choices = vim.tbl_map(function(model)
      return {
        id = model.id,
        name = model.name,
        provider = model.provider,
        selected = model.id == M.config.model,
      }
    end, models)

    utils.schedule_main()
    vim.ui.select(choices, {
      prompt = 'Select a model> ',
      format_item = function(item)
        local out = string.format('%s (%s:%s)', item.name, item.provider, item.id)
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

--- Select a prompt template to use.
---@param config CopilotChat.config.Shared?
function M.select_prompt(config)
  local prompts = M.prompts()
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
  prompt = insert_sticky(prompt, config)
  prompt = vim.trim(prompt)

  if not config.headless then
    if config.clear_chat_on_new_prompt then
      M.stop(true)
    elseif client:stop() then
      finish()
    end

    if not M.chat:focused() then
      M.open(config)
    end

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
    M.chat:set_prompt(prompt)
    M.chat:append('\n\n')
    M.chat:follow()
  else
    update_source()
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

  local ok, err = pcall(async.run, function()
    local selected_tools, prompt = M.resolve_tools(prompt, config)
    local selected_model, prompt = M.resolve_model(prompt, config)
    local resources, prompt = call_tools(prompt, config, selected_tools)
    local query_ok, resources = pcall(tools.process_resources, prompt, selected_model, config.headless, resources)

    if not query_ok then
      utils.schedule_main()
      log.error(resources)
      if not config.headless then
        show_error(resources)
      end
      return
    end

    if not config.headless then
      utils.schedule_main()
      M.chat:set_prompt(vim.trim(prompt))
      M.chat:append('\n\n' .. M.config.answer_header .. M.config.separator .. '\n\n')
      M.chat:follow()
    end

    local ask_ok, ask_response = pcall(client.ask, client, prompt, {
      headless = config.headless,
      selection = selection,
      resources = resources,
      tools = tools.parse_tools(selected_tools),
      system_prompt = system_prompt,
      model = selected_model,
      temperature = config.temperature,
      on_progress = vim.schedule_wrap(function(token)
        local out = config.stream and config.stream(token, state.source) or nil
        if out == nil then
          out = token
        end
        local to_print = not config.headless and out
        if to_print and to_print ~= '' then
          M.chat:append(token)
        end
      end),
    })

    utils.schedule_main()

    if not ask_ok then
      log.error(ask_response)
      if not config.headless then
        show_error(ask_response)
      end
      return
    end

    -- If there was no error and no response, it means job was cancelled
    if ask_response == nil then
      return
    end

    local response = ask_response.content
    local references = ask_response.references
    local token_count = ask_response.token_count
    local token_max_count = ask_response.token_max_count
    local tool_calls = ask_response.tool_calls

    -- Call the callback function and store to history
    local out = config.callback and config.callback(response, state.source) or nil
    if out == nil then
      out = response
    end
    local to_store = not config.headless and out
    if to_store and to_store ~= '' then
      table.insert(client.history, {
        content = prompt,
        role = 'user',
      })
      table.insert(client.history, {
        content = to_store,
        role = 'assistant',
      })
    end

    if not config.headless then
      M.chat.tool_calls = tool_calls
      M.chat.references = references
      M.chat.token_count = token_count
      M.chat.token_max_count = token_max_count
      finish()
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
  local stopped = false

  if reset then
    client:reset()
    M.chat:clear()
    vim.diagnostic.reset(vim.api.nvim_create_namespace('copilot-chat-diagnostics'))

    -- Clear the selection
    if state.source then
      M.set_selection(state.source.bufnr, 0, 0, true)
    end

    stopped = true
  else
    stopped = client:stop()
  end

  if stopped then
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

  local prompt = M.chat:get_prompt()
  local history = vim.list_slice(client.history)
  if prompt then
    table.insert(history, {
      content = prompt.content,
      role = 'user',
    })
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

  client:reset()
  M.chat:clear()

  client.history = history
  for i, message in ipairs(history) do
    if message.role == 'user' then
      if i > 1 then
        M.chat:append('\n\n')
      end
      M.chat:append(M.config.question_header .. M.config.separator .. '\n\n')
      M.chat:append(message.content)
    elseif message.role == 'assistant' then
      M.chat:append('\n\n' .. M.config.answer_header .. M.config.separator .. '\n\n')
      M.chat:append(message.content)
    end
  end

  log.info('Loaded history from ' .. history_path)

  if #history > 0 then
    local last = history[#history]
    if last and last.role == 'user' then
      M.chat:append('\n\n')
      M.chat:finish()
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
---@param config CopilotChat.config.Config?
function M.setup(config)
  M.config = vim.tbl_deep_extend('force', require('CopilotChat.config'), config or {})
  state.highlights_loaded = false

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

  if M.chat then
    M.chat:close(state.source and state.source.bufnr or nil)
    M.chat:delete()
  end
  M.chat = require('CopilotChat.ui.chat')(
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

      if M.config.chat_autocomplete then
        vim.api.nvim_create_autocmd('TextChangedI', {
          buffer = bufnr,
          callback = function()
            local completeopt = vim.opt.completeopt:get()
            if not vim.tbl_contains(completeopt, 'noinsert') and not vim.tbl_contains(completeopt, 'noselect') then
              -- Don't trigger completion if completeopt is not set to noinsert or noselect
              return
            end

            local line = vim.api.nvim_get_current_line()
            local cursor = vim.api.nvim_win_get_cursor(0)
            local col = cursor[2]
            local char = line:sub(col, col)

            if vim.tbl_contains(M.complete_info().triggers, char) then
              utils.debounce('complete', function()
                M.trigger_complete(true)
              end, 100)
            end
          end,
        })

        -- Add noinsert completeopt if not present
        if vim.fn.has('nvim-0.11.0') == 1 then
          local completeopt = vim.opt.completeopt:get()
          if not vim.tbl_contains(completeopt, 'noinsert') then
            table.insert(completeopt, 'noinsert')
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
end

return M
