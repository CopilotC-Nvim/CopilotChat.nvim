---@class CopilotChat.copilot.embed
---@field content string
---@field filename string
---@field filetype string

---@class CopilotChat.copilot.ask.opts
---@field selection CopilotChat.config.selection?
---@field embeddings table<CopilotChat.copilot.embed>?
---@field system_prompt string?
---@field model string?
---@field agent string?
---@field temperature number?
---@field on_progress nil|fun(response: string):nil

---@class CopilotChat.copilot.embed.opts
---@field model string?
---@field chunk_size number?

---@class CopilotChat.Copilot
---@field ask fun(self: CopilotChat.Copilot, prompt: string, opts: CopilotChat.copilot.ask.opts):string,number,number
---@field embed fun(self: CopilotChat.Copilot, inputs: table, opts: CopilotChat.copilot.embed.opts?):table<CopilotChat.copilot.embed>
---@field stop fun(self: CopilotChat.Copilot):boolean
---@field reset fun(self: CopilotChat.Copilot):boolean
---@field save fun(self: CopilotChat.Copilot, name: string, path: string):nil
---@field load fun(self: CopilotChat.Copilot, name: string, path: string):table
---@field running fun(self: CopilotChat.Copilot):boolean
---@field list_models fun(self: CopilotChat.Copilot):table
---@field list_agents fun(self: CopilotChat.Copilot):table

local async = require('plenary.async')
local log = require('plenary.log')
local curl = require('plenary.curl')
local prompts = require('CopilotChat.prompts')
local tiktoken = require('CopilotChat.tiktoken')
local utils = require('CopilotChat.utils')
local class = utils.class
local temp_file = utils.temp_file
local timeout = 30000
local version_headers = {
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
  -- ['x-github-api-version'] = '2023-07-07',
}

local curl_get = async.wrap(function(url, opts, callback)
  opts = vim.tbl_deep_extend('force', opts, {
    callback = callback,
    on_error = function(err)
      err = err and err.stderr or vim.inspect(err)
      callback(nil, err)
    end,
  })
  curl.get(url, opts)
end, 3)

local curl_post = async.wrap(function(url, opts, callback)
  opts = vim.tbl_deep_extend('force', opts, {
    callback = callback,
    on_error = function(err)
      err = err and err.stderr or vim.inspect(err)
      callback(nil, err)
    end,
  })
  curl.post(url, opts)
end, 3)

local tiktoken_load = async.wrap(function(tokenizer, callback)
  tiktoken.load(tokenizer, callback)
end, 2)

local function uuid()
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return (
    string.gsub(template, '[xy]', function(c)
      local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
      return string.format('%x', v)
    end)
  )
end

local function machine_id()
  local length = 65
  local hex_chars = '0123456789abcdef'
  local hex = ''
  for _ = 1, length do
    local index = math.random(1, #hex_chars)
    hex = hex .. hex_chars:sub(index, index)
  end
  return hex
end

local function quick_hash(str)
  return #str .. str:sub(1, 32) .. str:sub(-32)
end

local function get_cached_token()
  -- loading token from the environment only in GitHub Codespaces
  local token = os.getenv('GITHUB_TOKEN')
  local codespaces = os.getenv('CODESPACES')
  if token and codespaces then
    return token
  end

  -- loading token from the file
  local config_path = utils.config_path()
  if not config_path then
    return nil
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
          return value.oauth_token
        end
      end
    end
  end

  return nil
end

local function generate_line_numbers(content, start_line)
  local lines = vim.split(content, '\n')
  local total_lines = #lines
  local max_length = #tostring(total_lines)
  for i, line in ipairs(lines) do
    local formatted_line_number = string.format('%' .. max_length .. 'd', i - 1 + (start_line or 1))
    lines[i] = formatted_line_number .. ': ' .. line
  end
  content = table.concat(lines, '\n')
  return content
end

--- Generate messages for the given selection
--- @param selection CopilotChat.config.selection
local function generate_selection_messages(selection)
  local filename = selection.filename or 'unknown'
  local filetype = selection.filetype or 'text'
  local content = selection.content

  if not content or content == '' then
    return {}
  end

  local out = string.format('# FILE:%s CONTEXT\n', filename:upper())
  out = out .. "User's active selection:\n"
  if selection.start_line and selection.end_line > 0 then
    out = out
      .. string.format(
        'Excerpt from %s, lines %s to %s:\n',
        filename,
        selection.start_line,
        selection.end_line
      )
  end
  out = out
    .. string.format(
      '```%s\n%s\n```',
      filetype,
      generate_line_numbers(content, selection.start_line)
    )

  if selection.diagnostics then
    local diagnostics = {}
    for _, diagnostic in ipairs(selection.diagnostics) do
      table.insert(
        diagnostics,
        string.format(
          '%s line=%d-%d: %s',
          diagnostic.severity,
          diagnostic.start_line,
          diagnostic.end_line,
          diagnostic.content
        )
      )
    end

    out = out
      .. string.format('\n# FILE:%s DIAGNOSTICS:\n%s', filename, table.concat(diagnostics, '\n'))
  end

  return {
    {
      content = out,
      role = 'user',
    },
  }
end

--- Generate messages for the given embeddings
--- @param embeddings table<CopilotChat.copilot.embed>
local function generate_embeddings_messages(embeddings)
  local files = {}
  for _, embedding in ipairs(embeddings) do
    local filename = embedding.filename
    if not files[filename] then
      files[filename] = {}
    end
    table.insert(files[filename], embedding)
  end

  local out = {}

  for filename, group in pairs(files) do
    table.insert(out, {
      content = string.format(
        '# FILE:%s CONTEXT\n```%s\n%s\n```',
        filename:upper(),
        group[1].filetype,
        generate_line_numbers(table.concat(
          vim.tbl_map(function(e)
            return vim.trim(e.content)
          end, group),
          '\n'
        ))
      ),
      role = 'user',
    })
  end

  return out
end

local function generate_ask_request(
  history,
  prompt,
  system_prompt,
  generated_messages,
  model,
  temperature,
  max_output_tokens,
  stream
)
  local messages = {}
  local system_role = stream and 'system' or 'user'

  if system_prompt ~= '' then
    table.insert(messages, {
      content = system_prompt,
      role = system_role,
    })
  end

  for _, message in ipairs(generated_messages) do
    table.insert(messages, message)
  end

  for _, message in ipairs(history) do
    table.insert(messages, message)
  end

  table.insert(messages, {
    content = prompt,
    role = 'user',
  })

  local out = {
    messages = messages,
    model = model,
    stream = stream,
  }

  if max_output_tokens then
    out.max_tokens = max_output_tokens
  end

  if stream then
    out.n = 1
    out.temperature = temperature
    out.top_p = 1
  end

  return out
end

local function generate_embedding_request(inputs, model)
  return {
    dimensions = 512,
    input = vim.tbl_map(function(input)
      local out = ''
      if input.filetype == 'raw' then
        out = input.content .. '\n'
      else
        out = out
          .. string.format(
            'File: `%s`\n```%s\n%s\n```',
            input.filename,
            input.filetype,
            input.content
          )
      end

      return out
    end, inputs),
    model = model,
  }
end

local function count_history_tokens(history)
  local count = 0
  for _, msg in ipairs(history) do
    count = count + tiktoken.count(msg.content)
  end
  return count
end

local Copilot = class(function(self, proxy, allow_insecure)
  self.history = {}
  self.embedding_cache = {}
  self.github_token = nil
  self.token = nil
  self.sessionid = nil
  self.machineid = machine_id()
  self.models = nil
  self.agents = nil
  self.claude_enabled = false
  self.current_job = nil
  self.request_args = {
    timeout = timeout,
    proxy = proxy,
    insecure = allow_insecure,
    raw = {
      -- Retry failed requests twice
      '--retry',
      '2',
      -- Wait 1 second between retries
      '--retry-delay',
      '1',
      -- Maximum time for the request
      '--max-time',
      math.floor(timeout * 2 / 1000),
      -- Timeout for initial connection
      '--connect-timeout',
      '10',
      '--no-keepalive', -- Don't reuse connections
      '--tcp-nodelay', -- Disable Nagle's algorithm for faster streaming
      '--no-buffer', -- Disable output buffering for streaming
    },
  }
end)

function Copilot:authenticate()
  if not self.github_token then
    self.github_token = get_cached_token()
    if not self.github_token then
      error(
        'No GitHub token found, please use `:Copilot auth` to set it up from copilot.lua or `:Copilot setup` for copilot.vim'
      )
    end
  end

  if
    not self.token or (self.token.expires_at and self.token.expires_at <= math.floor(os.time()))
  then
    local sessionid = uuid() .. tostring(math.floor(os.time() * 1000))
    local headers = {
      ['authorization'] = 'token ' .. self.github_token,
      ['accept'] = 'application/json',
    }
    for key, value in pairs(version_headers) do
      headers[key] = value
    end

    local response, err = curl_get(
      'https://api.github.com/copilot_internal/v2/token',
      vim.tbl_extend('force', self.request_args, {
        headers = headers,
      })
    )

    if err then
      error(err)
    end

    if response.status ~= 200 then
      error('Failed to authenticate: ' .. tostring(response.status))
    end

    self.sessionid = sessionid
    self.token = vim.json.decode(response.body)
  end

  local headers = {
    ['authorization'] = 'Bearer ' .. self.token.token,
    ['x-request-id'] = uuid(),
    ['vscode-sessionid'] = self.sessionid,
    ['vscode-machineid'] = self.machineid,
    ['copilot-integration-id'] = 'vscode-chat',
    ['openai-organization'] = 'github-copilot',
    ['openai-intent'] = 'conversation-panel',
    ['content-type'] = 'application/json',
  }
  for key, value in pairs(version_headers) do
    headers[key] = value
  end

  return headers
end

function Copilot:fetch_models()
  if self.models then
    return self.models
  end

  local response, err = curl_get(
    'https://api.githubcopilot.com/models',
    vim.tbl_extend('force', self.request_args, {
      headers = self:authenticate(),
    })
  )

  if err then
    error(err)
  end

  if response.status ~= 200 then
    error('Failed to fetch models: ' .. tostring(response.status))
  end

  -- Find chat models
  local models = vim.json.decode(response.body)['data']
  local out = {}
  for _, model in ipairs(models) do
    if model['capabilities']['type'] == 'chat' then
      out[model['id']] = model
    end
  end

  log.info('Models fetched')
  self.models = out
  return out
end

function Copilot:fetch_agents()
  if self.agents then
    return self.agents
  end

  local response, err = curl_get(
    'https://api.githubcopilot.com/agents',
    vim.tbl_extend('force', self.request_args, {
      headers = self:authenticate(),
    })
  )

  if err then
    error(err)
  end

  if response.status ~= 200 then
    error('Failed to fetch agents: ' .. tostring(response.status))
  end

  local agents = vim.json.decode(response.body)['agents']
  local out = {}
  for _, agent in ipairs(agents) do
    out[agent['slug']] = agent
  end

  out['copilot'] = { name = 'Copilot', default = true, description = 'Default noop agent' }

  log.info('Agents fetched')
  self.agents = out
  return out
end

function Copilot:enable_claude()
  if self.claude_enabled then
    return true
  end

  local business_check = 'cannot enable policy inline for business users'
  local business_msg =
    'Claude is probably enabled (for business users needs to be enabled manually).'

  local response, err = curl_post(
    'https://api.githubcopilot.com/models/claude-3.5-sonnet/policy',
    vim.tbl_extend('force', self.request_args, {
      headers = self:authenticate(),
      body = vim.json.encode({ state = 'enabled' }),
    })
  )

  if err then
    error(err)
  end

  -- Handle business user case
  if response.status ~= 200 and string.find(tostring(response.body), business_check) then
    self.claude_enabled = true
    log.info(business_msg)
    return true
  end

  -- Handle errors
  if response.status ~= 200 then
    error('Failed to enable Claude: ' .. tostring(response.status))
  end

  self.claude_enabled = true
  log.info('Claude enabled')
  return true
end

--- Ask a question to Copilot
---@param prompt string: The prompt to send to Copilot
---@param opts CopilotChat.copilot.ask.opts: Options for the request
function Copilot:ask(prompt, opts)
  opts = opts or {}
  prompt = vim.trim(prompt)
  local embeddings = opts.embeddings or {}
  local selection = opts.selection or {}
  local system_prompt = vim.trim(opts.system_prompt or prompts.COPILOT_INSTRUCTIONS)
  local model = opts.model or 'gpt-4o-2024-05-13'
  local agent = opts.agent or 'copilot'
  local temperature = opts.temperature or 0.1
  local on_progress = opts.on_progress
  local job_id = uuid()
  self.current_job = job_id

  log.trace('System prompt: ' .. system_prompt)
  log.trace('Selection: ' .. (selection.content or ''))
  log.debug('Prompt: ' .. prompt)
  log.debug('Embeddings: ' .. #embeddings)
  log.debug('Model: ' .. model)
  log.debug('Agent: ' .. agent)
  log.debug('Temperature: ' .. temperature)

  local models = self:fetch_models()
  local agents = self:fetch_agents()
  local agent_config = agents[agent]
  if not agent_config then
    error('Agent not found: ' .. agent)
  end
  local model_config = models[model]
  if not model_config then
    error('Model not found: ' .. model)
  end

  local capabilities = model_config.capabilities
  local max_tokens = capabilities.limits.max_prompt_tokens -- FIXME: Is max_prompt_tokens the right limit?
  local max_output_tokens = capabilities.limits.max_output_tokens
  local tokenizer = capabilities.tokenizer
  log.debug('Max tokens: ' .. max_tokens)
  log.debug('Tokenizer: ' .. tokenizer)
  tiktoken_load(tokenizer)

  local generated_messages = {}
  local selection_messages = generate_selection_messages(selection)
  local embeddings_messages = generate_embeddings_messages(embeddings)
  local generated_tokens = 0
  for _, message in ipairs(selection_messages) do
    generated_tokens = generated_tokens + tiktoken.count(message.content)
    table.insert(generated_messages, message)
  end

  -- Count required tokens that we cannot reduce
  local prompt_tokens = tiktoken.count(prompt)
  local system_tokens = tiktoken.count(system_prompt)
  local required_tokens = prompt_tokens + system_tokens + generated_tokens

  -- Reserve space for first embedding if its smaller than half of max tokens
  local reserved_tokens = 0
  if #embeddings_messages > 0 then
    local file_tokens = tiktoken.count(embeddings_messages[1].content)
    if file_tokens < max_tokens / 2 then
      reserved_tokens = file_tokens
    end
  end

  -- Calculate how many tokens we can use for history
  local history_limit = max_tokens - required_tokens - reserved_tokens
  local history_tokens = count_history_tokens(self.history)

  -- If we're over history limit, truncate history from the beginning
  while history_tokens > history_limit and #self.history > 0 do
    local removed = table.remove(self.history, 1)
    history_tokens = history_tokens - tiktoken.count(removed.content)
  end

  -- Now add as many files as possible with remaining token budget
  local remaining_tokens = max_tokens - required_tokens - history_tokens
  for _, message in ipairs(embeddings_messages) do
    local tokens = tiktoken.count(message.content)
    if remaining_tokens - tokens >= 0 then
      remaining_tokens = remaining_tokens - tokens
      table.insert(generated_messages, message)
    else
      break
    end
  end

  -- Prepend links to embeddings to the prompt
  local embeddings_prompt = ''
  for _, embedding in ipairs(embeddings) do
    embeddings_prompt = embeddings_prompt
      .. string.format('[#file:%s](#file:%s-context)\n', embedding.filename, embedding.filename)
  end
  if embeddings_prompt ~= '' then
    prompt = embeddings_prompt .. '\n' .. prompt
  end

  local last_message = nil
  local errored = false
  local finished = false
  local full_response = ''
  local full_references = ''

  local function finish_stream(err, job)
    if err then
      errored = true
      full_response = err
    end

    finished = true
    job:shutdown(0)
  end

  local function stream_func(err, line, job)
    if not line or errored or finished then
      return
    end

    if self.current_job ~= job_id then
      finish_stream(nil, job)
      return
    end

    if err or vim.startswith(line, '{"error"') then
      finish_stream('Failed to get response: ' .. (err and vim.inspect(err) or line), job)
      return
    end

    if not vim.startswith(line, 'data: ') then
      return
    end

    line = line:gsub('^%s*data:%s*', ''):gsub('%s*$', '')

    if line == '[DONE]' then
      finish_stream(nil, job)
      return
    end

    local ok, content = pcall(vim.json.decode, line, {
      luanil = {
        object = true,
        array = true,
      },
    })

    if not ok then
      finish_stream('Failed to parse response: ' .. vim.inspect(content) .. '\n' .. line, job)
      return
    end

    if content.copilot_references then
      for _, reference in ipairs(content.copilot_references) do
        local metadata = reference.metadata
        if metadata and metadata.display_name and metadata.display_url then
          full_references = full_references
            .. '\n'
            .. '['
            .. metadata.display_name
            .. ']'
            .. '('
            .. metadata.display_url
            .. ')'
        end
      end
    end

    if not content.choices or #content.choices == 0 then
      return
    end

    last_message = content
    local choice = content.choices[1]
    content = choice.message and choice.message.content or choice.delta and choice.delta.content

    if not content then
      return
    end

    if on_progress then
      on_progress(content)
    end

    full_response = full_response .. content
  end

  local body = vim.json.encode(
    generate_ask_request(
      self.history,
      prompt,
      system_prompt,
      generated_messages,
      model,
      temperature,
      max_output_tokens,
      not vim.startswith(model, 'o1')
    )
  )

  if vim.startswith(model, 'claude') then
    self:enable_claude()
  end

  local url = 'https://api.githubcopilot.com/chat/completions'
  if not agent_config.default then
    url = 'https://api.githubcopilot.com/agents/' .. agent .. '?chat'
  end

  local response, err = curl_post(
    url,
    vim.tbl_extend('force', self.request_args, {
      headers = self:authenticate(),
      body = temp_file(body),
      stream = stream_func,
    })
  )

  if self.current_job ~= job_id then
    return nil, nil, nil
  end

  self.current_job = nil

  if err then
    error(err)
    return
  end

  if not response then
    error('Failed to get response')
    return
  end

  if response.status ~= 200 then
    if response.status == 401 then
      local ok, content = pcall(vim.json.decode, response.body, {
        luanil = {
          object = true,
          array = true,
        },
      })

      if ok and content.authorize_url then
        error(
          'Failed to authenticate. Visit following url to authorize '
            .. content.slug
            .. ':\n'
            .. content.authorize_url
        )
        return
      end
    end

    error('Failed to get response: ' .. tostring(response.status) .. '\n' .. response.body)
    return
  end

  if errored then
    error(full_response)
    return
  end

  if full_response == '' then
    error('Failed to get response: empty response')
    return
  end

  if full_references ~= '' then
    full_references = '\n\n**`References:`**' .. full_references
    full_response = full_response .. full_references
    if on_progress then
      on_progress(full_references)
    end
  end

  log.trace('Full response: ' .. full_response)
  log.debug('Last message: ' .. vim.inspect(last_message))

  table.insert(self.history, {
    content = prompt,
    role = 'user',
  })

  table.insert(self.history, {
    content = full_response,
    role = 'assistant',
  })

  return full_response,
    last_message and last_message.usage and last_message.usage.total_tokens,
    max_tokens
end

--- List available models
---@return table
function Copilot:list_models()
  local models = self:fetch_models()

  local version_map = {}
  for id, model in pairs(models) do
    local version = model.version
    if not version_map[version] or #id < #version_map[version] then
      version_map[version] = id
    end
  end

  local result = vim.tbl_values(version_map)
  table.sort(result)

  local out = {}
  for _, id in ipairs(result) do
    out[id] = models[id].name
  end
  return out
end

--- List available agents
---@return table
function Copilot:list_agents()
  local agents = self:fetch_agents()

  local result = vim.tbl_keys(agents)
  table.sort(result)

  local out = {}
  for _, id in ipairs(result) do
    out[id] = agents[id].description
  end
  return out
end

--- Generate embeddings for the given inputs
---@param inputs table<CopilotChat.copilot.embed>: The inputs to embed
---@param opts CopilotChat.copilot.embed.opts: Options for the request
function Copilot:embed(inputs, opts)
  if not inputs or #inputs == 0 then
    return {}
  end

  -- Check which embeddings need to be fetched
  local cached_embeddings = {}
  local uncached_embeddings = {}
  for _, embed in ipairs(inputs) do
    if embed.content then
      local key = embed.filename .. quick_hash(embed.content)
      if self.embedding_cache[key] then
        table.insert(cached_embeddings, self.embedding_cache[key])
      else
        table.insert(uncached_embeddings, embed)
      end
    else
      table.insert(uncached_embeddings, embed)
    end
  end

  opts = opts or {}
  local model = opts.model or 'text-embedding-3-small'
  local chunk_size = opts.chunk_size or 15

  local out = {}

  for i = 1, #uncached_embeddings, chunk_size do
    local chunk = vim.list_slice(uncached_embeddings, i, i + chunk_size - 1)
    local body = vim.json.encode(generate_embedding_request(chunk, model))
    local response, err = curl_post(
      'https://api.githubcopilot.com/embeddings',
      vim.tbl_extend('force', self.request_args, {
        headers = self:authenticate(),
        body = temp_file(body),
      })
    )

    if err then
      error(err)
      return
    end

    if not response then
      error('Failed to get response')
      return
    end

    if response.status ~= 200 then
      error('Failed to get response: ' .. tostring(response.status) .. '\n' .. response.body)
      return
    end

    local ok, content = pcall(vim.json.decode, response.body, {
      luanil = {
        object = true,
        array = true,
      },
    })

    if not ok then
      error('Failed to parse response: ' .. vim.inspect(content) .. '\n' .. response.body)
      return
    end

    for _, embedding in ipairs(content.data) do
      table.insert(out, vim.tbl_extend('keep', chunk[embedding.index + 1], embedding))
    end
  end

  -- Cache embeddings
  for _, embedding in ipairs(out) do
    if embedding.content then
      local key = embedding.filename .. quick_hash(embedding.content)
      self.embedding_cache[key] = embedding
    end
  end

  -- Merge cached embeddings and newly fetched embeddings and return
  return vim.list_extend(out, cached_embeddings)
end

--- Stop the running job
function Copilot:stop()
  if self.current_job ~= nil then
    self.current_job = nil
    return true
  end

  return false
end

--- Reset the history and stop any running job
function Copilot:reset()
  local stopped = self:stop()
  self.history = {}
  self.embedding_cache = {}
  return stopped
end

--- Save the history to a file
---@param name string: The name to save the history to
---@param path string: The path to save the history to
function Copilot:save(name, path)
  local history = vim.json.encode(self.history)
  path = vim.fn.expand(path)
  vim.fn.mkdir(path, 'p')
  path = path .. '/' .. name .. '.json'
  local file = io.open(path, 'w')
  if not file then
    log.error('Failed to save history to ' .. path)
    return
  end

  file:write(history)
  file:close()
  log.info('Saved Copilot history to ' .. path)
end

--- Load the history from a file
---@param name string: The name to load the history from
---@param path string: The path to load the history from
---@return table
function Copilot:load(name, path)
  path = vim.fn.expand(path) .. '/' .. name .. '.json'
  local file = io.open(path, 'r')
  if not file then
    return {}
  end

  local history = file:read('*a')
  file:close()
  self.history = vim.json.decode(history, {
    luanil = {
      object = true,
      array = true,
    },
  })

  log.info('Loaded Copilot history from ' .. path)
  return self.history
end

--- Check if there is a running job
---@return boolean
function Copilot:running()
  return self.current_job ~= nil
end

return Copilot
