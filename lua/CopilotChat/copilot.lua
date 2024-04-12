---@class CopilotChat.copilot.embed
---@field filename string
---@field filetype string
---@field prompt string?
---@field content string?

---@class CopilotChat.copilot.ask.opts
---@field selection string?
---@field embeddings table<CopilotChat.copilot.embed>?
---@field filename string?
---@field filetype string?
---@field start_row number?
---@field end_row number?
---@field system_prompt string?
---@field model string?
---@field temperature number?
---@field on_done nil|fun(response: string, token_count: number?):nil
---@field on_progress nil|fun(response: string):nil
---@field on_error nil|fun(err: string):nil

---@class CopilotChat.copilot.embed.opts
---@field model string?
---@field chunk_size number?
---@field on_done nil|fun(results: table):nil
---@field on_error nil|fun(err: string):nil

---@class CopilotChat.Copilot
---@field ask fun(self: CopilotChat.Copilot, prompt: string, opts: CopilotChat.copilot.ask.opts):nil
---@field embed fun(self: CopilotChat.Copilot, inputs: table, opts: CopilotChat.copilot.embed.opts):nil
---@field stop fun(self: CopilotChat.Copilot):boolean
---@field reset fun(self: CopilotChat.Copilot):boolean
---@field save fun(self: CopilotChat.Copilot, name: string, path: string):nil
---@field load fun(self: CopilotChat.Copilot, name: string, path: string):table
---@field running fun(self: CopilotChat.Copilot):boolean

local log = require('plenary.log')
local curl = require('plenary.curl')
local utils = require('CopilotChat.utils')
local class = utils.class
local join = utils.join
local temp_file = utils.temp_file
local prompts = require('CopilotChat.prompts')
local tiktoken = require('CopilotChat.tiktoken')
local max_tokens = 8192
local version_headers = {
  ['editor-version'] = 'Neovim/'
    .. vim.version().major
    .. '.'
    .. vim.version().minor
    .. '.'
    .. vim.version().patch,
  ['editor-plugin-version'] = 'CopilotChat.nvim/2.0.0',
  ['user-agent'] = 'CopilotChat.nvim/2.0.0',
}

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
    hex = hex .. hex_chars:sub(math.random(1, #hex_chars), math.random(1, #hex_chars))
  end
  return hex
end

local function find_config_path()
  local config = vim.fn.expand('$XDG_CONFIG_HOME')
  if config and vim.fn.isdirectory(config) > 0 then
    return config
  elseif vim.fn.has('win32') > 0 then
    config = vim.fn.expand('~/AppData/Local')
    if vim.fn.isdirectory(config) > 0 then
      return config
    end
  else
    config = vim.fn.expand('~/.config')
    if vim.fn.isdirectory(config) > 0 then
      return config
    end
  end
end

local function get_cached_token()
  -- loading token from the environment only in GitHub Codespaces
  local token = os.getenv('GITHUB_TOKEN')
  local codespaces = os.getenv('CODESPACES')
  if token and codespaces then
    return token
  end

  -- loading token from the file
  local config_path = find_config_path()
  if not config_path then
    return nil
  end
  local file_path = find_config_path() .. '/github-copilot/hosts.json'
  if vim.fn.filereadable(file_path) == 0 then
    return nil
  end
  local userdata = vim.fn.json_decode(vim.fn.readfile(file_path))
  return userdata['github.com'].oauth_token
end

local function generate_selection_message(filename, filetype, start_row, end_row, selection)
  if not selection or selection == '' then
    return ''
  end

  local content = selection
  if start_row > 0 then
    local lines = vim.split(selection, '\n')
    local total_lines = #lines
    local max_length = #tostring(total_lines)
    for i, line in ipairs(lines) do
      local formatted_line_number = string.format('%' .. max_length .. 'd', i - 1 + start_row)
      lines[i] = formatted_line_number .. ': ' .. line
    end
    content = table.concat(lines, '\n')
  end

  return string.format('Active selection: `%s`\n```%s\n%s\n```', filename, filetype, content)
end

local function generate_embeddings_message(embeddings)
  local files = {}
  for _, embedding in ipairs(embeddings) do
    local filename = embedding.filename
    if not files[filename] then
      files[filename] = {}
    end
    table.insert(files[filename], embedding)
  end

  local out = {
    header = 'Open files:\n',
    files = {},
  }

  for filename, group in pairs(files) do
    table.insert(
      out.files,
      string.format(
        'File: `%s`\n```%s\n%s\n```\n',
        filename,
        group[1].filetype,
        table.concat(
          vim.tbl_map(function(e)
            return vim.trim(e.content)
          end, group),
          '\n'
        )
      )
    )
  end
  return out
end

local function generate_ask_request(
  history,
  prompt,
  embeddings,
  selection,
  system_prompt,
  model,
  temperature
)
  local messages = {}

  if system_prompt ~= '' then
    table.insert(messages, {
      content = system_prompt,
      role = 'system',
    })
  end

  for _, message in ipairs(history) do
    table.insert(messages, message)
  end

  if embeddings and #embeddings.files > 0 then
    table.insert(messages, {
      content = embeddings.header .. table.concat(embeddings.files, ''),
      role = 'system',
    })
  end

  if selection ~= '' then
    table.insert(messages, {
      content = selection,
      role = 'system',
    })
  end

  table.insert(messages, {
    content = prompt,
    role = 'user',
  })

  return {
    intent = true,
    model = model,
    n = 1,
    stream = true,
    temperature = temperature,
    top_p = 1,
    messages = messages,
  }
end

local function generate_embedding_request(inputs, model)
  return {
    input = vim.tbl_map(function(input)
      local out = ''
      if input.prompt then
        out = input.prompt .. '\n'
      end
      if input.content then
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

local function generate_headers(token, sessionid, machineid)
  local headers = {
    ['authorization'] = 'Bearer ' .. token,
    ['x-request-id'] = uuid(),
    ['vscode-sessionid'] = sessionid,
    ['vscode-machineid'] = machineid,
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

local Copilot = class(function(self, proxy, allow_insecure)
  self.proxy = proxy
  self.allow_insecure = allow_insecure
  self.github_token = get_cached_token()
  self.history = {}
  self.token = nil
  self.token_count = 0
  self.sessionid = nil
  self.machineid = machine_id()
  self.current_job = nil
end)

function Copilot:with_auth(on_done, on_error)
  if not self.github_token then
    local msg =
      'No GitHub token found, please use `:Copilot setup` to set it up from copilot.vim or copilot.lua'
    log.error(msg)
    if on_error then
      on_error(msg)
    end
    return
  end

  if
    not self.token or (self.token.expires_at and self.token.expires_at <= math.floor(os.time()))
  then
    local sessionid = uuid() .. tostring(math.floor(os.time() * 1000))

    local url = 'https://api.github.com/copilot_internal/v2/token'
    local headers = {
      ['authorization'] = 'token ' .. self.github_token,
      ['accept'] = 'application/json',
    }
    for key, value in pairs(version_headers) do
      headers[key] = value
    end

    curl.get(url, {
      headers = headers,
      proxy = self.proxy,
      insecure = self.allow_insecure,
      on_error = function(err)
        err = 'Failed to get response: ' .. vim.inspect(err)
        log.error(err)
        if on_error then
          on_error(err)
        end
      end,
      callback = function(response)
        if response.status ~= 200 then
          local msg = 'Failed to authenticate: ' .. tostring(response.status)
          log.error(msg)
          if on_error then
            on_error(msg)
          end
          return
        end

        self.sessionid = sessionid
        self.token = vim.json.decode(response.body)
        on_done()
      end,
    })
  else
    on_done()
  end
end

--- Ask a question to Copilot
---@param prompt string: The prompt to send to Copilot
---@param opts CopilotChat.copilot.ask.opts: Options for the request
function Copilot:ask(prompt, opts)
  opts = opts or {}
  local embeddings = opts.embeddings or {}
  local filename = opts.filename or ''
  local filetype = opts.filetype or ''
  local selection = opts.selection or ''
  local start_row = opts.start_row or 0
  local end_row = opts.end_row or 0
  local system_prompt = opts.system_prompt or prompts.COPILOT_INSTRUCTIONS
  local model = opts.model or 'gpt-4'
  local temperature = opts.temperature or 0.1
  local on_done = opts.on_done
  local on_progress = opts.on_progress
  local on_error = opts.on_error

  log.debug('System prompt: ' .. system_prompt)
  log.debug('Prompt: ' .. prompt)
  log.debug('Embeddings: ' .. #embeddings)
  log.debug('Filename: ' .. filename)
  log.debug('Filetype: ' .. filetype)
  log.debug('Selection: ' .. selection)
  log.debug('Model: ' .. model)
  log.debug('Temperature: ' .. temperature)

  -- If we already have running job, cancel it and notify the user
  if self.current_job then
    self:stop()
  end

  local selection_message =
    generate_selection_message(filename, filetype, start_row, end_row, selection)
  local embeddings_message = generate_embeddings_message(embeddings)

  -- Count tokens
  self.token_count = self.token_count + tiktoken.count(prompt)

  local current_count = 0
  current_count = current_count + tiktoken.count(system_prompt)
  current_count = current_count + tiktoken.count(selection_message)

  if #embeddings_message.files > 0 then
    local filtered_files = {}
    current_count = current_count + tiktoken.count(embeddings_message.header)
    for _, file in ipairs(embeddings_message.files) do
      local file_count = current_count + tiktoken.count(file)
      if file_count + self.token_count < max_tokens then
        current_count = file_count
        table.insert(filtered_files, file)
      end
    end
    embeddings_message.files = filtered_files
  end

  local url = 'https://api.githubcopilot.com/chat/completions'
  local body = vim.json.encode(
    generate_ask_request(
      self.history,
      prompt,
      embeddings_message,
      selection_message,
      system_prompt,
      model,
      temperature
    )
  )

  -- Add the prompt to history after we have encoded the request
  table.insert(self.history, {
    content = prompt,
    role = 'user',
  })

  local errored = false
  local full_response = ''

  self:with_auth(function()
    local headers = generate_headers(self.token.token, self.sessionid, self.machineid)
    self.current_job = curl
      .post(url, {
        headers = headers,
        body = temp_file(body),
        proxy = self.proxy,
        insecure = self.allow_insecure,
        on_error = function(err)
          err = 'Failed to get response: ' .. vim.inspect(err)
          log.error(err)
          if self.current_job and on_error then
            on_error(err)
          end
        end,
        stream = function(err, line)
          if not line or errored then
            return
          end

          if err or vim.startswith(line, '{"error"') then
            err = 'Failed to get response: ' .. (err and vim.inspect(err) or line)
            errored = true
            log.error(err)
            if self.current_job and on_error then
              on_error(err)
            end
            return
          end

          line = line:gsub('data: ', '')
          if line == '' then
            return
          elseif line == '[DONE]' then
            log.trace('Full response: ' .. full_response)
            self.token_count = self.token_count + tiktoken.count(full_response)

            if self.current_job and on_done then
              on_done(full_response, self.token_count + current_count)
            end

            table.insert(self.history, {
              content = full_response,
              role = 'assistant',
            })
            return
          end

          local ok, content = pcall(vim.json.decode, line, {
            luanil = {
              object = true,
              array = true,
            },
          })

          if not ok then
            err = 'Failed parse response: \n' .. line .. '\n' .. vim.inspect(content)
            log.error(err)
            return
          end

          if not content.choices or #content.choices == 0 then
            return
          end

          content = content.choices[1].delta.content
          if not content then
            return
          end

          if self.current_job and on_progress then
            on_progress(content)
          end

          -- Collect full response incrementally so we can insert it to history later
          full_response = full_response .. content
        end,
      })
      :after(function()
        self.current_job = nil
      end)
  end, on_error)
end

--- Generate embeddings for the given inputs
---@param inputs table<CopilotChat.copilot.embed>: The inputs to embed
---@param opts CopilotChat.copilot.embed.opts: Options for the request
function Copilot:embed(inputs, opts)
  opts = opts or {}
  local model = opts.model or 'copilot-text-embedding-ada-002'
  local chunk_size = opts.chunk_size or 15
  local on_done = opts.on_done
  local on_error = opts.on_error

  if not inputs or #inputs == 0 then
    if on_done then
      on_done({})
    end
    return
  end

  local url = 'https://api.githubcopilot.com/embeddings'

  local chunks = {}
  for i = 1, #inputs, chunk_size do
    table.insert(chunks, vim.list_slice(inputs, i, i + chunk_size - 1))
  end

  local jobs = {}
  for _, chunk in ipairs(chunks) do
    local body = vim.json.encode(generate_embedding_request(chunk, model))

    table.insert(jobs, function(resolve)
      local headers = generate_headers(self.token.token, self.sessionid, self.machineid)
      curl.post(url, {
        headers = headers,
        body = temp_file(body),
        proxy = self.proxy,
        insecure = self.allow_insecure,
        on_error = function(err)
          err = 'Failed to get response: ' .. vim.inspect(err)
          log.error(err)
          resolve()
        end,
        callback = function(response)
          if not response then
            resolve()
            return
          end

          if response.status ~= 200 then
            local err = 'Failed to get response: ' .. vim.inspect(response)
            log.error(err)
            resolve()
            return
          end

          local ok, content = pcall(vim.json.decode, response.body, {
            luanil = {
              object = true,
              array = true,
            },
          })

          if not ok then
            local err = vim.inspect(content)
            log.error('Failed parse response: ' .. err)
            resolve()
            return
          end

          resolve(content.data)
        end,
      })
    end)
  end

  self:with_auth(function()
    join(function(results)
      local out = {}
      for chunk_i, chunk_result in ipairs(results) do
        if chunk_result then
          for _, embedding in ipairs(chunk_result) do
            local input = chunks[chunk_i][embedding.index + 1]
            table.insert(out, vim.tbl_extend('keep', input, embedding))
          end
        end
      end

      if on_done then
        on_done(out)
      end
    end, jobs)
  end, on_error)
end

--- Stop the running job
function Copilot:stop()
  if self.current_job then
    local job = self.current_job
    self.current_job = nil
    job:shutdown()
    return true
  end

  return false
end

--- Reset the history and stop any running job
function Copilot:reset()
  local stopped = self:stop()
  self.history = {}
  self.token_count = 0
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
