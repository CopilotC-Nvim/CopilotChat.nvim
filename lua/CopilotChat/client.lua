---@class CopilotChat.Client.ask
---@field headless boolean
---@field contexts table<string, string>?
---@field selection CopilotChat.select.selection?
---@field embeddings table<CopilotChat.context.embed>?
---@field system_prompt string
---@field model string
---@field agent string?
---@field temperature number
---@field on_progress? fun(response: string):nil

---@class CopilotChat.Client.model : CopilotChat.Provider.model
---@field provider string

---@class CopilotChat.Client.agent : CopilotChat.Provider.agent
---@field provider string

local log = require('plenary.log')
local tiktoken = require('CopilotChat.tiktoken')
local notify = require('CopilotChat.notify')
local utils = require('CopilotChat.utils')
local class = utils.class

--- Constants
local CONTEXT_FORMAT = '[#file:%s](#file:%s-context)'
local LINE_CHARACTERS = 100
local BIG_FILE_THRESHOLD = 1000 * LINE_CHARACTERS
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
      local formatted_line_number = string.format('%' .. max_length .. 'd', i - 1 + (start_line or 1))
      lines[i] = formatted_line_number .. ': ' .. line
    end

    return table.concat(lines, '\n')
  end

  return content
end

--- Generate diagnostics message
---@param diagnostics table<CopilotChat.Diagnostic>
---@return string
local function generate_diagnostics(diagnostics)
  local out = {}
  for _, diagnostic in ipairs(diagnostics) do
    table.insert(
      out,
      string.format(
        '%s line=%d-%d: %s',
        diagnostic.severity,
        diagnostic.start_line,
        diagnostic.end_line,
        diagnostic.content
      )
    )
  end
  return table.concat(out, '\n')
end

--- Generate messages for the given selection
--- @param selection CopilotChat.select.selection?
--- @return table<CopilotChat.Provider.input>
local function generate_selection_messages(selection)
  if not selection then
    return {}
  end

  local filename = selection.filename or 'unknown'
  local filetype = selection.filetype or 'text'
  local content = selection.content

  if not content or content == '' then
    return {}
  end

  local out = string.format('# FILE:%s CONTEXT\n', filename:upper())
  out = out .. "User's active selection:\n"
  if selection.start_line and selection.end_line then
    out = out .. string.format('Excerpt from %s, lines %s to %s:\n', filename, selection.start_line, selection.end_line)
  end
  out = out
    .. string.format(
      '```%s\n%s\n```',
      filetype,
      generate_content_block(content, nil, BIG_FILE_THRESHOLD, selection.start_line)
    )

  if selection.diagnostics then
    out = out
      .. string.format("\nDiagnostics in user's active selection:\n%s", generate_diagnostics(selection.diagnostics))
  end

  return {
    {
      name = filename,
      context = string.format(CONTEXT_FORMAT, filename, filename),
      content = out,
      role = 'user',
    },
  }
end

--- Generate messages for the given embeddings
--- @param embeddings table<CopilotChat.context.embed>?
--- @return table<CopilotChat.Provider.input>
local function generate_embeddings_messages(embeddings)
  if not embeddings then
    return {}
  end

  return vim.tbl_map(function(embedding)
    local out = string.format(
      '# FILE:%s CONTEXT\n```%s\n%s\n```',
      embedding.filename:upper(),
      embedding.filetype or 'text',
      generate_content_block(embedding.content, embedding.outline, BIG_FILE_THRESHOLD)
    )

    if embedding.diagnostics then
      out = out
        .. string.format(
          '\nFILE:%s DIAGNOSTICS:\n%s',
          embedding.filename:upper(),
          generate_diagnostics(embedding.diagnostics)
        )
    end

    return {
      name = embedding.filename,
      context = string.format(CONTEXT_FORMAT, embedding.filename, embedding.filename),
      content = out,
      role = 'user',
    }
  end, embeddings)
end

--- Generate ask request
--- @param history table<CopilotChat.Provider.input>
--- @param contexts table<string, string>?
--- @param prompt string
--- @param system_prompt string
--- @param generated_messages table<CopilotChat.Provider.input>
local function generate_ask_request(history, contexts, prompt, system_prompt, generated_messages)
  local messages = {}

  system_prompt = vim.trim(system_prompt)

  -- Include context help
  if contexts and not vim.tbl_isempty(contexts) then
    local help_text = [[When you need additional context, request it using this format:

> #<command>:`<input>`

Examples:
> #file:`path/to/file.js`        (loads specific file)
> #buffers:`visible`             (loads all visible buffers)
> #git:`staged`                  (loads git staged changes)
> #system:`uname -a`             (loads system information)

Guidelines:
- Always request context when needed rather than guessing about files or code
- Use the > format on a new line when requesting context
- Output context commands directly - never ask if the user wants to provide information
- Assume the user will provide requested context in their next response

Available context providers and their usage:]]

    local context_names = vim.tbl_keys(contexts)
    table.sort(context_names)
    for _, name in ipairs(context_names) do
      local description = contexts[name]
      description = description:gsub('\n', '\n   ')
      help_text = help_text .. '\n\n - #' .. name .. ': ' .. description
    end

    if system_prompt ~= '' then
      system_prompt = system_prompt .. '\n\n'
    end
    system_prompt = system_prompt .. help_text
  end

  -- Include system prompt
  if not utils.empty(system_prompt) then
    table.insert(messages, {
      content = system_prompt,
      role = 'system',
    })
  end

  local context_references = {}

  -- Include embeddings and history
  for _, message in ipairs(generated_messages) do
    table.insert(messages, {
      content = message.content,
      role = message.role,
    })

    if message.context then
      context_references[message.context] = true
    end
  end
  for _, message in ipairs(history) do
    table.insert(messages, message)
  end

  -- Include context references
  prompt = vim.trim(prompt)
  if not vim.tbl_isempty(context_references) then
    if prompt ~= '' then
      prompt = '\n\n' .. prompt
    end
    prompt = table.concat(vim.tbl_keys(context_references), '\n') .. prompt
  end

  -- Include user prompt
  if not utils.empty(prompt) then
    table.insert(messages, {
      content = prompt,
      role = 'user',
    })
  end

  log.debug('System prompt:\n', system_prompt)
  log.debug('Prompt:\n', prompt)
  return messages
end

--- Generate embedding request
--- @param inputs table<CopilotChat.context.embed>
--- @param threshold number
--- @return table<string>
local function generate_embedding_request(inputs, threshold)
  return vim.tbl_map(function(embedding)
    local content = generate_content_block(embedding.outline or embedding.content, nil, threshold, -1)
    if embedding.filetype == 'raw' then
      return content
    else
      return string.format('File: `%s`\n```%s\n%s\n```', embedding.filename, embedding.filetype, content)
    end
  end, inputs)
end

---@class CopilotChat.Client : Class
---@field history table<CopilotChat.Provider.input>
---@field providers table<string, CopilotChat.Provider>
---@field provider_cache table<string, table>
---@field models table<string, CopilotChat.Client.model>?
---@field agents table<string, CopilotChat.Client.agent>?
---@field current_job string?
---@field headers table<string, string>?
local Client = class(function(self)
  self.history = {}
  self.providers = {}
  self.provider_cache = {}
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

  if provider.get_headers and (not headers or (expires_at and expires_at <= math.floor(os.time()))) then
    headers, expires_at = provider.get_headers()
    self.provider_cache[provider_name].headers = headers
    self.provider_cache[provider_name].expires_at = expires_at
  end

  return headers or {}
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
      local ok, headers = pcall(self.authenticate, self, provider_name)
      if not ok then
        log.warn('Failed to authenticate with ' .. provider_name .. ': ' .. headers)
        goto continue
      end
      local ok, provider_models = pcall(provider.get_models, headers)
      if not ok then
        log.warn('Failed to fetch models from ' .. provider_name .. ': ' .. provider_models)
        goto continue
      end

      for _, model in ipairs(provider_models) do
        model.provider = provider_name
        if models[model.id] then
          model.id = model.id .. ':' .. provider_name
        end
        models[model.id] = model
      end

      ::continue::
    end
  end

  log.debug('Fetched models:', vim.inspect(models))
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
      local ok, headers = pcall(self.authenticate, self, provider_name)
      if not ok then
        log.warn('Failed to authenticate with ' .. provider_name .. ': ' .. headers)
        goto continue
      end
      local ok, provider_agents = pcall(provider.get_agents, headers)
      if not ok then
        log.warn('Failed to fetch agents from ' .. provider_name .. ': ' .. provider_agents)
        goto continue
      end

      for _, agent in ipairs(provider_agents) do
        agent.provider = provider_name
        if agents[agent.id] then
          agent.id = agent.id .. ':' .. provider_name
        end
        agents[agent.id] = agent
      end

      ::continue::
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

  if opts.agent == 'none' or opts.agent == 'copilot' then
    opts.agent = nil
  end

  local job_id = utils.uuid()

  log.debug('Model:', opts.model)
  log.debug('Agent:', opts.agent)

  local models = self:fetch_models()
  local model_config = models[opts.model]
  if not model_config then
    error('Model not found: ' .. opts.model)
  end

  local agents = self:fetch_agents()
  local agent_config = opts.agent and agents[opts.agent]
  if opts.agent and not agent_config then
    error('Agent not found: ' .. opts.agent)
  end

  local provider_name = model_config.provider
  if not provider_name then
    error('Provider not found for model: ' .. opts.model)
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
    temperature = opts.temperature,
  }

  local max_tokens = model_config.max_input_tokens
  local tokenizer = model_config.tokenizer or 'o200k_base'
  log.debug('Tokenizer:', tokenizer)

  if max_tokens and tokenizer then
    tiktoken.load(tokenizer)
  end

  if not opts.headless then
    notify.publish(notify.STATUS, 'Generating request')
  end

  local history = not opts.headless and vim.list_slice(self.history) or {}
  local references = utils.ordered_map()
  local generated_messages = {}
  local selection_messages = generate_selection_messages(opts.selection)
  local embeddings_messages = generate_embeddings_messages(opts.embeddings)

  for _, message in ipairs(selection_messages) do
    table.insert(generated_messages, message)
    references:set(message.name, {
      name = utils.filename(message.name),
      url = message.name,
    })
  end

  if max_tokens then
    -- Count tokens from selection messages
    local selection_tokens = 0
    for _, message in ipairs(selection_messages) do
      selection_tokens = selection_tokens + tiktoken.count(message.content)
    end

    -- Count required tokens that we cannot reduce
    local prompt_tokens = tiktoken.count(prompt)
    local system_tokens = tiktoken.count(opts.system_prompt)
    local required_tokens = prompt_tokens + system_tokens + selection_tokens

    -- Reserve space for first embedding
    local reserved_tokens = #embeddings_messages > 0 and tiktoken.count(embeddings_messages[1].content) or 0

    -- Calculate how many tokens we can use for history
    local history_limit = max_tokens - required_tokens - reserved_tokens
    local history_tokens = 0
    for _, msg in ipairs(history) do
      history_tokens = history_tokens + tiktoken.count(msg.content)
    end

    -- Remove history messages until we are under the limit
    while history_tokens > history_limit and #history > 0 do
      local entry = table.remove(history, 1)
      history_tokens = history_tokens - tiktoken.count(entry.content)
    end

    -- Now add as many files as possible with remaining token budget
    local remaining_tokens = max_tokens - required_tokens - history_tokens
    for _, message in ipairs(embeddings_messages) do
      local tokens = tiktoken.count(message.content)
      if remaining_tokens - tokens >= 0 then
        remaining_tokens = remaining_tokens - tokens
        table.insert(generated_messages, message)
        references:set(message.name, {
          name = utils.filename(message.name),
          url = message.name,
        })
      else
        break
      end
    end
  else
    -- Add all embedding messages as we cant limit them
    for _, message in ipairs(embeddings_messages) do
      table.insert(generated_messages, message)
      references:set(message.name, {
        name = utils.filename(message.name),
        url = message.name,
      })
    end
  end

  log.debug('References:', #generated_messages)

  local last_message = nil
  local errored = false
  local finished = false
  local response_buffer = utils.string_buffer()

  local function finish_stream(err, job)
    if err then
      errored = true
      response_buffer:set(err)
    end

    log.debug('Finishing stream', err)
    finished = true

    if job then
      job:shutdown(0)
    end
  end

  local function parse_line(line, job)
    if not line or line == '' then
      return
    end

    log.debug('Response line:', line)
    if not opts.headless then
      notify.publish(notify.STATUS, '')
    end

    local content, err = utils.json_decode(line)

    if err then
      finish_stream(line, job)
      return
    end

    if type(content) ~= 'table' then
      finish_stream(content, job)
      return
    end

    local out = provider.prepare_output(content, options)
    last_message = out

    if out.references then
      for _, reference in ipairs(out.references) do
        references:set(reference.name, reference)
      end
    end

    if out.content then
      response_buffer:add(out.content)
      if opts.on_progress then
        opts.on_progress(out.content)
      end
    end

    if out.finish_reason then
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

    -- Ignore SSE event names and comments
    if vim.startswith(line, 'event:') or vim.startswith(line, ':') then
      return
    end

    line = line:gsub('^data:%s*', '')
    if line == '[DONE]' then
      finish_stream(nil, job)
      return
    end

    parse_line(line, job)
  end

  local function stream_func(err, line, job)
    if not line or errored or finished then
      return
    end

    if not opts.headless and self.current_job ~= job_id then
      finish_stream(nil, job)
      return
    end

    if err then
      finish_stream(err and err or line, job)
      return
    end

    parse_stream_line(line, job)
  end

  if not opts.headless then
    notify.publish(notify.STATUS, 'Thinking')
    self.current_job = job_id
  end

  local headers = self:authenticate(provider_name)
  local request = provider.prepare_input(
    generate_ask_request(history, opts.contexts, prompt, opts.system_prompt, generated_messages),
    options
  )
  local is_stream = request.stream

  local args = {
    json_request = true,
    body = request,
    headers = headers,
  }
  if is_stream then
    args.stream = stream_func
  end

  local response, err = utils.curl_post(provider.get_url(options), args)

  if not opts.headless then
    if self.current_job ~= job_id then
      return
    end

    self.current_job = nil
  end

  if response then
    log.debug('Response status:', response.status)
    log.debug('Response body:\n', response.body)
    log.debug('Response headers:\n', response.headers)
  end

  if err then
    local error_msg = 'Failed to get response: ' .. err

    if response then
      if response.status == 401 then
        local content = utils.json_decode(response.body)
        if content.authorize_url then
          error_msg = 'Failed to authenticate. Visit following url to authorize '
            .. content.slug
            .. ':\n'
            .. content.authorize_url
        end
      else
        error_msg = 'Failed to get response: ' .. tostring(response.status) .. '\n' .. response.body
      end
    end

    error(error_msg)
    return
  end

  local response_text = response_buffer:tostring()
  if errored then
    error(response_text)
    return
  end

  if response then
    if is_stream then
      if utils.empty(response_text) then
        for _, line in ipairs(vim.split(response.body, '\n')) do
          parse_stream_line(line)
        end
      end
    else
      parse_line(response.body)
    end
    response_text = response_buffer:tostring()
  end

  if utils.empty(response_text) then
    error('Failed to get response: empty response')
    return
  end

  return response_text, references:values(), last_message and last_message.total_tokens or 0, max_tokens
end

--- List available models
---@return table<string, table>
function Client:list_models()
  local models = self:fetch_models()
  local result = vim.tbl_keys(models)

  table.sort(result, function(a, b)
    a = models[a]
    b = models[b]
    if a.provider ~= b.provider then
      return a.provider < b.provider
    end
    return a.id < b.id
  end)

  return vim.tbl_map(function(id)
    return models[id]
  end, result)
end

--- List available agents
---@return table<string, table>
function Client:list_agents()
  local agents = self:fetch_agents()
  local result = vim.tbl_keys(agents)

  table.sort(result, function(a, b)
    a = agents[a]
    b = agents[b]
    if a.provider ~= b.provider then
      return a.provider < b.provider
    end
    return a.id < b.id
  end)

  local out = vim.tbl_map(function(id)
    return agents[id]
  end, result)
  table.insert(out, 1, { id = 'none', name = 'None', description = 'No agent', provider = 'none' })
  return out
end

--- Generate embeddings for the given inputs
---@param inputs table<CopilotChat.context.embed>: The inputs to embed
---@param model string
---@return table<CopilotChat.context.embed>
function Client:embed(inputs, model)
  if not inputs or #inputs == 0 then
    return inputs
  end

  local models = self:fetch_models()
  local ok, provider_name, embed = pcall(resolve_provider_function, 'embed', model, models, self.providers)
  if not ok then
    return inputs
  end

  notify.publish(notify.STATUS, 'Generating embeddings for ' .. #inputs .. ' inputs')

  -- Initialize essentials
  local to_process = inputs
  local results = {}
  local initial_chunk_size = 10

  -- Process inputs in batches with adaptive chunk size
  while #to_process > 0 do
    local chunk_size = initial_chunk_size -- Reset chunk size for each new batch
    local threshold = BIG_EMBED_THRESHOLD -- Reset threshold for each new batch
    local last_error = nil

    -- Take next chunk
    local batch = {}
    for _ = 1, math.min(chunk_size, #to_process) do
      table.insert(batch, table.remove(to_process, 1))
    end

    -- Try to get embeddings for batch
    local success = false
    local attempts = 0
    while not success and attempts < 5 do -- Limit total attempts to 5
      local ok, data = pcall(embed, generate_embedding_request(batch, threshold), self:authenticate(provider_name))

      if not ok then
        log.debug('Failed to get embeddings: ', data)
        last_error = data
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
        end
      end
    end

    if not success then
      error(last_error)
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
