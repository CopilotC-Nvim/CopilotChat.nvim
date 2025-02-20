local async = require('plenary.async')
local utils = require('CopilotChat.utils')

---@class CopilotChat.Provider.model
---@field id string
---@field name string
---@field version string?
---@field tokenizer string?
---@field max_input_tokens number?
---@field max_output_tokens number?

---@class CopilotChat.Provider.agent
---@field id string
---@field name string
---@field description string?

---@class CopilotChat.Provider.embed
---@field index number
---@field embedding table<number>

---@class CopilotChat.Provider.options
---@field model CopilotChat.Provider.model
---@field agent CopilotChat.Provider.agent?
---@field temperature number?

---@class CopilotChat.Provider.input
---@field role string
---@field content string

---@class CopilotChat.Provider.reference
---@field name string
---@field url string

---@class CopilotChat.Provider.output
---@field content string
---@field finish_reason string?
---@field total_tokens number?
---@field references table<CopilotChat.Provider.reference>?

---@class CopilotChat.Provider
---@field disabled nil|boolean
---@field get_headers fun(token:string):table<string, string>
---@field get_token nil|fun():string,number?
---@field get_agents nil|fun(headers:table):table<CopilotChat.Provider.agent>
---@field get_models nil|fun(headers:table):table<CopilotChat.Provider.model>
---@field embed nil|string|fun(inputs:table<string>, headers:table):table<CopilotChat.Provider.embed>
---@field prepare_input nil|fun(inputs:table<CopilotChat.Provider.input>, opts:CopilotChat.Provider.options):table
---@field prepare_output nil|fun(output:table, opts:CopilotChat.Provider.options):CopilotChat.Provider.output
---@field get_url nil|fun(opts:CopilotChat.Provider.options):string

local EDITOR_VERSION = 'Neovim/'
  .. vim.version().major
  .. '.'
  .. vim.version().minor
  .. '.'
  .. vim.version().patch

local cached_github_token = nil

--- Get the github copilot oauth cached token (gu_ token)
---@return string
local function get_github_token()
  if cached_github_token then
    return cached_github_token
  end

  async.util.scheduler()

  -- loading token from the environment only in GitHub Codespaces
  local token = os.getenv('GITHUB_TOKEN')
  local codespaces = os.getenv('CODESPACES')
  if token and codespaces then
    cached_github_token = token
    return token
  end

  -- loading token from the file
  local config_path = utils.config_path()
  if not config_path then
    error('Failed to find config path for GitHub token')
  end

  -- token can be sometimes in apps.json sometimes in hosts.json
  local file_paths = {
    config_path .. '/github-copilot/hosts.json',
    config_path .. '/github-copilot/apps.json',
  }

  for _, file_path in ipairs(file_paths) do
    if vim.fn.filereadable(file_path) == 1 then
      local userdata = vim.fn.json_decode(vim.fn.readfile(file_path))
      for key, value in pairs(userdata) do
        if string.find(key, 'github.com') then
          cached_github_token = value.oauth_token
          return value.oauth_token
        end
      end
    end
  end

  error('Failed to find GitHub token')
end

---@type table<string, CopilotChat.Provider>
local M = {}

M.copilot = {
  embed = 'copilot_embeddings',

  get_headers = function(token)
    return {
      ['authorization'] = 'Bearer ' .. token,
      ['editor-version'] = EDITOR_VERSION,
      ['editor-plugin-version'] = 'CopilotChat.nvim/*',
      ['copilot-integration-id'] = 'vscode-chat',
      ['content-type'] = 'application/json',
    }
  end,

  get_token = function()
    local response, err = utils.curl_get('https://api.github.com/copilot_internal/v2/token', {
      headers = {
        ['Authorization'] = 'Token ' .. get_github_token(),
        ['Accept'] = 'application/json',
      },
    })

    if err then
      error(err)
    end

    if response.status ~= 200 then
      error('Failed to authenticate: ' .. tostring(response.status))
    end

    local body = vim.json.decode(response.body)
    return body.token, body.expires_at
  end,

  get_agents = function(headers)
    local response, err = utils.curl_get('https://api.githubcopilot.com/agents', {
      headers = headers,
    })

    if err then
      error(err)
    end

    if response.status ~= 200 then
      error('Failed to fetch agents: ' .. tostring(response.status))
    end

    local agents = vim.json.decode(response.body)['agents']
    local out = {}
    for _, agent in ipairs(agents) do
      table.insert(out, {
        id = agent.slug,
        name = agent.name,
        description = agent.description,
      })
    end

    return out
  end,

  get_models = function(headers)
    local response, err = utils.curl_get('https://api.githubcopilot.com/models', {
      headers = headers,
    })

    if err then
      error(err)
    end

    if response.status ~= 200 then
      error('Failed to fetch models: ' .. tostring(response.status))
    end

    local models = {}
    for _, model in ipairs(vim.json.decode(response.body).data) do
      if model['capabilities']['type'] == 'chat' then
        table.insert(models, {
          id = model.id,
          name = model.name,
          version = model.version,
          tokenizer = model.capabilities.tokenizer,
          max_input_tokens = model.capabilities.limits.max_prompt_tokens,
          max_output_tokens = model.capabilities.limits.max_output_tokens,
          policy = not model['policy'] or model['policy']['state'] == 'enabled',
        })
      end
    end

    for _, model in ipairs(models) do
      if not model.policy then
        utils.curl_post('https://api.githubcopilot.com/models/' .. model.id .. '/policy', {
          headers = headers,
          body = vim.json.encode({ state = 'enabled' }),
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
      stream = not is_o1,
      n = 1,
    }

    if not is_o1 then
      out.temperature = opts.temperature
      out.top_p = 1
    end

    if opts.model.max_output_tokens then
      out.max_tokens = opts.model.max_output_tokens
    end

    return out
  end,

  prepare_output = function(output)
    local references = {}

    if output.copilot_references then
      for _, reference in ipairs(output.copilot_references) do
        local metadata = reference.metadata
        if metadata and metadata.display_name and metadata.display_url then
          table.insert(references, {
            name = metadata.display_name,
            url = metadata.display_url,
          })
        end
      end
    end

    local message
    if output.choices and #output.choices > 0 then
      message = output.choices[1]
    else
      message = output
    end

    local content = message.message and message.message.content
      or message.delta and message.delta.content

    return {
      content = content,
      finish_reason = message.finish_reason or message.done_reason,
      total_tokens = message.usage and message.usage.total_tokens,
      references = references,
    }
  end,

  get_url = function(opts)
    if opts.agent then
      return 'https://api.githubcopilot.com/agents/' .. opts.agent.id .. '?chat'
    end

    return 'https://api.githubcopilot.com/chat/completions'
  end,
}

M.github_models = {
  embed = 'copilot_embeddings',

  get_headers = function(token)
    return {
      ['Authorization'] = 'Bearer ' .. token,
      ['Content-Type'] = 'application/json',
      ['x-ms-useragent'] = EDITOR_VERSION,
      ['x-ms-user-agent'] = EDITOR_VERSION,
    }
  end,

  get_token = function()
    return get_github_token(), nil
  end,

  get_models = function(headers)
    local response = utils.curl_post('https://api.catalog.azureml.ms/asset-gallery/v1.0/models', {
      headers = headers,
      body = [[
        {
          "filters": [
            { "field": "freePlayground", "values": ["true"], "operator": "eq"},
            { "field": "labels", "values": ["latest"], "operator": "eq"}
          ],
          "order": [
            { "field": "displayName", "direction": "asc" }
          ]
        }
      ]],
    })

    if not response or response.status ~= 200 then
      error('Failed to fetch models: ' .. tostring(response and response.status))
    end

    local models = {}
    for _, model in ipairs(vim.json.decode(response.body)['summaries']) do
      if vim.tbl_contains(model.inferenceTasks, 'chat-completion') then
        table.insert(models, {
          id = model.name,
          name = model.displayName,
          version = model.name .. '-' .. model.version,
          tokenizer = 'o200k_base',
          max_input_tokens = model.modelLimits.textLimits.inputContextWindow,
          max_output_tokens = model.modelLimits.textLimits.maxOutputTokens,
        })
      end
    end

    return models
  end,

  prepare_input = M.copilot.prepare_input,
  prepare_output = M.copilot.prepare_output,

  get_url = function()
    return 'https://models.inference.ai.azure.com/chat/completions'
  end,
}

M.copilot_embeddings = {
  get_headers = M.copilot.get_headers,
  get_token = M.copilot.get_token,

  embed = function(inputs, headers)
    local response = utils.curl_post('https://api.githubcopilot.com/embeddings', {
      headers = headers,
      body = utils.temp_file(vim.json.encode({
        dimensions = 512,
        input = inputs,
        model = 'text-embedding-3-small',
      })),
    })

    if not response or response.status ~= 200 then
      error('Failed to embed text: ' .. tostring(response and response.status))
    end

    return vim.json.decode(response.body).data
  end,
}

return M
