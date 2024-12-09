---@class CopilotChat.copilot.ask.opts
---@field selection CopilotChat.select.selection?
---@field embeddings table<CopilotChat.context.embed>?
---@field system_prompt string?
---@field model string?
---@field agent string?
---@field temperature number?
---@field no_history boolean?
---@field on_progress nil|fun(response: string):nil

local log = require('plenary.log')
local prompts = require('CopilotChat.prompts')
local tiktoken = require('CopilotChat.tiktoken')
local notify = require('CopilotChat.notify')
local utils = require('CopilotChat.utils')
local class = utils.class
local temp_file = utils.temp_file

--- Constants
local CONTEXT_FORMAT = '[#file:%s](#file:%s-context)'
local LINE_CHARACTERS = 100
local BIG_FILE_THRESHOLD = 2000 * LINE_CHARACTERS
local BIG_EMBED_THRESHOLD = 200 * LINE_CHARACTERS
local EMBED_MODEL = 'text-embedding-3-small'
local TRUNCATED = '... (truncated)'
local TIMEOUT = 30000
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
  -- ['x-github-api-version'] = '2023-07-07',
}

--- Get the github oauth cached token
---@return string|nil
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

--- Generate content block with line numbers, truncating if necessary
---@param content string: The content
---@param outline string?: The outline
---@param threshold number: The threshold for truncation
---@param start_line number|nil: The starting line number
---@return string
local function generate_content_block(content, outline, threshold, start_line)
  local total_chars = #content
  if total_chars > threshold and outline then
    content = outline
    total_chars = #content
  end
  if total_chars > threshold then
    content = content:sub(1, threshold)
    content = content .. '\n' .. TRUNCATED
  end

  if start_line ~= -1 then
    local lines = vim.split(content, '\n')
    local total_lines = #lines
    local max_length = #tostring(total_lines)
    for i, line in ipairs(lines) do
      local formatted_line_number =
        string.format('%' .. max_length .. 'd', i - 1 + (start_line or 1))
      lines[i] = formatted_line_number .. ': ' .. line
    end

    return table.concat(lines, '\n')
  end

  return content
end

--- Generate messages for the given selection
--- @param selection CopilotChat.select.selection
local function generate_selection_messages(selection)
  local filename = selection.filename or 'unknown'
  local filetype = selection.filetype or 'text'
  local content = selection.content

  if not content or content == '' then
    return {}
  end

  local out = string.format('# FILE:%s CONTEXT\n', filename:upper())
  out = out .. "User's active selection:\n"
  if selection.start_line and selection.end_line then
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
      generate_content_block(content, nil, BIG_FILE_THRESHOLD, selection.start_line)
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
      .. string.format(
        "\nDiagnostics in user's active selection:\n%s",
        table.concat(diagnostics, '\n')
      )
  end

  return {
    {
      context = string.format(CONTEXT_FORMAT, filename, filename),
      content = out,
      role = 'user',
    },
  }
end

--- Generate messages for the given embeddings
--- @param embeddings table<CopilotChat.context.embed>
local function generate_embeddings_messages(embeddings)
  return vim.tbl_map(function(embedding)
    return {
      context = string.format(CONTEXT_FORMAT, embedding.filename, embedding.filename),
      content = string.format(
        '# FILE:%s CONTEXT\n```%s\n%s\n```',
        embedding.filename:upper(),
        embedding.filetype or 'text',
        generate_content_block(embedding.content, embedding.outline, BIG_FILE_THRESHOLD)
      ),
      role = 'user',
    }
  end, embeddings)
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
  local is_o1 = vim.startswith(model, 'o1')
  local messages = {}
  local system_role = is_o1 and 'user' or 'system'
  local contexts = {}

  if system_prompt ~= '' then
    table.insert(messages, {
      content = system_prompt,
      role = system_role,
    })
  end

  for _, message in ipairs(generated_messages) do
    table.insert(messages, {
      content = message.content,
      role = message.role,
    })

    if message.context then
      contexts[message.context] = true
    end
  end

  for _, message in ipairs(history) do
    table.insert(messages, message)
  end

  if not vim.tbl_isempty(contexts) then
    prompt = table.concat(vim.tbl_keys(contexts), '\n') .. '\n' .. prompt
  end

  table.insert(messages, {
    content = prompt,
    role = 'user',
  })

  local out = {
    messages = messages,
    model = model,
    stream = stream,
    n = 1,
  }

  if max_output_tokens then
    out.max_tokens = max_output_tokens
  end

  if not is_o1 then
    out.temperature = temperature
    out.top_p = 1
  end

  return out
end

local function generate_embedding_request(inputs, model, threshold)
  return {
    dimensions = 512,
    input = vim.tbl_map(function(embedding)
      local content =
        generate_content_block(embedding.outline or embedding.content, nil, threshold, -1)
      if embedding.filetype == 'raw' then
        return content
      else
        return string.format(
          'File: `%s`\n```%s\n%s\n```',
          embedding.filename,
          embedding.filetype,
          content
        )
      end
    end, inputs),
    model = model,
  }
end

---@class CopilotChat.Copilot : Class
---@field history table
---@field embedding_cache table<CopilotChat.context.embed>
---@field policies table<string, boolean>
---@field models table<string, table>?
---@field agents table<string, table>?
---@field current_job string?
---@field github_token string?
---@field token table?
---@field sessionid string?
---@field machineid string
---@field request_args table<string>
local Copilot = class(function(self, proxy, allow_insecure)
  self.history = {}
  self.embedding_cache = {}
  self.policies = {}
  self.models = nil
  self.agents = nil

  self.current_job = nil
  self.github_token = nil
  self.token = nil
  self.sessionid = nil
  self.machineid = utils.machine_id()
  self.github_token = get_cached_token()

  self.request_args = {
    timeout = TIMEOUT,
    proxy = proxy,
    insecure = allow_insecure,
    raw = {
      -- Retry failed requests twice
      '--retry',
      '2',
      -- Wait 1 second between retries
      '--retry-delay',
      '1',
      -- Keep connections alive for better performance
      '--keepalive-time',
      '60',
      -- Disable compression (since responses are already streamed efficiently)
      '--no-compressed',
      -- Connect timeout of 10 seconds
      '--connect-timeout',
      '10',
      -- Streaming optimizations
      '--tcp-nodelay',
      '--no-buffer',
    },
  }
end)

--- Authenticate with GitHub and get the required headers
---@return table<string, string>
function Copilot:authenticate()
  if not self.github_token then
    error(
      'No GitHub token found, please use `:Copilot auth` to set it up from copilot.lua or `:Copilot setup` for copilot.vim'
    )
  end

  if
    not self.token or (self.token.expires_at and self.token.expires_at <= math.floor(os.time()))
  then
    local sessionid = utils.uuid() .. tostring(math.floor(os.time() * 1000))
    local headers = vim.tbl_extend('force', {
      ['authorization'] = 'token ' .. self.github_token,
      ['accept'] = 'application/json',
    }, VERSION_HEADERS)

    local response, err = utils.curl_get(
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
    ['x-request-id'] = utils.uuid(),
    ['vscode-sessionid'] = self.sessionid,
    ['vscode-machineid'] = self.machineid,
    ['copilot-integration-id'] = 'vscode-chat',
    ['openai-organization'] = 'github-copilot',
    ['openai-intent'] = 'conversation-panel',
    ['content-type'] = 'application/json',
  }
  for key, value in pairs(VERSION_HEADERS) do
    headers[key] = value
  end

  return headers
end

--- Fetch models from the Copilot API
---@return table<string, table>
function Copilot:fetch_models()
  if self.models then
    return self.models
  end

  notify.publish(notify.STATUS, 'Fetching models')

  local response, err = utils.curl_get(
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
    if not model['policy'] or model['policy']['state'] == 'enabled' then
      self.policies[model['id']] = true
    end

    if model['capabilities']['type'] == 'chat' then
      out[model['id']] = model
    end
  end

  log.trace(models)
  self.models = out
  return out
end

--- Fetch agents from the Copilot API
---@return table<string, table>
function Copilot:fetch_agents()
  if self.agents then
    return self.agents
  end

  notify.publish(notify.STATUS, 'Fetching agents')

  local response, err = utils.curl_get(
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

  log.trace(agents)
  self.agents = out
  return out
end

--- Enable policy for the given model if required
---@param model string: The model to enable policy for
function Copilot:enable_policy(model)
  if self.policies[model] then
    return
  end

  notify.publish(notify.STATUS, 'Enabling ' .. model .. ' policy')

  local response, err = utils.curl_post(
    'https://api.githubcopilot.com/models/' .. model .. '/policy',
    vim.tbl_extend('force', self.request_args, {
      headers = self:authenticate(),
      body = vim.json.encode({ state = 'enabled' }),
    })
  )

  self.policies[model] = true

  if err or response.status ~= 200 then
    log.warn('Failed to enable policy for ', model, ': ', (err or response.body))
    return
  end
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
  local no_history = opts.no_history or false
  local on_progress = opts.on_progress
  local job_id = utils.uuid()
  self.current_job = job_id

  log.trace('System prompt: ', system_prompt)
  log.trace('Selection: ', selection.content)
  log.debug('Prompt: ', prompt)
  log.debug('Embeddings: ', #embeddings)
  log.debug('Model: ', model)
  log.debug('Agent: ', agent)
  log.debug('Temperature: ', temperature)

  local history = no_history and {} or self.history
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
  log.debug('Max tokens: ', max_tokens)
  log.debug('Tokenizer: ', tokenizer)
  tiktoken.load(tokenizer)

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

  -- Reserve space for first embedding
  local reserved_tokens = #embeddings_messages > 0
      and tiktoken.count(embeddings_messages[1].content)
    or 0

  -- Calculate how many tokens we can use for history
  local history_limit = max_tokens - required_tokens - reserved_tokens
  local history_tokens = 0
  for _, msg in ipairs(history) do
    history_tokens = history_tokens + tiktoken.count(msg.content)
  end

  -- If we're over history limit, truncate history from the beginning
  while history_tokens > history_limit and #history > 0 do
    local removed = table.remove(history, 1)
    history_tokens = history_tokens - tiktoken.count(removed.content)
  end

  -- Now add as many files as possible with remaining token budget (back to front)
  local remaining_tokens = max_tokens - required_tokens - history_tokens
  for i = #embeddings_messages, 1, -1 do
    local message = embeddings_messages[i]
    local tokens = tiktoken.count(message.content)
    if remaining_tokens - tokens >= 0 then
      remaining_tokens = remaining_tokens - tokens
      table.insert(generated_messages, message)
    else
      break
    end
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

    log.debug('Finishing stream', err)
    finished = true
    job:shutdown(0)
  end

  local function parse_line(line, job)
    if not line then
      return
    end

    notify.publish(notify.STATUS, '')

    local ok, content = pcall(vim.json.decode, line, {
      luanil = {
        object = true,
        array = true,
      },
    })

    if not ok then
      if job then
        finish_stream(
          'Failed to parse response: ' .. utils.make_string(content) .. '\n' .. line,
          job
        )
      end
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

    if content then
      full_response = full_response .. content
    end

    if content and on_progress then
      on_progress(content)
    end

    if choice.finish_reason and job then
      finish_stream(nil, job)
    end
  end

  local function parse_stream_line(line, job)
    line = vim.trim(line)
    if not vim.startswith(line, 'data:') then
      return
    end
    line = line:gsub('^data:', '')
    line = vim.trim(line)

    if line == '[DONE]' then
      if job then
        finish_stream(nil, job)
      end
      return
    end

    parse_line(line, job)
  end

  local function stream_func(err, line, job)
    if not line or errored or finished then
      return
    end

    if self.current_job ~= job_id then
      finish_stream(nil, job)
      return
    end

    if err then
      finish_stream('Failed to get response: ' .. utils.make_string(err and err or line), job)
      return
    end

    parse_stream_line(line, job)
  end

  local is_stream = not vim.startswith(model, 'o1')
  local body = vim.json.encode(
    generate_ask_request(
      history,
      prompt,
      system_prompt,
      generated_messages,
      model,
      temperature,
      max_output_tokens,
      is_stream
    )
  )

  self:enable_policy(model)
  local url = 'https://api.githubcopilot.com/chat/completions'
  if not agent_config.default then
    url = 'https://api.githubcopilot.com/agents/' .. agent .. '?chat'
  end

  local args = vim.tbl_extend('force', self.request_args, {
    headers = self:authenticate(),
    body = temp_file(body),
  })

  if is_stream then
    args.stream = stream_func
  end

  notify.publish(notify.STATUS, 'Thinking')

  local response, err = utils.curl_post(url, args)

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

  log.debug('Response status: ', response.status)
  log.debug('Response body: ', response.body)
  log.debug('Response headers: ', response.headers)

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

  if is_stream then
    if full_response == '' then
      for _, line in ipairs(vim.split(response.body, '\n')) do
        parse_stream_line(line)
      end
    end
  else
    parse_line(response.body)
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

  log.trace('Full response: ', full_response)
  log.debug('Last message: ', last_message)

  table.insert(history, {
    content = prompt,
    role = 'user',
  })

  table.insert(history, {
    content = full_response,
    role = 'assistant',
  })

  if not no_history then
    log.debug('History size increased to ' .. #history)
    self.history = history
  end

  return full_response,
    last_message and last_message.usage and last_message.usage.total_tokens,
    max_tokens
end

--- List available models
---@return table<string, string>
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
---@return table<string, string>
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
---@param inputs table<CopilotChat.context.embed>: The inputs to embed
---@return table<CopilotChat.context.embed>
function Copilot:embed(inputs)
  if not inputs or #inputs == 0 then
    return {}
  end

  notify.publish(notify.STATUS, 'Generating embeddings for ' .. #inputs .. ' inputs')

  -- Initialize essentials
  local model = EMBED_MODEL
  local to_process = {}
  local results = {}
  local initial_chunk_size = 10

  -- Process each input, using cache when possible
  for _, input in ipairs(inputs) do
    input.filename = input.filename or 'unknown'
    input.filetype = input.filetype or 'text'

    if input.content then
      local cache_key = input.filename .. utils.quick_hash(input.content)
      if self.embedding_cache[cache_key] then
        table.insert(results, self.embedding_cache[cache_key])
      else
        table.insert(to_process, input)
      end
    end
  end

  -- Process inputs in batches with adaptive chunk size
  while #to_process > 0 do
    local chunk_size = initial_chunk_size -- Reset chunk size for each new batch
    local threshold = BIG_EMBED_THRESHOLD -- Reset threshold for each new batch

    -- Take next chunk
    local batch = {}
    for _ = 1, math.min(chunk_size, #to_process) do
      table.insert(batch, table.remove(to_process, 1))
    end

    -- Try to get embeddings for batch
    local success = false
    local attempts = 0
    while not success and attempts < 5 do -- Limit total attempts to 5
      local body = vim.json.encode(generate_embedding_request(batch, model, threshold))
      local response, err = utils.curl_post(
        'https://api.githubcopilot.com/embeddings',
        vim.tbl_extend('force', self.request_args, {
          headers = self:authenticate(),
          body = temp_file(body),
        })
      )

      if err or not response or response.status ~= 200 then
        attempts = attempts + 1
        -- If we have few items and the request failed, try reducing threshold first
        if #batch <= 5 then
          threshold = math.max(5 * LINE_CHARACTERS, math.floor(threshold / 2))
          log.debug(string.format('Reducing threshold to %d and retrying...', threshold))
        else
          -- Otherwise reduce batch size first
          chunk_size = math.max(1, math.floor(chunk_size / 2))
          -- Put items back in to_process
          for i = #batch, 1, -1 do
            table.insert(to_process, 1, table.remove(batch, i))
          end
          -- Take new smaller batch
          batch = {}
          for _ = 1, math.min(chunk_size, #to_process) do
            table.insert(batch, table.remove(to_process, 1))
          end
          log.debug(string.format('Reducing batch size to %d and retrying...', chunk_size))
        end
      else
        success = true

        -- Process and cache results
        local ok, content = pcall(vim.json.decode, response.body)
        if not ok then
          error('Failed to parse embedding response: ' .. response.body)
        end

        for _, embedding in ipairs(content.data) do
          local result = vim.tbl_extend('keep', batch[embedding.index + 1], embedding)
          table.insert(results, result)

          local cache_key = result.filename .. utils.quick_hash(result.content)
          self.embedding_cache[cache_key] = result
        end
      end
    end

    if not success then
      error('Failed to process embeddings after multiple attempts')
    end
  end

  return results
end

--- Stop the running job
---@return boolean
function Copilot:stop()
  if self.current_job ~= nil then
    self.current_job = nil
    return true
  end

  return false
end

--- Reset the history and stop any running job
---@return boolean
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
