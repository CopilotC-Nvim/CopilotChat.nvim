local utils = require('CopilotChat.utils')

local EDITOR_VERSION = 'Neovim/' .. vim.version().major .. '.' .. vim.version().minor .. '.' .. vim.version().patch

local cached_github_token = nil

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

--- Get the github copilot oauth cached token (gu_ token)
---@return string
local function get_github_token()
  if cached_github_token then
    return cached_github_token
  end

  -- loading token from the environment only in GitHub Codespaces
  local token = os.getenv('GITHUB_TOKEN')
  local codespaces = os.getenv('CODESPACES')
  if token and codespaces then
    cached_github_token = token
    return token
  end

  -- loading token from the file
  local config_path = config_path()
  if not config_path then
    error('Failed to find config path for GitHub token')
  end

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
          if string.find(key, 'github.com') then
            cached_github_token = value.oauth_token
            return value.oauth_token
          end
        end
      end
    end
  end

  error('Failed to find GitHub token')
end

---@class CopilotChat.config.providers.Options
---@field model CopilotChat.client.Model
---@field temperature number?
---@field tools table<CopilotChat.client.Tool>?

---@class CopilotChat.config.providers.Output
---@field content string
---@field finish_reason string?
---@field total_tokens number?
---@field tool_calls table<CopilotChat.client.ToolCall>

---@class CopilotChat.config.providers.Provider
---@field disabled nil|boolean
---@field get_headers nil|fun():table<string, string>,number?
---@field get_models nil|fun(headers:table):table<CopilotChat.client.Model>
---@field embed nil|string|fun(inputs:table<string>, headers:table):table<CopilotChat.client.Embed>
---@field prepare_input nil|fun(inputs:table<CopilotChat.client.Message>, opts:CopilotChat.config.providers.Options):table
---@field prepare_output nil|fun(output:table, opts:CopilotChat.config.providers.Options):CopilotChat.config.providers.Output
---@field get_url nil|fun(opts:CopilotChat.config.providers.Options):string

---@type table<string, CopilotChat.config.providers.Provider>
local M = {}

M.copilot = {
  embed = 'copilot_embeddings',

  get_headers = function()
    local response, err = utils.curl_get('https://api.github.com/copilot_internal/v2/token', {
      json_response = true,
      headers = {
        ['Authorization'] = 'Token ' .. get_github_token(),
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
      if is_o1 then
        if input.role == 'system' then
          input.role = 'user'
        end
      end

      return input
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
    local usage = choice.usage and choice.usage.total_tokens
    if not usage then
      usage = output.usage and output.usage.total_tokens
    end
    local finish_reason = choice.finish_reason or choice.done_reason or output.finish_reason or output.done_reason

    return {
      content = content,
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
  embed = 'copilot_embeddings',

  get_headers = function()
    return {
      ['Authorization'] = 'Bearer ' .. get_github_token(),
      ['x-ms-useragent'] = EDITOR_VERSION,
      ['x-ms-user-agent'] = EDITOR_VERSION,
    }
  end,

  get_models = function(headers)
    local response, err = utils.curl_post('https://api.catalog.azureml.ms/asset-gallery/v1.0/models', {
      headers = headers,
      json_request = true,
      json_response = true,
      body = {
        filters = {
          { field = 'freePlayground', values = { 'true' }, operator = 'eq' },
          { field = 'labels', values = { 'latest' }, operator = 'eq' },
        },
        order = {
          { field = 'displayName', direction = 'asc' },
        },
      },
    })

    if err then
      error(err)
    end

    return vim
      .iter(response.body.summaries)
      :filter(function(model)
        return vim.tbl_contains(model.inferenceTasks, 'chat-completion')
      end)
      :map(function(model)
        local context_window = model.modelLimits.textLimits.inputContextWindow
        local max_output_tokens = model.modelLimits.textLimits.maxOutputTokens
        local max_input_tokens = context_window - max_output_tokens
        if max_input_tokens <= 0 then
          max_output_tokens = 4096
          max_input_tokens = context_window - max_output_tokens
        end

        return {
          id = model.name,
          name = model.displayName,
          tokenizer = 'o200k_base',
          max_input_tokens = max_input_tokens,
          max_output_tokens = max_output_tokens,
          streaming = true,
        }
      end)
      :totable()
  end,

  prepare_input = M.copilot.prepare_input,
  prepare_output = M.copilot.prepare_output,

  get_url = function()
    return 'https://models.inference.ai.azure.com/chat/completions'
  end,
}

M.copilot_embeddings = {
  get_headers = M.copilot.get_headers,

  embed = function(inputs, headers)
    local response, err = utils.curl_post('https://api.githubcopilot.com/embeddings', {
      headers = headers,
      json_request = true,
      json_response = true,
      body = {
        dimensions = 512,
        input = inputs,
        model = 'text-embedding-3-small',
      },
    })

    if err then
      error(err)
    end

    return response.body.data
  end,
}

return M
