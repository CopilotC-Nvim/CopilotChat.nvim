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

local function encode_arguments(arguments)
  if arguments == nil then
    return ''
  end
  if type(arguments) == 'string' then
    return arguments
  end
  local ok, encoded = pcall(vim.json.encode, arguments)
  if ok then
    return encoded
  end
  return ''
end

local function push_tool_call(buffer, tool)
  if not tool or not tool.name then
    return
  end
  local index = #buffer + 1
  buffer[index] = {
    id = tool.id or ('tooluse_' .. index),
    index = tool.index or index,
    name = tool.name,
    arguments = encode_arguments(tool.arguments),
  }
end

local function summarize_response_output(response)
  local text_parts = {}
  local reasoning_parts = {}
  local tool_calls = {}

  local function handle_content(content)
    if type(content) ~= 'table' then
      return
    end
    local ctype = content.type
    if (ctype == 'output_text' or ctype == 'text') and type(content.text) == 'string' then
      table.insert(text_parts, content.text)
    elseif ctype == 'reasoning' and type(content.text) == 'string' then
      table.insert(reasoning_parts, content.text)
    elseif ctype == 'tool_use' or ctype == 'tool_call' then
      push_tool_call(tool_calls, content)
    end
  end

  if type(response.output) == 'table' then
    for _, item in ipairs(response.output) do
      if type(item) == 'table' then
        if type(item.content) == 'table' then
          for _, content in ipairs(item.content) do
            handle_content(content)
          end
        else
          handle_content(item)
        end
      end
    end
  end

  if type(response.required_action) == 'table' then
    local submit = response.required_action.submit_tool_outputs
    if submit and type(submit.tool_calls) == 'table' then
      for _, tool in ipairs(submit.tool_calls) do
        push_tool_call(tool_calls, tool)
      end
    end
  end

  local text = table.concat(text_parts, '')
  local reasoning = table.concat(reasoning_parts, '\n')

  if text == '' then
    text = nil
  end
  if reasoning == '' then
    reasoning = nil
  end
  if #tool_calls == 0 then
    tool_calls = nil
  end

  return {
    content = text,
    reasoning = reasoning,
    tool_calls = tool_calls,
  }
end

local function responses_finish_reason(response)
  local status = response and response.status or nil
  if status == 'completed' then
    return 'stop'
  elseif status == 'requires_action' then
    return 'tool_calls'
  elseif status == 'failed' or status == 'errored' or status == 'error' then
    return 'error'
  elseif status == 'canceled' or status == 'cancelled' then
    return 'canceled'
  end
  return nil
end

local function build_responses_body(inputs, opts)
  local instructions = {}
  local conversation = {}

  for _, message in ipairs(inputs) do
    local role = message.role or ''
    local content = vim.trim(message.content or '')
    if role == constants.ROLE.SYSTEM then
      if content ~= '' then
        table.insert(instructions, content)
      end
    else
      local label = role
      if role == constants.ROLE.TOOL then
        label = 'tool'
      end
      table.insert(conversation, string.format('%s:\n%s', label:upper(), content))
    end
  end

  local body = {
    model = opts.model.id,
    stream = opts.model.streaming or false,
  }

  if not utils.empty(instructions) then
    body.instructions = table.concat(instructions, '\n\n')
  end

  body.input = utils.empty(conversation) and '' or table.concat(conversation, '\n\n')

  if opts.tools and opts.model.tools then
    body.tools = vim.tbl_map(function(tool)
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

  if opts.model.max_output_tokens then
    body.max_output_tokens = opts.model.max_output_tokens
  end

  if opts.temperature ~= nil then
    body.temperature = opts.temperature
  end

  body.top_p = opts.top_p or 1

  return body
end

local function parse_responses_event(event)
  local event_type = event.type
  if not event_type then
    return {}
  end

  if event_type == 'response.error' then
    local message = ''
    if type(event.error) == 'table' and type(event.error.message) == 'string' then
      message = event.error.message
    elseif type(event.error) == 'string' then
      message = event.error
    end
    return {
      content = message,
      content_overwrite = message ~= '',
      finish_reason = 'error',
      skip_progress = true,
    }
  end

  if event_type == 'response.canceled' or event_type == 'response.cancelled' then
    return {
      finish_reason = 'canceled',
      skip_progress = true,
    }
  end

  if event_type == 'response.failed' then
    return {
      finish_reason = 'failed',
      skip_progress = true,
    }
  end

  local delta = event.delta
  if not delta and type(event.response) == 'table' then
    delta = event.response.delta
  end

  local function extract_delta_text(value)
    if not value then
      return ''
    end
    if type(value) == 'string' then
      return value
    end
    if type(value) ~= 'table' then
      return ''
    end

    local pieces = {}

    if type(value.text) == 'string' then
      table.insert(pieces, value.text)
    end

    if type(value.content) == 'table' then
      for _, entry in ipairs(value.content) do
        if type(entry) == 'table' and type(entry.text) == 'string' then
          table.insert(pieces, entry.text)
        end
      end
    end

    return table.concat(pieces, '')
  end

  local chunk = extract_delta_text(delta)
  if chunk ~= '' then
    if event_type:find('reasoning', 1, true) then
      return {
        reasoning = chunk,
      }
    else
      return {
        content = chunk,
      }
    end
  end

  if type(event.response) == 'table' then
    local summary = summarize_response_output(event.response)
    local finish_reason = responses_finish_reason(event.response)

    local result = {
      finish_reason = finish_reason,
      total_tokens = event.response.usage and event.response.usage.total_tokens or nil,
      tool_calls = summary.tool_calls,
      skip_progress = true,
    }

    if summary.content then
      result.content = summary.content
      result.content_overwrite = true
    end

    if summary.reasoning then
      result.reasoning = summary.reasoning
      result.reasoning_overwrite = true
    end

    return result
  end

  return {}
end

local function parse_responses_response(response)
  if type(response) ~= 'table' then
    return {}
  end
  local summary = summarize_response_output(response)
  local finish_reason = responses_finish_reason(response) or 'stop'

  return {
    content = summary.content or '',
    reasoning = summary.reasoning,
    tool_calls = summary.tool_calls,
    total_tokens = response.usage and response.usage.total_tokens or nil,
    finish_reason = finish_reason,
  }
end

---@class CopilotChat.config.providers.Options
---@field model CopilotChat.client.Model
---@field temperature number?
---@field tools table<CopilotChat.client.Tool>?
---@field use_responses_api boolean?
---@field top_p number?

---@class CopilotChat.config.providers.Output
---@field content string?
---@field reasoning string?
---@field finish_reason string?
---@field total_tokens number?
---@field tool_calls table<CopilotChat.client.ToolCall>?
---@field content_overwrite boolean?
---@field reasoning_overwrite boolean?
---@field skip_progress boolean?

---@class CopilotChat.config.providers.Provider
---@field disabled nil|boolean
---@field get_headers nil|fun():table<string, string>,number?
---@field get_info nil|fun(headers:table):string[]
---@field get_models nil|fun(headers:table):table<CopilotChat.client.Model>
---@field prepare_input nil|fun(inputs:table<CopilotChat.client.Message>, opts:CopilotChat.config.providers.Options):table
---@field prepare_output nil|fun(output:table, opts:CopilotChat.config.providers.Options):CopilotChat.config.providers.Output
---@field get_url nil|fun(opts:CopilotChat.config.providers.Options):string

---@type table<string, CopilotChat.config.providers.Provider>
local M = {}

M.copilot = {
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
          supported_endpoints = model.supported_endpoints,
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
    opts = opts or {}
    if opts.use_responses_api then
      return build_responses_body(inputs, opts)
    end

    local is_o1 = vim.startswith(opts.model.id, 'o1')

    inputs = vim.tbl_map(function(input)
      local output = {
        role = input.role,
        content = input.content,
      }

      if is_o1 then
        if input.role == constants.ROLE.SYSTEM then
          output.role = constants.ROLE.USER
        end
      end

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
      out.top_p = opts.top_p or 1
      out.temperature = opts.temperature
    end

    if opts.model.max_output_tokens then
      out.max_tokens = opts.model.max_output_tokens
    end

    return out
  end,

  prepare_output = function(output, opts)
    opts = opts or {}
    if opts.use_responses_api then
      if output.type then
        return parse_responses_event(output)
      end
      return parse_responses_response(output)
    end

    local tool_calls = {}

    local choice
    if output.choices and #output.choices > 0 then
      for _, choice_entry in ipairs(output.choices) do
        local message = choice_entry.message or choice_entry.delta
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
    local usage = choice.usage and choice.usage.total_tokens
    if not usage then
      usage = output.usage and output.usage.total_tokens
    end
    local finish_reason = choice.finish_reason or choice.done_reason or output.finish_reason or output.done_reason

    return {
      content = content,
      reasoning = reasoning,
      finish_reason = finish_reason,
      total_tokens = usage,
      tool_calls = tool_calls,
    }
  end,

  get_url = function(opts)
    if opts and opts.use_responses_api then
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
        local max_output_tokens = model.limits.max_output_tokens
        local max_input_tokens = model.limits.max_input_tokens
        return {
          id = model.id,
          name = model.name,
          tokenizer = 'o200k_base',
          max_input_tokens = max_input_tokens,
          max_output_tokens = max_output_tokens,
          streaming = vim.tbl_contains(model.capabilities, 'streaming'),
          tools = vim.tbl_contains(model.capabilities, 'tool-calling'),
          reasoning = vim.tbl_contains(model.capabilities, 'reasoning'),
          version = model.version,
          supported_endpoints = model.supported_endpoints,
        }
      end)
      :totable()
  end,

  prepare_input = M.copilot.prepare_input,
  prepare_output = M.copilot.prepare_output,

  get_url = function(opts)
    if opts and opts.use_responses_api then
      return 'https://models.github.ai/inference/responses'
    end
    return 'https://models.github.ai/inference/chat/completions'
  end,
}

return M
