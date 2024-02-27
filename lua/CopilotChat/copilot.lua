local log = require('plenary.log')
local curl = require('plenary.curl')
local class = require('CopilotChat.utils').class
local prompts = require('CopilotChat.prompts')

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

local function get_cached_token()
  local userdata =
    vim.fn.json_decode(vim.fn.readfile(vim.fn.expand('~/.config/github-copilot/hosts.json')))
  return userdata['github.com'].oauth_token
end

local function generate_request(history, selection, filetype, system_prompt, model, temperature)
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

  if selection ~= '' then
    -- Insert the active selection before last prompt
    table.insert(messages, #messages, {
      content = '\nActive selection:\n```' .. selection .. '\n' .. filetype .. '\n```',
      role = 'system',
    })
  end

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

local function generate_headers(token, sessionid, machineid)
  return {
    ['authorization'] = 'Bearer ' .. token,
    ['x-request-id'] = uuid(),
    ['vscode-sessionid'] = sessionid,
    ['machineid'] = machineid,
    ['editor-version'] = 'vscode/1.85.1',
    ['editor-plugin-version'] = 'copilot-chat/0.12.2023120701',
    ['openai-organization'] = 'github-copilot',
    ['openai-intent'] = 'conversation-panel',
    ['content-type'] = 'application/json',
    ['user-agent'] = 'GitHubCopilotChat/0.12.2023120701',
  }
end

local function authenticate(github_token)
  local url = 'https://api.github.com/copilot_internal/v2/token'
  local headers = {
    authorization = 'token ' .. github_token,
    accept = 'application/json',
    ['editor-version'] = 'vscode/1.85.1',
    ['editor-plugin-version'] = 'copilot-chat/0.12.2023120701',
    ['user-agent'] = 'GitHubCopilotChat/0.12.2023120701',
  }

  local sessionid = uuid() .. tostring(math.floor(os.time() * 1000))
  local response = curl.get(url, { headers = headers })

  if response.status ~= 200 then
    return nil, nil, response.status
  end

  local token = vim.json.decode(response.body)
  return sessionid, token, nil
end

local Copilot = class(function(self, show_extra_info)
  self.github_token = get_cached_token()
  self.show_extra_info = show_extra_info or false
  self.history = {}
  self.token = nil
  self.sessionid = nil
  self.machineid = machine_id()
  self.current_job = nil
  self.current_job_on_cancel = nil
end)

--- Ask a question to Copilot
---@param prompt string: The prompt to send to Copilot
---@param opts table: Options for the request
function Copilot:ask(prompt, opts)
  opts = opts or {}
  local selection = opts.selection or ''
  local filetype = opts.filetype or ''
  local system_prompt = opts.system_prompt or prompts.COPILOT_INSTRUCTIONS
  local model = opts.model or 'gpt-4'
  local temperature = opts.temperature or 0.1
  local on_start = opts.on_start
  local on_done = opts.on_done
  local on_progress = opts.on_progress
  local on_error = opts.on_error

  if
    not self.token or (self.token.expires_at and self.token.expires_at <= math.floor(os.time()))
  then
    local sessionid, token, err = authenticate(self.github_token)
    if err then
      log.error('Failed to authenticate: ' .. tostring(err))
      if on_error then
        on_error(err)
      end
      return
    else
      self.sessionid = sessionid
      self.token = token
    end
  end

  log.debug('System prompt: ' .. system_prompt)
  log.debug('Prompt: ' .. prompt)
  log.debug('Selection: ' .. selection)
  log.debug('Filetype: ' .. filetype)
  log.debug('Model: ' .. model)
  log.debug('Temperature: ' .. temperature)

  if self.show_extra_info and on_progress then
    on_progress('SYSTEM PROMPT:\n```\n' .. system_prompt .. '```\n')

    if selection ~= '' then
      on_progress('CODE:\n```' .. filetype .. '\n' .. selection .. '\n```')
    end

    on_done('')
  end

  table.insert(self.history, {
    content = prompt,
    role = 'user',
  })

  -- If we already have running job, cancel it and notify the user
  if self.current_job then
    self:stop()
  end

  -- Notify the user about current prompt
  if on_progress then
    on_progress(prompt)
  end
  if on_done then
    on_done(prompt)
  end

  if on_start then
    on_start()
  end

  local url = 'https://api.githubcopilot.com/chat/completions'
  local headers = generate_headers(self.token.token, self.sessionid, self.machineid)
  local data =
    generate_request(self.history, selection, filetype, system_prompt, model, temperature)

  local full_response = ''

  self.current_job_on_cancel = on_done
  self.current_job = curl
    .post(url, {
      headers = headers,
      body = vim.json.encode(data),
      stream = function(err, line)
        if err then
          log.error('Failed to stream response: ' .. tostring(err))
          on_error(err)
          return
        end

        if not line then
          return
        end

        line = line:gsub('data: ', '')
        if line == '' then
          return
        elseif line == '[DONE]' then
          log.debug('Full response: ' .. full_response)
          if on_done then
            on_done(full_response)
          end

          table.insert(self.history, {
            content = full_response,
            role = 'system',
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
          log.error('Failed parse response: ' .. tostring(err))
          on_error(content)
          return
        end

        if not content.choices or #content.choices == 0 then
          return
        end

        content = content.choices[1].delta.content
        if not content then
          return
        end

        log.debug('Token: ' .. content)
        if on_progress then
          on_progress(content)
        end

        -- Collect full response incrementally so we can insert it to history later
        full_response = full_response .. content
      end,
    })
    :after(function()
      self.current_job = nil
    end)

  return self.current_job
end

--- Stop the running job
function Copilot:stop()
  if self.current_job then
    self.current_job:shutdown()
    self.current_job = nil
    if self.current_job_on_cancel then
      self.current_job_on_cancel('job cancelled')
      self.current_job_on_cancel = nil
    end
  end
end

--- Reset the history and stop any running job
function Copilot:reset()
  self.history = {}
  self:stop()
end

return Copilot
