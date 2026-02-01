local log = require('plenary.log')
local plenary_utils = require('plenary.async.util')
local constants = require('CopilotChat.constants')
local notify = require('CopilotChat.notify')
local utils = require('CopilotChat.utils')
local curl = require('CopilotChat.utils.curl')
local files = require('CopilotChat.utils.files')

local EDITOR_VERSION = 'Neovim/' .. vim.version().major .. '.' .. vim.version().minor .. '.' .. vim.version().patch

local token_cache = nil
local unsaved_token_cache = {}
local function load_tokens()
  if token_cache then
    return token_cache
  end

  local config_path = vim.fs.normalize(vim.fn.stdpath('data') .. '/copilot_chat')
  local cache_file = config_path .. '/tokens.json'
  local file = files.read_file(cache_file)
  if file then
    token_cache = vim.json.decode(file)
  else
    token_cache = {}
  end

  return token_cache
end

local function get_token(tag)
  if unsaved_token_cache[tag] then
    return unsaved_token_cache[tag]
  end

  local tokens = load_tokens()
  return tokens[tag]
end

local function set_token(tag, token, save)
  if not save then
    unsaved_token_cache[tag] = token
    return token
  end

  utils.schedule_main()
  local tokens = load_tokens()
  tokens[tag] = token
  local config_path = vim.fs.normalize(vim.fn.stdpath('data') .. '/copilot_chat')
  local file_path = config_path .. '/tokens.json'
  vim.fn.mkdir(vim.fn.fnamemodify(file_path, ':p:h'), 'p')
  files.write_file(file_path, vim.json.encode(tokens))
  log.info('Token for ' .. tag .. ' saved to ' .. file_path)
  return token
end

--- Get the github token using device flow
---@return string
local function github_device_flow(tag, client_id, scope)
  local function request_device_code()
    local res = curl.post('https://github.com/login/device/code', {
      body = {
        client_id = client_id,
        scope = scope,
      },
      headers = { ['Accept'] = 'application/json' },
    })

    local data = vim.json.decode(res.body)
    return data
  end

  local function poll_for_token(device_code, interval)
    plenary_utils.sleep(interval * 1000)

    local res = curl.post('https://github.com/login/oauth/access_token', {
      json_response = true,
      body = {
        client_id = client_id,
        device_code = device_code,
        grant_type = 'urn:ietf:params:oauth:grant-type:device_code',
      },
      headers = { ['Accept'] = 'application/json' },
    })

    local data = res.body
    if data.access_token then
      return data.access_token
    elseif data.error ~= 'authorization_pending' then
      error('Auth error: ' .. (data.error or 'unknown'))
    else
      return poll_for_token(device_code, interval)
    end
  end

  local token = get_token(tag)
  if token then
    return token
  end

  local code_data = request_device_code()
  notify.publish(
    notify.MESSAGE,
    '[' .. tag .. '] Visit ' .. code_data.verification_uri .. ' and enter code: ' .. code_data.user_code
  )
  notify.publish(notify.STATUS, '[' .. tag .. '] Waiting for authorization...')
  token = poll_for_token(code_data.device_code, code_data.interval)
  notify.publish(notify.MESSAGE, '')
  notify.publish(notify.STATUS, '')
  return set_token(tag, token, true)
end

--- Get the github copilot oauth cached token (gu_ token)
---@return string
local function get_github_copilot_token(tag)
  local function config_path()
    local config = vim.fs.normalize('$XDG_CONFIG_HOME')
    if config and vim.uv.fs_stat(config) then
      return config
    end
    if vim.fn.has('win32') > 0 then
      config = vim.fs.normalize('$LOCALAPPDATA')
      if not config or not vim.uv.fs_stat(config) then
        config = vim.fs.normalize('$HOME/AppData/Local')
      end
    else
      config = vim.fs.normalize('$HOME/.config')
    end
    if config and vim.uv.fs_stat(config) then
      return config
    end
  end

  local token = get_token(tag)
  if token then
    return token
  end

  -- loading token from the environment only in GitHub Codespaces
  local codespaces = os.getenv('CODESPACES')
  token = os.getenv('GITHUB_TOKEN')
  if token and codespaces then
    return set_token(tag, token, false)
  end

  -- loading token from the file
  local config_path = config_path()
  if config_path then
    -- token can be sometimes in apps.json sometimes in hosts.json
    local file_paths = {
      config_path .. '/github-copilot/hosts.json',
      config_path .. '/github-copilot/apps.json',
    }

    for _, file_path in ipairs(file_paths) do
      local file_data = files.read_file(file_path)
      if file_data then
        local parsed_data = utils.json_decode(file_data)
        if parsed_data then
          for key, value in pairs(parsed_data) do
            if string.find(key, 'github.com') and value and value.oauth_token then
              return set_token(tag, value.oauth_token, false)
            end
          end
        end
      end
    end
  end

  return github_device_flow(tag, 'Iv1.b507a08c87ecfe98', '')
end

local function get_github_models_token(tag)
  local token = get_token(tag)
  if token then
    return token
  end

  -- loading token from the environment only in GitHub Codespaces
  local codespaces = os.getenv('CODESPACES')
  token = os.getenv('GITHUB_TOKEN')
  if token and codespaces then
    return set_token(tag, token, false)
  end

  -- loading token from gh cli if available
  if vim.fn.executable('gh') == 0 then
    local result = utils.system({ 'gh', 'auth', 'token', '-h', 'github.com' })
    if result and result.code == 0 and result.stdout then
      local gh_token = vim.trim(result.stdout)
      if gh_token ~= '' and not gh_token:find('no oauth token') then
        return set_token(tag, gh_token, false)
      end
    end
  end

  return github_device_flow(tag, '178c6fc778ccc68e1d6a', 'read:user copilot')
end

--- Prepare input for Responses API
---@param inputs table<CopilotChat.client.Message>
---@param opts CopilotChat.config.providers.Options
---@return table
local function prepare_responses_input(inputs, opts)
  local instructions = nil
  local input_messages = {}

  for _, msg in ipairs(inputs) do
    if msg.role == constants.ROLE.SYSTEM then
      instructions = instructions and (instructions .. '\n\n' .. msg.content) or msg.content
    elseif msg.role == constants.ROLE.TOOL then
      table.insert(input_messages, {
        type = 'function_call_output',
        call_id = msg.tool_call_id,
        output = msg.content,
      })
    else
      table.insert(input_messages, {
        role = msg.role,
        content = msg.content,
      })

      if msg.tool_calls then
        for _, tool_call in ipairs(msg.tool_calls) do
          table.insert(input_messages, {
            type = 'function_call',
            call_id = tool_call.id,
            name = tool_call.name,
            arguments = tool_call.arguments or '',
          })
        end
      end
    end
  end

  local out = {
    model = opts.model.id,
    stream = opts.model.streaming ~= false,
    input = input_messages,
  }

  if instructions then
    out.instructions = instructions
  end

  if opts.tools and opts.model.tools then
    out.tools = vim.tbl_map(function(tool)
      return {
        type = 'function',
        name = tool.name,
        description = tool.description,
        parameters = tool.schema,
      }
    end, opts.tools)
  end

  return out
end

--- Prepare input for Chat Completions API
---@param inputs table<CopilotChat.client.Message>
---@param opts CopilotChat.config.providers.Options
---@return table
local function prepare_chat_input(inputs, opts)
  local is_o1 = vim.startswith(opts.model.id, 'o1')

  inputs = vim.tbl_map(function(input)
    local output = {
      role = (is_o1 and input.role == constants.ROLE.SYSTEM) and constants.ROLE.USER or input.role,
      content = input.content,
    }

    if input.tool_call_id then
      output.tool_call_id = input.tool_call_id
    end

    if input.tool_calls then
      output.tool_calls = vim.tbl_map(function(tool_call)
        return {
          id = tool_call.id,
          type = 'function',
          ['function'] = {
            name = tool_call.name,
            arguments = tool_call.arguments or nil,
          },
        }
      end, input.tool_calls)
    end

    return output
  end, inputs)

  local out = {
    messages = inputs,
    model = opts.model.id,
    stream = opts.model.streaming or false,
  }

  if opts.tools and opts.model.tools then
    out.tools = vim.tbl_map(function(tool)
      return {
        type = 'function',
        ['function'] = {
          name = tool.name,
          description = tool.description,
          parameters = tool.schema,
        },
      }
    end, opts.tools)
  end

  if not is_o1 then
    out.n = 1
    out.top_p = 1
    out.temperature = opts.temperature
  end

  if opts.model.max_output_tokens then
    out.max_tokens = opts.model.max_output_tokens
  end

  return out
end
---@param parts table Array of content parts
---@return string The concatenated text content
local function extract_text_from_parts(parts)
  if not parts or type(parts) ~= 'table' then
    return ''
  end

  local content = ''
  for _, part in ipairs(parts) do
    if type(part) == 'string' then
      content = content .. part
    elseif type(part) == 'table' then
      -- Responses API: parts have type field
      if part.type == 'text' or part.type == 'output_text' or part.type == 'input_text' then
        content = content .. (part.text or '')
      -- Fallback for simpler structures
      elseif part.text then
        content = content .. part.text
      end
    end
  end
  return content
end

--- Parse Responses API output (both streaming and non-streaming)
---@param output table Raw API response
---@return CopilotChat.config.providers.Output
local function prepare_responses_output(output)
  local content = ''
  local reasoning = ''
  local finish_reason = nil
  local total_tokens = nil
  local tool_calls = {}

  -- Handle errors
  local error_msg = output.error or (output.response and output.response.error)
  if error_msg then
    if type(error_msg) == 'table' then
      error_msg = error_msg.message or vim.inspect(error_msg)
    end
    return {
      content = '',
      reasoning = '',
      finish_reason = 'error: ' .. tostring(error_msg),
      total_tokens = nil,
      tool_calls = {},
    }
  end

  -- Handle streaming events
  if output.type then
    if output.type == 'response.output_text.delta' then
      -- Streaming text delta
      if output.delta and type(output.delta) == 'string' then
        content = output.delta
      elseif output.delta and output.delta.text then
        content = output.delta.text
      end
    elseif output.type == 'response.output_item.done' then
      -- Complete output item (including tool calls)
      local item = output.item
      if item and item.type == 'function_call' then
        table.insert(tool_calls, {
          id = item.call_id or ('tooluse_' .. (#tool_calls + 1)),
          index = #tool_calls + 1,
          name = item.name or '',
          arguments = item.arguments or '',
        })
      end
    elseif output.type == 'response.completed' or output.type == 'response.done' then
      local response = output.response
      if response then
        if response.reasoning and response.reasoning.summary then
          reasoning = response.reasoning.summary
        end
        if response.usage then
          total_tokens = response.usage.total_tokens
        end
        finish_reason = 'stop'
      end
    elseif output.type == 'response.failed' then
      finish_reason = 'error: ' .. (output.error and output.error.message or 'unknown error')
    end
  -- Handle non-streaming response
  elseif output.response then
    local response = output.response
    if response.output and #response.output > 0 then
      for _, msg in ipairs(response.output) do
        if msg.content then
          content = content .. extract_text_from_parts(msg.content)
        end
        if msg.tool_calls then
          for i, tool_call in ipairs(msg.tool_calls) do
            table.insert(tool_calls, {
              id = tool_call.call_id or ('tooluse_' .. i),
              index = i,
              name = tool_call.name or '',
              arguments = tool_call.arguments or '',
            })
          end
        end
      end
    end
    if response.reasoning and response.reasoning.summary then
      reasoning = response.reasoning.summary
    end
    if response.usage then
      total_tokens = response.usage.total_tokens
    end
    finish_reason = response.status == 'completed' and 'stop' or nil
  end

  return {
    content = content,
    reasoning = reasoning,
    finish_reason = finish_reason,
    total_tokens = total_tokens,
    tool_calls = tool_calls,
  }
end

--- Parse Chat Completions API output (both streaming and non-streaming)
---@param output table Raw API response
---@return CopilotChat.config.providers.Output
local function prepare_chat_output(output)
  local tool_calls = {}

  local choice
  if output.choices and #output.choices > 0 then
    for _, c in ipairs(output.choices) do
      local message = c.message or c.delta
      if message and message.tool_calls then
        for i, tool_call in ipairs(message.tool_calls) do
          local fn = tool_call['function']
          if fn then
            local index = tool_call.index or i
            local id = utils.empty(tool_call.id) and ('tooluse_' .. index) or tool_call.id
            table.insert(tool_calls, {
              id = id,
              index = index,
              name = fn.name,
              arguments = fn.arguments or '',
            })
          end
        end
      end
    end
    choice = output.choices[1]
  else
    choice = output
  end

  local message = choice.message or choice.delta
  local content = message and message.content
  local reasoning = message and (message.reasoning or message.reasoning_content)
  local usage = choice.usage and choice.usage.total_tokens or output.usage and output.usage.total_tokens
  local finish_reason = choice.finish_reason or choice.done_reason or output.finish_reason or output.done_reason

  return {
    content = content,
    reasoning = reasoning,
    finish_reason = finish_reason,
    total_tokens = usage,
    tool_calls = tool_calls,
  }
end

---@class CopilotChat.config.providers.Options
---@field model CopilotChat.client.Model
---@field temperature number?
---@field tools table<CopilotChat.client.Tool>?

---@class CopilotChat.config.providers.Output
---@field content string
---@field reasoning string?
---@field finish_reason string?
---@field total_tokens number?
---@field tool_calls table<CopilotChat.client.ToolCall>

---@class CopilotChat.config.providers.Provider
---@field disabled nil|boolean
---@field get_headers nil|fun():table<string, string>,number?
---@field get_info nil|fun(headers:table):string[]
---@field get_models nil|fun(headers:table):table<CopilotChat.client.Model>
---@field select_model nil|fun(headers:table, hints:table?):string?,string?
---@field prepare_input nil|fun(inputs:table<CopilotChat.client.Message>, opts:CopilotChat.config.providers.Options):table
---@field prepare_output nil|fun(output:table, opts:CopilotChat.config.providers.Options):CopilotChat.config.providers.Output
---@field get_url nil|fun(opts:CopilotChat.config.providers.Options):string

---@type table<string, CopilotChat.config.providers.Provider>
local M = {}

M.copilot = {
  route_model = function(headers, hints)
    hints = hints or { 'auto' }
    local token = headers['Authorization'] and headers['Authorization']:gsub('^Bearer%s+', '')
    if not token then
      return nil, 'No authorization token available'
    end

    local url = 'https://api.individual.githubcopilot.com/models/session'
    local response, err = curl.post(url, {
      headers = {
        ['Authorization'] = 'Bearer ' .. token,
        ['editor-version'] = 'vscode/1.109.0-insider',
        ['user-agent'] = 'GitHubCopilotChat/0.38.0',
        ['x-github-api-version'] = '2025-10-01',
      },
      body = { auto_mode = { model_hints = hints } },
      json_response = true,
      json_request = true,
    })

    if err then
      return nil, 'Auto selection request failed: ' .. tostring(err)
    end

    if not response or response.status ~= 200 then
      return nil, 'Auto selection returned status: ' .. tostring(response and response.status or 'unknown')
    end

    if not response.body or not response.body.selected_model then
      return nil, 'No model selected in response'
    end

    return response.body.selected_model, nil
  end,
  get_headers = function()
    local response, err = curl.get('https://api.github.com/copilot_internal/v2/token', {
      json_response = true,
      headers = {
        ['Authorization'] = 'Token ' .. get_github_copilot_token('github_copilot'),
      },
    })

    if err then
      error(err)
    end

    return {
      ['Authorization'] = 'Bearer ' .. response.body.token,
      ['Editor-Version'] = EDITOR_VERSION,
      ['Editor-Plugin-Version'] = 'CopilotChat.nvim/*',
      ['Copilot-Integration-Id'] = 'vscode-chat',
    },
      response.body.expires_at
  end,

  get_info = function()
    local response, err = curl.get('https://api.github.com/copilot_internal/user', {
      json_response = true,
      headers = {
        ['Authorization'] = 'Token ' .. get_github_copilot_token('github_copilot'),
      },
    })

    if err then
      error(err)
    end

    local stats = response.body
    local lines = {}

    if not stats or not stats.quota_snapshots then
      return { 'No Copilot stats available.' }
    end

    local function usage_line(name, snap)
      if not snap then
        return
      end

      table.insert(lines, string.format('  **%s**', name))

      if snap.unlimited then
        table.insert(lines, '    Usage: Unlimited')
      else
        local used = snap.entitlement - snap.remaining
        local percent = snap.entitlement > 0 and (used / snap.entitlement * 100) or 0
        table.insert(lines, string.format('   Usage: %d / %d (%.1f%%)', used, snap.entitlement, percent))
        table.insert(lines, string.format('   Remaining: %d', snap.remaining))
        if snap.overage_permitted ~= nil then
          table.insert(lines, '   Overage: ' .. (snap.overage_permitted and 'Permitted' or 'Not Permitted'))
        end
      end
    end

    usage_line('Premium requests', stats.quota_snapshots.premium_interactions)
    usage_line('Chat', stats.quota_snapshots.chat)
    usage_line('Completions', stats.quota_snapshots.completions)

    if stats.quota_reset_date then
      table.insert(lines, string.format(' **Quota** resets on: %s', stats.quota_reset_date))
    end

    return lines
  end,

  get_models = function(headers)
    local response, err = curl.get('https://api.githubcopilot.com/models', {
      json_response = true,
      headers = headers,
    })

    if err then
      error(err)
    end

    local models = vim
      .iter(response.body.data)
      :filter(function(model)
        return model.capabilities.type == 'chat' and model.model_picker_enabled
      end)
      :map(function(model)
        local supported_endpoints = model.supported_endpoints or {}
        -- Pre-compute whether this model uses the Responses API
        local use_responses = vim.tbl_contains(supported_endpoints, '/responses')

        return {
          id = model.id,
          name = model.name,
          tokenizer = model.capabilities.tokenizer,
          max_input_tokens = model.capabilities.limits.max_prompt_tokens,
          max_output_tokens = model.capabilities.limits.max_output_tokens,
          streaming = model.capabilities.supports.streaming,
          tools = model.capabilities.supports.tool_calls,
          policy = not model['policy'] or model['policy']['state'] == 'enabled',
          version = model.version,
          use_responses = use_responses,
        }
      end)
      :totable()

    local name_map = {}
    for _, model in ipairs(models) do
      if not name_map[model.name] or model.version > name_map[model.name].version then
        name_map[model.name] = model
      end
    end

    models = vim.tbl_values(name_map)

    for _, model in ipairs(models) do
      if not model.policy then
        pcall(curl.post, 'https://api.githubcopilot.com/models/' .. model.id .. '/policy', {
          headers = headers,
          json_request = true,
          body = { state = 'enabled' },
        })
      end
    end

    return models
  end,

  prepare_input = function(inputs, opts)
    local request
    if opts.model.use_responses then
      request = prepare_responses_input(inputs, opts)
    else
      request = prepare_chat_input(inputs, opts)
    end

    if inputs and #inputs > 0 then
      local last_msg = inputs[#inputs]
      if last_msg.role == constants.ROLE.TOOL then
        return request, { ['x-initiator'] = 'agent' }
      end
    end

    return request
  end,

  prepare_output = function(output, opts)
    if opts and opts.model and opts.model.use_responses then
      return prepare_responses_output(output)
    end
    return prepare_chat_output(output)
  end,

  get_url = function(opts)
    if opts and opts.model and opts.model.use_responses then
      return 'https://api.githubcopilot.com/responses'
    end
    return 'https://api.githubcopilot.com/chat/completions'
  end,
}

M.github_models = {
  disabled = true,

  get_headers = function()
    return {
      ['Authorization'] = 'Bearer ' .. get_github_models_token('github_models'),
    }
  end,

  get_models = function(headers)
    local response, err = curl.get('https://models.github.ai/catalog/models', {
      json_response = true,
      headers = headers,
    })

    if err then
      error(err)
    end

    return vim
      .iter(response.body)
      :map(function(model)
        return {
          id = model.id,
          name = model.name,
          tokenizer = 'o200k_base', -- GitHub Models doesn't expose tokenizer info
          max_input_tokens = model.limits and model.limits.max_input_tokens,
          max_output_tokens = model.limits and model.limits.max_output_tokens,
          streaming = model.capabilities and vim.tbl_contains(model.capabilities, 'streaming') or false,
          tools = model.capabilities and vim.tbl_contains(model.capabilities, 'tool-calling') or false,
          reasoning = model.capabilities and vim.tbl_contains(model.capabilities, 'reasoning') or false,
          version = model.version,
        }
      end)
      :totable()
  end,

  prepare_input = M.copilot.prepare_input,
  prepare_output = M.copilot.prepare_output,

  get_url = function()
    return 'https://models.github.ai/inference/chat/completions'
  end,
}

return M
