---@class CopilotChat.client.AskOptions
---@field headless boolean
---@field history table<CopilotChat.client.Message>
---@field selection CopilotChat.select.Selection?
---@field tools table<CopilotChat.client.Tool>?
---@field resources table<CopilotChat.client.Resource>?
---@field system_prompt string
---@field model string
---@field temperature number
---@field on_progress? fun(response: string):nil

---@class CopilotChat.client.Message
---@field role string
---@field content string
---@field tool_call_id string?
---@field tool_calls table<CopilotChat.client.ToolCall>?

---@class CopilotChat.client.AskResponse
---@field message CopilotChat.client.Message
---@field token_count number
---@field token_max_count number

---@class CopilotChat.client.ToolCall
---@field id number
---@field index number
---@field name string
---@field arguments string

---@class CopilotChat.client.Tool
---@field name string name of the tool
---@field description string description of the tool
---@field schema table? schema of the tool

---@class CopilotChat.client.Embed
---@field index number
---@field embedding table<number>

---@class CopilotChat.client.Resource
---@field name string
---@field type string
---@field data string

---@class CopilotChat.client.EmbeddedResource : CopilotChat.client.Resource, CopilotChat.client.Embed

---@class CopilotChat.client.Model
---@field provider string?
---@field id string
---@field name string
---@field tokenizer string?
---@field max_input_tokens number?
---@field max_output_tokens number?
---@field streaming boolean?
---@field tools boolean?

local log = require('plenary.log')
local tiktoken = require('CopilotChat.tiktoken')
local notify = require('CopilotChat.notify')
local utils = require('CopilotChat.utils')
local class = utils.class

--- Constants
local RESOURCE_FORMAT = '# %s\n```%s\n%s\n```'
local LINE_CHARACTERS = 100
local BIG_FILE_THRESHOLD = 1000 * LINE_CHARACTERS
local BIG_EMBED_THRESHOLD = 200 * LINE_CHARACTERS
local TRUNCATED = '... (truncated)'

--- Resolve provider function
---@param model string
---@param models table<string, CopilotChat.client.Model>
---@param providers table<string, CopilotChat.config.providers.Provider>
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
---@param content string
---@param threshold number: The threshold for truncation
---@param start_line number?: The starting line number
---@return string
local function generate_content_block(content, threshold, start_line)
  local total_chars = #content
  if total_chars > threshold then
    content = content:sub(1, threshold)
    content = content .. '\n' .. TRUNCATED
  end

  if start_line ~= nil then
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

--- Generate messages for the given selection
--- @param selection CopilotChat.select.Selection
--- @return CopilotChat.client.Message?
local function generate_selection_message(selection)
  local filename = selection.filename or 'unknown'
  local filetype = selection.filetype or 'text'
  local content = selection.content

  if not content or content == '' then
    return nil
  end

  local out = "User's active selection:\n"
  if selection.start_line and selection.end_line then
    out = out .. string.format('Excerpt from %s, lines %s to %s:\n', filename, selection.start_line, selection.end_line)
  end
  out = out
    .. string.format(
      '```%s\n%s\n```',
      filetype,
      generate_content_block(content, BIG_FILE_THRESHOLD, selection.start_line)
    )

  return {
    content = out,
    role = 'user',
  }
end

--- Generate messages for the given resources
--- @param resources CopilotChat.client.Resource[]
--- @return table<CopilotChat.client.Message>
local function generate_resource_messages(resources)
  return vim
    .iter(resources or {})
    :filter(function(resource)
      return resource.data and resource.data ~= ''
    end)
    :map(function(resource)
      local content = generate_content_block(resource.data, BIG_FILE_THRESHOLD, 1)

      return {
        content = string.format(RESOURCE_FORMAT, resource.name, resource.type, content),
        role = 'user',
      }
    end)
    :totable()
end

--- Generate ask request
--- @param prompt string
--- @param system_prompt string
--- @param history table<CopilotChat.client.Message>
--- @param generated_messages table<CopilotChat.client.Message>
local function generate_ask_request(prompt, system_prompt, history, generated_messages)
  local messages = {}

  system_prompt = vim.trim(system_prompt)

  -- Include system prompt
  if not utils.empty(system_prompt) then
    table.insert(messages, {
      content = system_prompt,
      role = 'system',
    })
  end

  -- Include generated messages and history
  for _, message in ipairs(generated_messages) do
    table.insert(messages, {
      content = message.content,
      role = message.role,
    })
  end
  for _, message in ipairs(history) do
    table.insert(messages, message)
  end
  if not utils.empty(prompt) and utils.empty(history) then
    -- Include user prompt if we have no history
    table.insert(messages, {
      content = prompt,
      role = 'user',
    })
  end

  return messages
end

--- Generate embedding request
--- @param inputs table<CopilotChat.client.Resource>
--- @param threshold number
--- @return table<string>
local function generate_embedding_request(inputs, threshold)
  return vim.tbl_map(function(embedding)
    local content = generate_content_block(embedding.data, threshold)
    return string.format(RESOURCE_FORMAT, embedding.name, embedding.type, content)
  end, inputs)
end

---@class CopilotChat.client.Client : Class
---@field private providers table<string, CopilotChat.config.providers.Provider>
---@field private provider_cache table<string, table>
---@field private models table<string, CopilotChat.client.Model>?
---@field private current_job string?
---@field private headers table<string, string>?
local Client = class(function(self)
  self.providers = {}
  self.provider_cache = {}
  self.models = nil
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
---@return table<string, CopilotChat.client.Model>
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

  log.debug('Fetched models:', #models)
  self.models = models
  return self.models
end

--- Ask a question to Copilot
---@param prompt string: The prompt to send to Copilot
---@param opts CopilotChat.client.AskOptions: Options for the request
---@return CopilotChat.client.AskResponse?
function Client:ask(prompt, opts)
  opts = opts or {}
  local job_id = utils.uuid()

  log.debug('Model:', opts.model)
  log.debug('Tools:', #opts.tools)
  log.debug('Resources:', #opts.resources)
  log.debug('History:', #opts.history)

  local models = self:fetch_models()
  local model_config = models[opts.model]
  if not model_config then
    error('Model not found: ' .. opts.model)
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
    temperature = opts.temperature,
    tools = opts.tools,
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

  local history = not opts.headless and vim.deepcopy(opts.history) or {}
  local tool_calls = utils.ordered_map()
  local generated_messages = {}
  local selection_message = opts.selection and generate_selection_message(opts.selection)
  local resource_messages = generate_resource_messages(opts.resources)

  if selection_message then
    table.insert(generated_messages, selection_message)
  end

  if max_tokens then
    -- Count required tokens that we cannot reduce
    local selection_tokens = selection_message and tiktoken.count(selection_message.content) or 0
    local prompt_tokens = tiktoken.count(prompt)
    local system_tokens = tiktoken.count(opts.system_prompt)
    local resource_tokens = #resource_messages > 0 and tiktoken.count(resource_messages[1].content) or 0
    local required_tokens = prompt_tokens + system_tokens + selection_tokens + resource_tokens

    -- Calculate how many tokens we can use for history
    local history_limit = max_tokens - required_tokens
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
    for _, message in ipairs(resource_messages) do
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
    for _, message in ipairs(resource_messages) do
      table.insert(generated_messages, message)
    end
  end

  local errored = false
  local finished = false
  local token_count = 0
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

    if out.total_tokens then
      token_count = out.total_tokens
    end

    if out.tool_calls then
      for _, tool_call in ipairs(out.tool_calls) do
        local val = tool_calls:get(tool_call.index)
        if not val then
          tool_calls:set(tool_call.index, tool_call)
        else
          val.arguments = val.arguments .. tool_call.arguments
        end
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
      if reason == 'stop' or reason == 'tool_calls' then
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
  local request =
    provider.prepare_input(generate_ask_request(prompt, opts.system_prompt, history, generated_messages), options)
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
      if utils.empty(response_text) and not finished then
        for _, line in ipairs(vim.split(response.body, '\n')) do
          parse_stream_line(line)
        end
      end
    else
      parse_line(response.body)
    end
    response_text = response_buffer:tostring()
  end

  return {
    message = {
      role = 'assistant',
      content = response_text,
      tool_calls = #tool_calls:values() > 0 and tool_calls:values() or nil,
    },
    token_count = token_count,
    token_max_count = max_tokens,
  }
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

--- Generate embeddings for the given inputs
---@param inputs table<CopilotChat.client.Resource>: The inputs to embed
---@param model string
---@return table<CopilotChat.client.EmbeddedResource>
function Client:embed(inputs, model)
  if not inputs or #inputs == 0 then
    ---@diagnostic disable-next-line: return-type-mismatch
    return inputs
  end

  local models = self:fetch_models()
  local ok, provider_name, embed = pcall(resolve_provider_function, 'embed', model, models, self.providers)
  if not ok then
    ---@diagnostic disable-next-line: return-type-mismatch
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

--- @type CopilotChat.client.Client
return Client()
