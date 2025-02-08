local utils = require('CopilotChat.utils')

---@class CopilotChat.Provider
---@field get_headers nil|fun(token:string, sessionid:string, machineid:string):table
---@field get_token nil|fun():string,number?
---@field get_agents nil|fun(headers:table):table
---@field get_models fun(headers:table):table
---@field prepare_model nil|fun(model:table, opts:table, headers:table)
---@field prepare_embeddings nil|fun(inputs:table, opts:table, headers:table):table
---@field prepare_chat fun(messages:table, opts:table, headers:table):table
---@field get_embeddings_url nil|fun(opts:table):string
---@field get_chat_url fun(opts:table):string

local VERSION_HEADERS = {
  ['editor-version'] = 'Neovim/'
    .. vim.version().major
    .. '.'
    .. vim.version().minor
    .. '.'
    .. vim.version().patch,
  ['editor-plugin-version'] = 'CopilotChat.nvim/2.0.0',
  ['user-agent'] = 'CopilotChat.nvim/2.0.0',
  ['sec-fetch-site'] = 'none',
  ['sec-fetch-mode'] = 'no-cors',
  ['sec-fetch-dest'] = 'empty',
  ['priority'] = 'u=4, i',
}

--- Get the github oauth cached token
---@return string|nil
local cached_github_token = nil
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
return {
  copilot = {
    get_headers = function(token, sessionid, machineid)
      return vim.tbl_extend('force', {
        ['authorization'] = 'Bearer ' .. token,
        ['x-request-id'] = utils.uuid(),
        ['vscode-sessionid'] = sessionid,
        ['vscode-machineid'] = machineid,
        ['copilot-integration-id'] = 'vscode-chat',
        ['openai-organization'] = 'github-copilot',
        ['openai-intent'] = 'conversation-panel',
        ['content-type'] = 'application/json',
      }, VERSION_HEADERS)
    end,

    get_token = function()
      local response, err =
        utils.curl_get('https://api.githubcopilot.com/copilot_internal/v2/token', {
          headers = {
            ['authorization'] = 'token ' .. get_github_token(),
            ['accept'] = 'application/json',
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
          id = agent.id,
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
      for _, model in ipairs(vim.json.decode(response.body)['data']) do
        if model['capabilities']['type'] == 'chat' then
          table.insert(models, {
            id = model.id,
            name = model.name,
            version = model.version,
            tokenizer = model.capabilities.tokenizer,
            max_prompt_tokens = model.capabilities.limits.max_prompt_tokens,
            max_output_tokens = model.capabilities.limits.max_output_tokens,
            policy = not model['policy'] or model['policy']['state'] == 'enabled',
          })
        end
      end
      return models
    end,

    prepare_model = function(model, opts, headers)
      if model.policy then
        return
      end

      utils.curl_post('https://api.githubcopilot.com/models/' .. model.id .. '/policy', {
        headers = headers,
        body = vim.json.encode({ state = 'enabled' }),
      })

      model.policy = true
    end,

    prepare_embeddings = function(inputs, opts, headers)
      return {
        dimensions = 512,
        inputs = inputs,
        model = 'text-embedding-3-small',
      }
    end,

    prepare_chat = function(messages, opts)
      return {
        messages = messages,
        model = opts.model,
        stream = opts.stream,
        n = 1,
        temperature = opts.temperature,
        top_p = 1,
        max_tokens = opts.max_output_tokens,
      }
    end,

    get_embeddings_url = function()
      return 'https://api.githubcopilot.com/embeddings'
    end,

    get_chat_url = function(opts)
      if opts.agent then
        return 'https://api.githubcopilot.com/agents/' .. opts.agent .. '?chat'
      end
      return 'https://api.githubcopilot.com/chat/completions'
    end,
  },

  github_models = {
    get_headers = function(token)
      return vim.tbl_extend('force', {
        ['authorization'] = 'bearer ' .. token,
        ['content-type'] = 'application/json',
        ['x-ms-useragent'] = VERSION_HEADERS['editor-version'],
        ['x-ms-user-agent'] = VERSION_HEADERS['editor-version'],
      }, VERSION_HEADERS)
    end,

    get_token = function()
      return get_github_token(), nil
    end,

    get_models = function()
      local response = utils.curl_post('https://api.catalog.azureml.ms/asset-gallery/v1.0/models', {
        headers = {
          ['content-type'] = 'application/json',
        },
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
            max_prompt_tokens = model.modelLimits.textLimits.inputContextWindow,
            max_output_tokens = model.modelLimits.textLimits.maxOutputTokens,
            tokenizer = 'o200k_base',
            policy = true,
          })
        end
      end

      return models
    end,

    prepare_embeddings = function(inputs)
      return {
        dimensions = 512,
        inputs = inputs,
        model = 'text-embedding-3-small',
      }
    end,

    prepare_chat = function(messages, opts)
      return {
        messages = messages,
        model = opts.model,
        stream = opts.stream,
        n = 1,
        temperature = opts.temperature,
        top_p = 1,
        max_tokens = opts.max_output_tokens,
      }
    end,

    get_embeddings_url = function()
      return 'https://api.githubcopilot.com/embeddings'
    end,

    get_chat_url = function()
      return 'https://models.inference.ai.azure.com/chat/completions'
    end,
  },
}
