local client = require('CopilotChat.client')
local constants = require('CopilotChat.constants')
local functions = require('CopilotChat.functions')
local notify = require('CopilotChat.notify')
local files = require('CopilotChat.utils.files')
local utils = require('CopilotChat.utils')

local WORD = '([^%s:]+)'
local WORD_NO_INPUT = '([^%s]+)'
local WORD_WITH_INPUT_QUOTED = WORD .. ':`([^`]+)`'
local WORD_WITH_INPUT_UNQUOTED = WORD .. ':?([^%s`]*)'

--- Find custom instructions in the current working directory.
---@param cwd string
---@return table
local function find_custom_instructions(cwd)
  local out = {}
  local copilot_instructions_path = vim.fs.joinpath(cwd, '.github', 'copilot-instructions.md')
  local copilot_instructions = files.read_file(copilot_instructions_path)
  if copilot_instructions then
    table.insert(out, {
      filename = copilot_instructions_path,
      content = vim.trim(copilot_instructions),
    })
  end
  return out
end

local M = {}

--- List available prompts.
---@return table<string, CopilotChat.config.prompts.Prompt>
function M.list_prompts()
  local config = require('CopilotChat.config')
  local prompts_to_use = {}

  for name, prompt in pairs(config.prompts) do
    local val = prompt
    if type(prompt) == 'string' then
      val = {
        prompt = prompt,
      }
    end

    prompts_to_use[name] = val
  end

  return prompts_to_use
end

--- Resolve enabled tools from the prompt.
---@param prompt string?
---@param config CopilotChat.config.Shared?
---@return table<CopilotChat.client.Tool>, string
function M.resolve_tools(prompt, config)
  config, prompt = M.resolve_prompt(prompt, config)

  local tools = {}
  for _, tool in ipairs(functions.parse_tools(config.functions)) do
    tools[tool.name] = tool
  end

  local enabled_tools = {}
  local tool_matches = utils.to_table(config.tools)

  -- Check for @tool pattern to find enabled tools
  prompt = prompt:gsub('@' .. WORD, function(match)
    for name, tool in pairs(config.functions) do
      if name == match or tool.group == match then
        table.insert(tool_matches, match)
        return ''
      end
    end
    return '@' .. match
  end)
  for _, match in ipairs(tool_matches) do
    for name, tool in pairs(config.functions) do
      if name == match or tool.group == match then
        table.insert(enabled_tools, tools[name])
      end
    end
  end

  return enabled_tools, prompt
end

--- Call and resolve function calls from the prompt.
---@param prompt string?
---@param config CopilotChat.config.Shared?
---@return table<CopilotChat.client.Resource>, table<string>, table<string>, string
---@async
function M.resolve_functions(prompt, config)
  config, prompt = M.resolve_prompt(prompt, config)

  local chat = require('CopilotChat').chat
  local source = chat:get_source()

  local tools = {}
  for _, tool in ipairs(functions.parse_tools(config.functions)) do
    tools[tool.name] = tool
  end

  if config.resources then
    local resources = utils.to_table(config.resources)
    local lines = utils.split_lines(prompt)
    for i = #resources, 1, -1 do
      local resource = resources[i]
      table.insert(lines, 1, '#' .. resource)
    end
    prompt = table.concat(lines, '\n')
  end

  local resolved_resources = {}
  local resolved_tools = {}
  local resolved_stickies = {}
  local tool_calls = {}

  utils.schedule_main()
  for _, message in ipairs(chat:get_messages()) do
    if message.tool_calls then
      for _, tool_call in ipairs(message.tool_calls) do
        table.insert(tool_calls, tool_call)
      end
    end
  end

  local resource_matches = {}

  -- Check for #word:`input` pattern
  for word, input in prompt:gmatch('#' .. WORD_WITH_INPUT_QUOTED) do
    local pattern = string.format('#%s:`%s`', word, input)
    table.insert(resource_matches, {
      pattern = pattern,
      word = word,
      input = input,
    })
  end

  -- Check for #word:input pattern
  for word, input in prompt:gmatch('#' .. WORD_WITH_INPUT_UNQUOTED) do
    local pattern = utils.empty(input) and string.format('#%s', word) or string.format('#%s:%s', word, input)
    table.insert(resource_matches, {
      pattern = pattern,
      word = word,
      input = input,
    })
  end

  -- Check for ##word:input pattern
  for word in prompt:gmatch('##' .. WORD_NO_INPUT) do
    local pattern = string.format('##%s', word)
    table.insert(resource_matches, {
      pattern = pattern,
      word = word,
    })
  end

  -- Resolve each function reference
  local function expand_function(name, input)
    notify.publish(notify.STATUS, 'Running function: ' .. name)

    local tool_id = nil
    if not utils.empty(tool_calls) then
      for _, tool_call in ipairs(tool_calls) do
        if tool_call.name == name and vim.trim(tool_call.id) == vim.trim(input) then
          input = utils.empty(tool_call.arguments) and {} or utils.json_decode(tool_call.arguments)
          tool_id = tool_call.id
          break
        end
      end
    end

    local tool = config.functions[name]
    if not tool then
      -- Check if input matches uri
      for tool_name, tool_spec in pairs(config.functions) do
        if tool_spec.uri then
          local match = functions.match_uri(name, tool_spec.uri)
          if match then
            name = tool_name
            tool = tool_spec
            input = match
            break
          end
        end
      end
    end
    if not tool then
      return nil
    end
    if not tool_id and not tool.uri then
      return nil
    end

    local schema = tools[name] and tools[name].schema or nil
    local ok, output
    if config.stop_on_function_failure then
      output = tool.resolve(functions.parse_input(input, schema), source)
      ok = true
    else
      ok, output = pcall(tool.resolve, functions.parse_input(input, schema), source)
    end

    local result = ''
    if not ok then
      result = utils.make_string(output)
    else
      for _, content in ipairs(output) do
        if content then
          local content_out = nil
          if content.uri then
            if
              not vim.tbl_contains(resolved_resources, function(resource)
                return resource.uri == content.uri
              end, { predicate = true })
            then
              content_out = '##' .. content.uri
              table.insert(resolved_resources, content)
            end

            if tool_id then
              table.insert(resolved_stickies, '##' .. content.uri)
            end
          else
            content_out = content.data
          end

          if content_out then
            if not utils.empty(result) then
              result = result .. '\n'
            end
            result = result .. content_out
          end
        end
      end
    end

    if tool_id then
      table.insert(resolved_tools, {
        id = tool_id,
        result = result,
      })

      return ''
    end

    return result
  end

  -- Resolve and process all tools
  for _, match in ipairs(resource_matches) do
    if not utils.empty(match.pattern) then
      local out = expand_function(match.word, match.input)
      if out == nil then
        out = match.pattern
      end
      out = out:gsub('%%', '%%%%') -- Escape percent signs for gsub
      prompt = prompt:gsub(vim.pesc(match.pattern), out, 1)
    end
  end

  return resolved_resources, resolved_tools, resolved_stickies, prompt
end

--- Resolve the final prompt and config from prompt template.
---@param prompt string?
---@param config CopilotChat.config.Shared?
---@return CopilotChat.config.prompts.Prompt, string
---@async
function M.resolve_prompt(prompt, config)
  local chat = require('CopilotChat').chat
  local source = chat:get_source()

  if prompt == nil then
    utils.schedule_main()
    local message = chat:get_message(constants.ROLE.USER)
    if message then
      prompt = message.content
    end
  end

  local prompts_to_use = M.list_prompts()
  local depth = 0
  local MAX_DEPTH = 10

  local function resolve(inner_config, inner_prompt)
    if depth >= MAX_DEPTH then
      return inner_config, inner_prompt
    end
    depth = depth + 1

    inner_prompt = string.gsub(inner_prompt, '/' .. WORD, function(match)
      local p = prompts_to_use[match]
      if p then
        local resolved_config, resolved_prompt = resolve(p, p.prompt or '')
        inner_config = vim.tbl_deep_extend('force', inner_config, resolved_config)
        return resolved_prompt
      end

      return '/' .. match
    end)

    depth = depth - 1
    return inner_config, inner_prompt
  end

  config = vim.tbl_deep_extend('force', require('CopilotChat.config'), config or {})
  config, prompt = resolve(config, prompt or '')

  if config.system_prompt then
    if config.prompts[config.system_prompt] then
      -- Name references are good for making system prompt auto sticky
      config.system_prompt = config.prompts[config.system_prompt].system_prompt
    end

    local custom_instructions = vim.trim(require('CopilotChat.instructions.custom_instructions'))
    for _, instruction in ipairs(find_custom_instructions(source.cwd())) do
      config.system_prompt = vim.trim(config.system_prompt)
        .. '\n'
        .. custom_instructions:gsub('{FILENAME}', instruction.filename):gsub('{CONTENT}', instruction.content)
    end

    config.system_prompt = vim.trim(config.system_prompt) .. '\n' .. config.prompts.COPILOT_BASE.system_prompt
    config.system_prompt = vim.trim(config.system_prompt)
      .. '\n'
      .. vim.trim(require('CopilotChat.instructions.tool_use'))

    if config.diff == 'unified' then
      config.system_prompt = vim.trim(config.system_prompt)
        .. '\n'
        .. vim.trim(require('CopilotChat.instructions.edit_file_unified'))
    else
      config.system_prompt = vim.trim(config.system_prompt)
        .. '\n'
        .. vim.trim(require('CopilotChat.instructions.edit_file_block'))
    end

    config.system_prompt = config.system_prompt:gsub('{OS_NAME}', vim.uv.os_uname().sysname)
    config.system_prompt = config.system_prompt:gsub('{LANGUAGE}', config.language)
    config.system_prompt = config.system_prompt:gsub('{DIR}', source.cwd())
  end

  return config, prompt
end

--- Resolve the model from the prompt.
---@param prompt string?
---@param config CopilotChat.config.Shared?
---@return string, string
---@async
function M.resolve_model(prompt, config)
  config, prompt = M.resolve_prompt(prompt, config)
  local models = vim.tbl_keys(client:models())

  local selected_model = config.model or ''
  prompt = prompt:gsub('%$' .. WORD, function(match)
    if vim.tbl_contains(models, match) then
      selected_model = match
      return ''
    end
    return '$' .. match
  end)

  return selected_model, prompt
end

return M
