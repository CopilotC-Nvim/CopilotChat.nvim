local constants = require('CopilotChat.constants')
local notify = require('CopilotChat.notify')
local utils = require('CopilotChat.utils')
local plenary_utils = require('plenary.async.util')

local EDITOR_VERSION = 'Neovim/' .. vim.version().major .. '.' .. vim.version().minor .. '.' .. vim.version().patch

local token_cache = nil
local unsaved_token_cache = {}
local function load_tokens()
  if token_cache then
    return token_cache
  end

  local config_path = vim.fs.normalize(vim.fn.stdpath('data') .. '/copilot_chat')
  local cache_file = config_path .. '/tokens.json'
  local file = utils.read_file(cache_file)
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

  local tokens = load_tokens()
  tokens[tag] = token
  local config_path = vim.fs.normalize(vim.fn.stdpath('data') .. '/copilot_chat')
  utils.write_file(config_path .. '/tokens.json', vim.json.encode(tokens))
  return token
end

--- Get the github token using device flow
---@return string
local function github_device_flow(tag, client_id, scope)
  local function request_device_code()
    local res = utils.curl_post('https://github.com/login/device/code', {
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
    while true do
      plenary_utils.sleep(interval * 1000)

      local res = utils.curl_post('https://github.com/login/oauth/access_token', {
        body = {
          client_id = client_id,
          device_code = device_code,
          grant_type = 'urn:ietf:params:oauth:grant-type:device_code',
        },
        headers = { ['Accept'] = 'application/json' },
      })
      local data = vim.json.decode(res.body)
      if data.access_token then
        return data.access_token
      elseif data.error ~= 'authorization_pending' then
        error('Auth error: ' .. (data.error or 'unknown'))
      end
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
      local file_data = utils.read_file(file_path)
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
---@field prepare_input nil|fun(inputs:table<CopilotChat.client.Message>, opts:CopilotChat.config.providers.Options):table
---@field prepare_output nil|fun(output:table, opts:CopilotChat.config.providers.Options):CopilotChat.config.providers.Output
---@field get_url nil|fun(opts:CopilotChat.config.providers.Options):string

---@type table<string, CopilotChat.config.providers.Provider>
local M = {}

M.copilot = {
  get_headers = function()
    local response, err = utils.curl_get('https://api.github.com/copilot_internal/v2/token', {
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

  get_info = function(headers)
    local response, err = utils.curl_get('https://api.github.com/copilot_internal/user', {
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
    local response, err = utils.curl_get('https://api.githubcopilot.com/models', {
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
        utils.curl_post('https://api.githubcopilot.com/models/' .. model.id .. '/policy', {
          headers = headers,
          json_request = true,
          body = { state = 'enabled' },
        })
      end
    end

    return models
  end,

  prepare_input = function(inputs, opts)
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
      out.top_p = 1
      out.temperature = opts.temperature
    end

    if opts.model.max_output_tokens then
      out.max_tokens = opts.model.max_output_tokens
    end

    return out
  end,

  prepare_output = function(output)
    local tool_calls = {}

    local choice
    if output.choices and #output.choices > 0 then
      for _, choice in ipairs(output.choices) do
        local message = choice.message or choice.delta
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

  get_url = function()
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
    local response, err = utils.curl_get('https://models.github.ai/catalog/models', {
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
