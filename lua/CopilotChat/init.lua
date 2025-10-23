local async = require('plenary.async')
local log = require('plenary.log')
local client = require('CopilotChat.client')
local constants = require('CopilotChat.constants')
local prompts = require('CopilotChat.prompts')
local select = require('CopilotChat.select')
local utils = require('CopilotChat.utils')
local curl = require('CopilotChat.utils.curl')
local orderedmap = require('CopilotChat.utils.orderedmap')

local BLOCK_OUTPUT_FORMAT = '```%s\n%s\n```'

---@class CopilotChat
---@field config CopilotChat.config.Config
---@field chat CopilotChat.ui.chat.Chat
local M = setmetatable({}, {
  __index = function(t, key)
    if key == 'config' then
      return require('CopilotChat.config')
    end

    -- Lazy initialize
    local initialized = rawget(t, 'initialized')
    if not initialized then
      rawset(t, 'initialized', true)
      rawget(t, 'setup')()
    end

    return rawget(t, key)
  end,
})

--- Process sticky values from prompt and config
--- Extracts stickies from prompt, adds config-based stickies, stores them, returns clean prompt
---@param prompt string
---@param config CopilotChat.config.Shared
---@return string clean_prompt The prompt without sticky prefixes
local function process_sticky(prompt, config)
  local existing_prompt = M.chat:get_message(constants.ROLE.USER)
  local combined_prompt = (existing_prompt and existing_prompt.content or '') .. '\n' .. (prompt or '')
  local lines = vim.split(prompt or '', '\n')
  local stickies = orderedmap()

  -- Extract existing stickies from combined prompt
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

  -- Find sticky lines in new prompt to remove them
  for i, line in ipairs(lines) do
    if vim.startswith(line, '> ') then
      table.insert(sticky_indices, i)
    end
  end
  for i = #sticky_indices, 1, -1 do
    table.remove(lines, sticky_indices[i])
  end

  lines = vim.split(vim.trim(table.concat(lines, '\n')), '\n')

  -- Add config-based stickies
  if config.remember_as_sticky and config.model and config.model ~= M.config.model then
    stickies:set('$' .. config.model, true)
  end

  if config.remember_as_sticky and config.tools and not vim.deep_equal(config.tools, M.config.tools) then
    for _, tool in ipairs(utils.to_table(config.tools)) do
      stickies:set('@' .. tool, true)
    end
  end

  if config.remember_as_sticky and config.resources and not vim.deep_equal(config.resources, M.config.resources) then
    for _, resource in ipairs(utils.to_table(config.resources)) do
      stickies:set('#' .. resource, true)
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

  -- Store stickies
  local sticky_array = {}
  for _, sticky in ipairs(stickies:keys()) do
    if sticky ~= '' then
      table.insert(sticky_array, sticky)
    end
  end
  M.chat:set_sticky(sticky_array)

  -- Return clean prompt
  return table.concat(lines, '\n')
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
    M.chat:set_sticky(sticky)
  end

  local prompt_content = ''
  local assistant_message = M.chat:get_message(constants.ROLE.ASSISTANT)
  local tool_calls = assistant_message and assistant_message.tool_calls or {}

  local current_sticky = M.chat:get_sticky()
  if not utils.empty(current_sticky) then
    for _, sticky in ipairs(current_sticky) do
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
    local function error_handler(err)
      return {
        err = utils.make_string(err),
        traceback = debug.traceback(),
      }
    end

    local ok, out = xpcall(cb, error_handler)
    if ok then
      return out
    end
    log.error(out.err .. '\n' .. out.traceback)

    if config.headless then
      return
    end

    utils.schedule_main()
    out = out.err

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
      key.callback(M.chat:get_source())
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
  M.chat:set_source(use_prev_window and vim.fn.win_getid(vim.fn.winnr('#')) or vim.api.nvim_get_current_win())
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
    local clean_prompt = process_sticky(message.content, config)
    if clean_prompt and clean_prompt ~= '' then
      M.chat:add_message({
        role = constants.ROLE.USER,
        content = '\n> ' .. table.concat(M.chat:get_sticky(), '\n> ') .. '\n\n' .. clean_prompt,
      }, true)
    end
  end

  M.chat:follow()
  M.chat:focus()
end

--- Close the chat window.
function M.close()
  M.chat:close()
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

    models = vim.tbl_map(function(id)
      return models[id]
    end, result)

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
  local prompts = prompts.list_prompts()
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
  prompt = process_sticky(prompt, config)
  prompt = vim.trim(prompt)
  prompt = table.concat(M.chat:get_sticky(), '\n') .. '\n\n' .. prompt

  -- After opening window we need to schedule to next cycle so everything properly resolves
  schedule(function()
    if not config.headless then
      -- Prepare chat
      M.chat:start()
      M.chat:append('\n')
    end

    async.run(handle_error(config, function()
      config, prompt = prompts.resolve_prompt(prompt, config)
      local system_prompt = config.system_prompt or ''
      local selected_tools, prompt = prompts.resolve_tools(prompt, config)
      local resolved_resources, resolved_tools, resolved_stickies, prompt = prompts.resolve_functions(prompt, config)
      local selected_model, prompt = prompts.resolve_model(prompt, config)

      -- Store resolved stickies to chat
      local current_sticky = M.chat:get_sticky()
      for _, sticky in ipairs(resolved_stickies) do
        table.insert(current_sticky, sticky)
      end
      M.chat:set_sticky(current_sticky)

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
                result = 'User skipped this function call.',
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

      -- Build history, when in headless mode its just current prompt
      local history
      if not config.headless then
        history = M.chat:get_messages()
      else
        history = {
          {
            content = prompt,
            role = constants.ROLE.USER,
          },
        }
      end

      local ask_response = client:ask({
        headless = config.headless,
        history = history,
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

      -- If there was no error and no response, it means job was canceled
      if ask_response == nil then
        return
      end

      local response = ask_response.message
      local token_count = ask_response.token_count
      local token_max_count = ask_response.token_max_count

      -- Call the callback function
      if config.callback then
        utils.schedule_main()
        config.callback(response, M.chat:get_source())
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
    select.set(M.chat:get_source().bufnr)
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

  local history = vim.deepcopy(M.chat:get_messages())
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

  if level ~= log.level then
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
    log.level = level
  end
end

--- Set up the plugin
---@param config CopilotChat.config.Config?
function M.setup(config)
  for k, v in pairs(vim.tbl_deep_extend('force', M.config, config or {})) do
    M.config[k] = v
  end

  if not M.config.separator or M.config.separator == '' then
    log.warn(
      'Empty separator is not allowed, using default separator instead. Set `separator` in config to change this.'
    )
    M.config.separator = '---'
  end

  -- Set log level
  if M.config.debug then
    M.log_level('debug')
  else
    M.log_level(M.config.log_level)
  end

  -- Save proxy and insecure settings
  curl.store_args({
    insecure = M.config.allow_insecure,
    proxy = M.config.proxy,
  })

  -- Load the providers
  client:stop()
  client:set_providers(function()
    return M.config.providers
  end)

  -- Initialize chat
  if M.chat then
    M.chat:close()
    M.chat:delete()
  else
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

          vim.schedule(function()
            select.highlight(M.chat:get_source().bufnr, not (M.config.highlight_selection and M.chat:focused()))
          end)
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
  end

  for name, prompt in pairs(prompts.list_prompts()) do
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
