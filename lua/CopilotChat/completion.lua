local async = require('plenary.async')
local client = require('CopilotChat.client')
local constants = require('CopilotChat.constants')
local config = require('CopilotChat.config')
local functions = require('CopilotChat.functions')
local utils = require('CopilotChat.utils')

local M = {}

--- Get the completion info for the chat window, for use with custom completion providers
---@return table
function M.info()
  return {
    triggers = { '@', '/', '#', '$' },
    pattern = [[\%(@\|/\|#\|\$\)\S*]],
  }
end

--- Get the completion items for the chat window, for use with custom completion providers
---@return table
---@async
function M.items()
  local models = client:models()
  local prompts = config.prompts or {}
  local items = {}

  for name, prompt in pairs(prompts) do
    if type(prompt) == 'string' then
      prompt = {
        prompt = prompt,
      }
    end

    local kind = ''
    local info = ''
    if prompt.prompt then
      kind = constants.ROLE.USER
      info = prompt.prompt
    elseif prompt.system_prompt then
      kind = constants.ROLE.SYSTEM
      info = prompt.system_prompt
    end

    items[#items + 1] = {
      word = '/' .. name,
      abbr = name,
      kind = kind,
      info = info,
      menu = prompt.description or '',
      icase = 1,
      dup = 0,
      empty = 0,
    }
  end

  for id, model in pairs(models) do
    items[#items + 1] = {
      word = '$' .. id,
      abbr = id,
      kind = model.provider,
      menu = model.name,
      icase = 1,
      dup = 0,
      empty = 0,
    }
  end

  local groups = {}
  for name, tool in pairs(config.functions) do
    if tool.group then
      groups[tool.group] = groups[tool.group] or {}
      groups[tool.group][name] = tool
    end
  end
  for name, group in pairs(groups) do
    local group_tools = vim.tbl_keys(group)
    items[#items + 1] = {
      word = '@' .. name,
      abbr = name,
      kind = 'group',
      info = table.concat(group_tools, '\n'),
      menu = string.format('%s tools', #group_tools),
      icase = 1,
      dup = 0,
      empty = 0,
    }
  end
  for name, tool in pairs(config.functions) do
    items[#items + 1] = {
      word = '@' .. name,
      abbr = name,
      kind = constants.ROLE.TOOL,
      info = tool.description,
      menu = tool.group or '',
      icase = 1,
      dup = 0,
      empty = 0,
    }
  end

  local tools_to_use = functions.parse_tools(config.functions)
  for _, tool in pairs(tools_to_use) do
    local uri = config.functions[tool.name].uri
    if uri then
      local info =
        string.format('%s\n\n%s', tool.description, tool.schema and vim.inspect(tool.schema, { indent = '  ' }) or '')

      items[#items + 1] = {
        word = '#' .. tool.name,
        abbr = tool.name,
        kind = config.functions[tool.name].group or 'resource',
        info = info,
        menu = uri,
        icase = 1,
        dup = 0,
        empty = 0,
      }
    end
  end

  table.sort(items, function(a, b)
    if a.kind == b.kind then
      return a.word < b.word
    end
    return a.kind < b.kind
  end)

  return items
end

--- Trigger the completion for the chat window.
---@param without_input boolean?
function M.complete(without_input)
  local source = require('CopilotChat').get_source()
  local info = M.info()
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_get_current_line()
  local win = vim.api.nvim_get_current_win()
  local row, col = unpack(vim.api.nvim_win_get_cursor(win))

  local prefix, cmp_start = unpack(vim.fn.matchstrpos(line:sub(1, col), info.pattern))
  if not prefix then
    return
  end

  if not without_input and vim.startswith(prefix, '#') and vim.endswith(prefix, ':') then
    local found_tool = config.functions[prefix:sub(2, -2)]
    local found_schema = found_tool and functions.parse_schema(found_tool)
    if found_tool and found_schema and found_tool.uri then
      async.run(function()
        local value = functions.enter_input(found_schema, source)
        if not value then
          return
        end

        utils.schedule_main()
        vim.api.nvim_buf_set_text(bufnr, row - 1, col, row - 1, col, { value })
        vim.api.nvim_win_set_cursor(0, { row, col + #value })
      end)
    end

    return
  end

  utils.debounce('copilot_chat_complete', function()
    async.run(function()
      local items = M.items()
      utils.schedule_main()

      local row_changed = vim.api.nvim_win_get_cursor(win)[1] ~= row
      local mode = vim.api.nvim_get_mode().mode
      if row_changed or not (mode == 'i' or mode == 'ic') then
        return
      end

      vim.fn.complete(
        cmp_start + 1,
        vim.tbl_filter(function(item)
          return vim.startswith(item.word:lower(), prefix:lower())
        end, items)
      )
    end)
  end, 100)
end

--- Omnifunc for the chat window completion.
---@param findstart integer 0 or 1, decides behavior
---@param base integer findstart=0, text to match against
---@return number|table
function M.omnifunc(findstart, base)
  assert(base)
  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype

  if ft ~= 'copilot-chat' then
    return findstart == 1 and -1 or {}
  end

  M.complete(true)
  return -2 -- Return -2 to indicate that we are handling the completion asynchronously
end

--- Enable the completion for specific buffer.
---@param bufnr number: the buffer number to enable completion for
---@param autocomplete boolean: whether to enable autocomplete
function M.enable(bufnr, autocomplete)
  if autocomplete then
    vim.api.nvim_create_autocmd('TextChangedI', {
      buffer = bufnr,
      callback = function()
        local completeopt = vim.opt.completeopt:get()
        if not vim.tbl_contains(completeopt, 'noinsert') and not vim.tbl_contains(completeopt, 'noselect') then
          -- Don't trigger completion if completeopt is not set to noinsert or noselect
          return
        end

        M.complete(true)
      end,
    })

    -- Add noinsert completeopt if not present
    if vim.fn.has('nvim-0.11.0') == 1 then
      local completeopt = vim.opt.completeopt:get()
      if not vim.tbl_contains(completeopt, 'noinsert') then
        table.insert(completeopt, 'noinsert')
        vim.bo[bufnr].completeopt = table.concat(completeopt, ',')
      end
    end
  else
    -- Just set the omnifunc for the buffer
    vim.bo[bufnr].omnifunc = [[v:lua.require'CopilotChat.completion'.omnifunc]]
  end
end

return M
