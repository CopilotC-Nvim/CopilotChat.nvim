---@class CopilotChat.Client.ask
---@field history table
---@field selection CopilotChat.select.selection?
---@field embeddings table<CopilotChat.context.embed>?
---@field system_prompt string
---@field model string
---@field agent string
---@field temperature number
---@field on_progress fun(response: string):nil

---@class CopilotChat.Client.model : CopilotChat.Provider.model
---@field provider string

---@class CopilotChat.Client.agent : CopilotChat.Provider.agent
---@field provider string

local async = require('plenary.async')
local log = require('plenary.log')
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
local TRUNCATED = '... (truncated)'

--- Resolve provider function
---@param model string
---@param models table<string, CopilotChat.Client.model>
---@param providers table<string, CopilotChat.Provider>
---@return string, function
local function resolve_provider_function(name, model, models, providers)
  local model_config = models[model]
  if not model_config then
    error('Model not found: ' .. model)
  end

  local provider_name = model_config.provider
  if not provider_name then
    error('Provider not found for model: ' .. model)
  end
  local provider = providers[provider_name]
  if not provider then
    error('Provider not found: ' .. provider_name)
  end

  local func = provider[name]
  if type(func) == 'string' then
    provider_name = func
    provider = providers[provider_name]
    if not provider then
      error('Provider not found: ' .. provider_name)
    end
    func = provider[name]
  end
  if not func then
    error('Function not found: ' .. name)
  end

  return provider_name, func
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
--- @return table<CopilotChat.Provider.input>
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
--- @return table<CopilotChat.Provider.input>
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

--- Generate ask request
--- @param history table<CopilotChat.Provider.input>
--- @param prompt string
--- @param system_prompt string
--- @param generated_messages table<CopilotChat.Provider.input>
local function generate_ask_request(history, prompt, system_prompt, generated_messages)
  local messages = {}
  local contexts = {}

  if system_prompt ~= '' then
    table.insert(messages, {
      content = system_prompt,
      role = 'system',
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

  return messages
end

--- Generate embedding request
--- @param inputs table<CopilotChat.context.embed>
--- @param threshold number
--- @return table<string>
local function generate_embedding_request(inputs, threshold)
  return vim.tbl_map(function(embedding)
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
  end, inputs)
end

---@class CopilotChat.Client : Class
---@field providers table<string, CopilotChat.Provider>
---@field provider_cache table<string, table>
---@field embedding_cache table<string, CopilotChat.context.embed>
---@field models table<string, CopilotChat.Client.model>?
---@field agents table<string, CopilotChat.Client.agent>?
---@field current_job string?
---@field headers table<string, string>?
local Client = class(function(self)
  self.providers = {}
  self.provider_cache = {}
  self.embedding_cache = {}
  self.models = nil
  self.agents = nil
  self.current_job = nil
  self.headers = nil
end)

--- Authenticate with GitHub and get the required headers
---@param provider_name string: The provider to authenticate with
---@return table<string, string>
function Client:authenticate(provider_name)
  local provider = self.providers[provider_name]
  local headers = self.provider_cache[provider_name].headers
  local expires_at = self.provider_cache[provider_name].expires_at

  if not headers or (expires_at and expires_at <= math.floor(os.time())) then
    local token
    if provider.get_token then
      token, expires_at = provider.get_token()
    end

    headers = provider.get_headers(token)
    self.provider_cache[provider_name].headers = headers
    self.provider_cache[provider_name].expires_at = expires_at
  end

  return headers
end

--- Fetch models from the Copilot API
---@return table<string, CopilotChat.Client.model>
function Client:fetch_models()
  if self.models then
    return self.models
  end

  local models = {}
  local provider_order = vim.tbl_keys(self.providers)
  table.sort(provider_order)
  for _, provider_name in ipairs(provider_order) do
    local provider = self.providers[provider_name]
    if not provider.disabled and provider.get_models then
      notify.publish(notify.STATUS, 'Fetching models from ' .. provider_name)
      local headers = self:authenticate(provider_name)
      local ok, provider_models = pcall(provider.get_models, headers)
      if ok then
        for _, model in ipairs(provider_models) do
          model.provider = provider_name
          if not model.version then
            model.version = model.id
          end

          if models[model.id] then
            model.id = model.id .. ':' .. provider_name
            model.version = model.version .. ':' .. provider_name
          end
          models[model.id] = model
        end
      else
        log.warn('Failed to fetch models from ' .. provider_name .. ': ' .. provider_models)
      end
    end
  end

  log.debug('Fetched models: ', vim.inspect(models))
  self.models = models
  return self.models
end

--- Fetch agents from the Copilot API
---@return table<string, CopilotChat.Client.agent>
function Client:fetch_agents()
  if self.agents then
    return self.agents
  end

  local agents = {}
  local provider_order = vim.tbl_keys(self.providers)
  table.sort(provider_order)
  for _, provider_name in ipairs(provider_order) do
    local provider = self.providers[provider_name]
    if not provider.disabled and provider.get_agents then
      notify.publish(notify.STATUS, 'Fetching agents from ' .. provider_name)
      local headers = self:authenticate(provider_name)
      local ok, provider_agents = pcall(provider.get_agents, headers)
      if ok then
        for _, agent in ipairs(provider_agents) do
          agent.provider = provider_name
          if agents[agent.id] then
            agent.id = agent.id .. ':' .. provider_name
          end
          agents[agent.id] = agent
        end
      else
        log.warn('Failed to fetch agents from ' .. provider_name .. ': ' .. provider_agents)
      end
    end
  end

  self.agents = agents
  return self.agents
end

--- Ask a question to Copilot
---@param prompt string: The prompt to send to Copilot
---@param opts CopilotChat.Client.ask: Options for the request
---@return string?, table?, number?, number?
function Client:ask(prompt, opts)
  opts = opts or {}
  prompt = vim.trim(prompt)

  if opts.agent == 'none' or opts.agent == 'copilot' then
    opts.agent = nil
  end

  local history = opts.history or {}
  local embeddings = opts.embeddings or {}
  local selection = opts.selection or {}
  local system_prompt = vim.trim(opts.system_prompt)
  local model = opts.model
  local agent = opts.agent
  local temperature = opts.temperature
  local on_progress = opts.on_progress
  local job_id = utils.uuid()
  self.current_job = job_id

  log.trace('System prompt: ', system_prompt)
  log.trace('History: ', #history)
  log.trace('Selection: ', selection.content)
  log.debug('Prompt: ', prompt)
  log.debug('Embeddings: ', #embeddings)
  log.debug('Model: ', model)
  log.debug('Agent: ', agent)
  log.debug('Temperature: ', temperature)

  local models = self:fetch_models()
  local model_config = models[model]
  if not model_config then
    error('Model not found: ' .. model)
  end

  local agents = self:fetch_agents()
  local agent_config = agent and agents[agent]
  if agent and not agent_config then
    error('Agent not found: ' .. agent)
  end

  local provider_name = model_config.provider
  if not provider_name then
    error('Provider not found for model: ' .. model)
  end
  local provider = self.providers[provider_name]
  if not provider then
    error('Provider not found: ' .. provider_name)
  end

  local options = {
    model = vim.tbl_extend('force', model_config, {
      id = opts.model:gsub(':' .. provider_name .. '$', ''),
    }),
    agent = agent_config and vim.tbl_extend('force', agent_config, {
      id = opts.agent and opts.agent:gsub(':' .. provider_name .. '$', ''),
    }),
    temperature = temperature,
  }

  local max_tokens = model_config.max_input_tokens
  local tokenizer = model_config.tokenizer or 'o200k_base'
  log.debug('Max tokens: ', max_tokens)
  log.debug('Tokenizer: ', tokenizer)

  if max_tokens and tokenizer then
    tiktoken.load(tokenizer)
  end

  notify.publish(notify.STATUS, 'Generating request')

  async.util.scheduler()
  local references = {}
  for _, embed in ipairs(embeddings) do
    table.insert(references, {
      name = utils.filename(embed.filename),
      url = embed.filename,
    })
  end

  local generated_messages = {}
  local selection_messages = generate_selection_messages(selection)
  local embeddings_messages = generate_embeddings_messages(embeddings)

  if max_tokens then
    -- Count tokens from embeddings
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
  else
    -- Add all embedding messages as we cant limit them
    for _, message in ipairs(embeddings_messages) do
      table.insert(generated_messages, message)
    end
  end

  log.debug('Generated messages: ', #generated_messages)

  local last_message = nil
  local errored = false
  local finished = false
  local full_response = ''

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
    if not line or line == '' then
      return
    end

    log.debug('Response line: ', line)
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

    local out = provider.prepare_output(content, options)
    if out.references then
      for _, reference in ipairs(out.references) do
        table.insert(references, reference)
      end
    end

    last_message = out

    if out.content then
      full_response = full_response .. out.content
      on_progress(out.content)
    end

    if job and out.finish_reason then
      local reason = out.finish_reason
      if reason == 'stop' then
        reason = nil
      else
        reason = 'Early stop: ' .. reason
      end
      finish_stream(reason, job)
    end
  end

  local function parse_stream_line(line, job)
    line = vim.trim(line)
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

  notify.publish(notify.STATUS, 'Thinking')

  local headers = self:authenticate(provider_name)
  local request = provider.prepare_input(
    generate_ask_request(history, prompt, system_prompt, generated_messages),
    options
  )
  local is_stream = request.stream
  local body = vim.json.encode(request)

  local args = {
    body = temp_file(body),
    headers = headers,
  }

  if is_stream then
    args.stream = stream_func
  end

  local response, err = utils.curl_post(provider.get_url(options), args)

  if self.current_job ~= job_id then
    return
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
    if not full_response then
      for _, line in ipairs(vim.split(response.body, '\n')) do
        parse_stream_line(line)
      end
    end
  else
    parse_line(response.body)
  end

  if not full_response then
    error('Failed to get response: empty response')
    return
  end

  log.trace('Full response: ', full_response)
  log.debug('Last message: ', last_message)

  return full_response, references, last_message and last_message.total_tokens or 0, max_tokens
end

--- List available models
---@return table<string, table>
function Client:list_models()
  local models = self:fetch_models()

  -- First deduplicate by version, keeping shortest ID
  local version_map = {}
  for id, model in pairs(models) do
    local version = model.version or model.id
    if not version_map[version] or #id < #version_map[version] then
      version_map[version] = id
    end
  end

  local result = vim.tbl_values(version_map)
  table.sort(result, function(a, b)
    local a_model = models[a]
    local b_model = models[b]
    if a_model.provider ~= b_model.provider then
      return a_model.provider < b_model.provider -- sort by version first
    end
    return a_model.version < b_model.version -- then by provider
  end)

  local out = {}
  for _, id in ipairs(result) do
    table.insert(out, vim.tbl_extend('force', models[id], { id = id }))
  end
  return out
end

--- List available agents
---@return table<string, table>
function Client:list_agents()
  local agents = self:fetch_agents()

  local result = vim.tbl_keys(agents)
  table.sort(result)

  local out = {}
  table.insert(out, { id = 'none', name = 'None', description = 'No agent', provider = 'none' })
  for _, id in ipairs(result) do
    table.insert(out, vim.tbl_extend('force', agents[id], { id = id }))
  end
  return out
end

--- Generate embeddings for the given inputs
---@param inputs table<CopilotChat.context.embed>: The inputs to embed
---@param model string
---@return table<CopilotChat.context.embed>
function Client:embed(inputs, model)
  if not inputs or #inputs == 0 then
    return {}
  end

  local models = self:fetch_models()
  local provider_name, embed = resolve_provider_function('embed', model, models, self.providers)

  notify.publish(notify.STATUS, 'Generating embeddings for ' .. #inputs .. ' inputs')

  -- Initialize essentials
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
      local ok, data =
        pcall(embed, generate_embedding_request(batch, threshold), self:authenticate(provider_name))

      if not ok then
        log.debug('Failed to get embeddings: ', data)
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
        for _, embedding in ipairs(data) do
          local result = vim.tbl_extend('force', batch[embedding.index + 1], embedding)
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
function Client:stop()
  if self.current_job ~= nil then
    self.current_job = nil
    return true
  end

  return false
end

--- Reset the history and stop any running job
---@return boolean
function Client:reset()
  local stopped = self:stop()
  self.history = {}
  self.embedding_cache = {}
  return stopped
end

--- Check if there is a running job
---@return boolean
function Client:running()
  return self.current_job ~= nil
end

--- Load providers to client
function Client:load_providers(providers)
  self.providers = providers
  for provider_name, _ in pairs(providers) do
    self.provider_cache[provider_name] = {}
  end
end

--- @type CopilotChat.Client
return Client()
