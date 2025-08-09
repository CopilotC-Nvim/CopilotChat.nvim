---@class CopilotChat.client.AskOptions
---@field headless boolean
---@field history table<CopilotChat.client.Message>
---@field selection CopilotChat.select.Selection?
---@field tools table<CopilotChat.client.Tool>?
---@field resources table<CopilotChat.client.Resource>?
---@field system_prompt string
---@field model string
---@field temperature number
---@field on_progress fun(response: CopilotChat.client.Message)?

---@class CopilotChat.client.Message
---@field role string
---@field content string
---@field reasoning string?
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

---@class CopilotChat.client.Resource
---@field data string
---@field name string?
---@field mimetype string?
---@field uri string?

---@class CopilotChat.client.Model
---@field provider string?
---@field id string
---@field name string
---@field tokenizer string?
---@field max_input_tokens number?
---@field max_output_tokens number?
---@field streaming boolean?
---@field tools boolean?
---@field reasoning boolean?

local log = require('plenary.log')
local constants = require('CopilotChat.constants')
local notify = require('CopilotChat.notify')
local tiktoken = require('CopilotChat.tiktoken')
local utils = require('CopilotChat.utils')
local class = utils.class

--- Constants
local RESOURCE_SHORT_FORMAT = '# %s\n```%s start_line=% end_line=%s\n%s\n```'
local RESOURCE_LONG_FORMAT = '# %s\n```%s path=%s start_line=%s end_line=%s\n%s\n```'
local CACHE_TTL = 300 -- 5 minutes

--- Get a cached value or fill it if not present
--- @param cache table: The cache table to use
--- @param key string: The key to look up in the cache
--- @param filler function: A function that returns the value to cache if not present
local function get_cached(cache, key, filler)
  local now = math.floor(os.time())
  if cache and cache[key] and cache[key .. '_expires_at'] > now then
    return cache[key]
  end

  local value = filler()
  cache[key] = value
  cache[key .. '_expires_at'] = now + CACHE_TTL
  return value
end

--- Generate resource block with line numbers, truncating if necessary
---@param content string
---@param start_line number: The starting line number
---@return string
local function generate_resource_block(content, mimetype, name, path, start_line, end_line)
  local lines = vim.split(content, '\n')
  local total_lines = #lines
  local max_length = #tostring(total_lines)
  for i, line in ipairs(lines) do
    local formatted_line_number = string.format('%' .. max_length .. 'd', i - 1 + (start_line or 1))
    lines[i] = formatted_line_number .. ': ' .. line
  end

  local updated_content = table.concat(lines, '\n')
  local filetype = utils.mimetype_to_filetype(mimetype or 'text')
  if not start_line then
    start_line = 1
  end
  if not end_line then
    end_line = start_line and (start_line + total_lines - 1) or 1
  end

  if path then
    return string.format(RESOURCE_LONG_FORMAT, name, filetype, path, start_line, end_line, updated_content)
  else
    return string.format(RESOURCE_SHORT_FORMAT, name, filetype, start_line, end_line, updated_content)
  end
end

--- Generate messages for the given selection
--- @param selection CopilotChat.select.Selection
--- @return CopilotChat.client.Message?
local function generate_selection_message(selection)
  local content = selection.content

  if not content or content == '' then
    return nil
  end

  return {
    content = generate_resource_block(
      content,
      selection.filetype,
      "User's active selection",
      selection.filename,
      selection.start_line,
      selection.end_line
    ),
    role = constants.ROLE.USER,
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
      return {
        content = generate_resource_block(resource.data, resource.mimetype, resource.uri, resource.name, 1, nil),
        role = constants.ROLE.USER,
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
      role = constants.ROLE.SYSTEM,
    })
  end

  -- Include generated messages and history
  vim.list_extend(messages, generated_messages)
  vim.list_extend(messages, history)

  -- Include user prompt if we have no history
  if not utils.empty(prompt) and utils.empty(history) then
    table.insert(messages, {
      content = prompt,
      role = constants.ROLE.USER,
    })
  end

  return messages
end

---@class CopilotChat.client.Client : Class
---@field private provider_resolver function():table<string, CopilotChat.config.providers.Provider>
---@field private provider_cache table<string, table>
---@field private current_job string?
local Client = class(function(self)
  self.provider_resolver = nil
  self.provider_cache = vim.defaulttable(function()
    return {}
  end)
  self.current_job = nil
end)

--- Get all providers from the client
---@param supported_method? string: The method to filter providers by (optional)
---@return OrderedMap<string, CopilotChat.config.providers.Provider>
function Client:get_providers(supported_method)
  local out = utils.ordered_map()

  if not self.provider_resolver then
    return out
  end

  local providers = self.provider_resolver()
  local provider_names = vim.tbl_keys(providers)
  table.sort(provider_names)

  for _, provider_name in ipairs(provider_names) do
    local provider = providers[provider_name]
    if provider and not provider.disabled and (not supported_method or provider[supported_method]) then
      out:set(provider_name, provider)
    end
  end
  return out
end

--- Set a provider resolver on the client
---@param resolver function: A function that returns a table of providers
function Client:add_providers(resolver)
  self.provider_resolver = resolver
end

--- Authenticate with GitHub and get the required headers
---@param provider_name string: The provider to authenticate with
---@return table<string, string>
function Client:authenticate(provider_name)
  local provider = self:get_providers():get(provider_name)
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
function Client:models()
  local out = {}
  local providers = self:get_providers('get_models')

  for _, provider_name in ipairs(providers:keys()) do
    local provider = providers:get(provider_name)
    for _, model in
      ipairs(get_cached(self.provider_cache[provider_name], 'models', function()
        notify.publish(notify.STATUS, 'Fetching models from ' .. provider_name)

        local ok, headers = pcall(self.authenticate, self, provider_name)
        if not ok then
          log.warn('Failed to authenticate with ' .. provider_name .. ': ' .. headers)
          return {}
        end

        local ok, models = pcall(provider.get_models, headers)
        if not ok then
          log.warn('Failed to fetch models from ' .. provider_name .. ': ' .. models)
          return {}
        end

        return models or {}
      end))
    do
      model.provider = provider_name
      if out[model.id] then
        model.id = model.id .. ':' .. provider_name
      end
      out[model.id] = model
    end
  end

  log.debug('Fetched models:', #vim.tbl_keys(out))
  return out
end

--- Get information about all providers
---@return table<string, string[]>
function Client:info()
  local out = {}
  local providers = self:get_providers('get_info')

  for _, provider_name in ipairs(providers:keys()) do
    local provider = providers:get(provider_name)
    out[provider_name] = get_cached(self.provider_cache[provider_name], 'infos', function()
      notify.publish(notify.STATUS, 'Fetching info from ' .. provider_name)

      local ok, headers = pcall(self.authenticate, self, provider_name)
      if not ok then
        log.warn('Failed to authenticate with ' .. provider_name .. ': ' .. headers)
        return {}
      end

      local ok, infos = pcall(provider.get_info, headers)
      if not ok then
        log.warn('Failed to fetch info from ' .. provider_name .. ': ' .. infos)
        return {}
      end

      return infos or {}
    end)
  end

  log.debug('Fetched provider infos:', #vim.tbl_keys(out))
  return out
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

  local models = self:models()
  local model_config = models[opts.model]
  if not model_config then
    error('Model not found: ' .. opts.model)
  end

  local provider_name = model_config.provider
  if not provider_name then
    error('Provider not found for model: ' .. opts.model)
  end
  local provider = self:get_providers():get(provider_name)
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
    tiktoken:load(tokenizer)
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
    local selection_tokens = selection_message and tiktoken:count(selection_message.content) or 0
    local prompt_tokens = tiktoken:count(prompt)
    local system_tokens = tiktoken:count(opts.system_prompt)
    local resource_tokens = #resource_messages > 0 and tiktoken:count(resource_messages[1].content) or 0
    local required_tokens = prompt_tokens + system_tokens + selection_tokens + resource_tokens

    -- Calculate how many tokens we can use for history
    local history_limit = max_tokens - required_tokens
    local history_tokens = 0
    for _, msg in ipairs(history) do
      history_tokens = history_tokens + tiktoken:count(msg.content)
    end

    -- Remove history messages until we are under the limit
    while history_tokens > history_limit and #history > 0 do
      local entry = table.remove(history, 1)
      history_tokens = history_tokens - tiktoken:count(entry.content)
    end

    -- Now add as many files as possible with remaining token budget
    local remaining_tokens = max_tokens - required_tokens - history_tokens
    for _, message in ipairs(resource_messages) do
      local tokens = tiktoken:count(message.content)
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

  local errored = nil
  local finished = false
  local token_count = 0
  local response_content_buffer = utils.string_buffer()
  local response_reasoning_buffer = utils.string_buffer()

  local function finish_stream(err, job)
    if err then
      errored = err
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
      response_content_buffer:add(out.content)
    end

    if out.reasoning then
      response_reasoning_buffer:add(out.reasoning)
    end

    if opts.on_progress then
      opts.on_progress({
        role = constants.ROLE.ASSISTANT,
        content = out.content or '',
        reasoning = out.reasoning or '',
      })
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

  if errored then
    error(errored)
    return
  end

  local response_text = response_content_buffer:tostring()
  local response_reasoning = response_reasoning_buffer:tostring()

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
    response_text = response_content_buffer:tostring()
    response_reasoning = response_reasoning_buffer:tostring()
  end

  return {
    message = {
      role = constants.ROLE.ASSISTANT,
      content = response_text,
      reasoning = response_reasoning,
      tool_calls = #tool_calls:values() > 0 and tool_calls:values() or nil,
    },
    token_count = token_count,
    token_max_count = max_tokens,
  }
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

--- @type CopilotChat.client.Client
return Client()
