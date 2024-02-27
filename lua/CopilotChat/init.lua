local log = require('plenary.log')
local Copilot = require('CopilotChat.copilot')
local Spinner = require('CopilotChat.spinner')
local prompts = require('CopilotChat.prompts')
local select = require('CopilotChat.select')
local debuginfo = require('CopilotChat.debuginfo')

local M = {}
local state = {
  copilot = nil,
  spinner = nil,
  selection = nil,
  window = {
    id = nil,
    bufnr = nil,
  },
}

local function is_copilot_reply(input)
  return vim.startswith(vim.trim(input), '**' .. M.config.name .. ':** ')
end

local function get_prompt_kind(name)
  if vim.startswith(name, 'COPILOT_') then
    return 'system'
  end

  return 'user'
end

local function find_lines_between_separator_at_cursor(bufnr, separator)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]
  local line_count = #lines
  local last_separator_line = 1
  local next_separator_line = line_count
  local pattern = '^' .. separator .. '%w*$'

  -- Find the last occurrence of the separator
  for i, line in ipairs(lines) do
    if i > cursor_line and string.find(line, pattern) then
      next_separator_line = i - 1
      break
    end
    if string.find(line, pattern) then
      last_separator_line = i + 1
    end
  end

  -- Extract everything between the last and next separator
  local result = {}
  for i = last_separator_line, next_separator_line do
    table.insert(result, lines[i])
  end

  return vim.trim(table.concat(result, '\n')), last_separator_line, next_separator_line, line_count
end

local function update_prompts(prompt)
  local prompts_to_use = M.get_prompts()

  local system_prompt = nil
  local result = string.gsub(prompt, [[/[%w_]+]], function(match)
    match = string.sub(match, 2)
    local found = prompts_to_use[match]

    if found then
      if found.kind == 'user' then
        return found.prompt
      elseif found.kind == 'system' then
        system_prompt = match
      end
    end

    return ''
  end)

  return system_prompt, result
end

local function append(str)
  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(state.window.id) then
      state.copilot:stop()
      return
    end

    local last_line = vim.api.nvim_buf_line_count(state.window.bufnr) - 1
    local last_line_content = vim.api.nvim_buf_get_lines(state.window.bufnr, -2, -1, false)
    local last_column = #last_line_content[1]
    vim.api.nvim_buf_set_text(
      state.window.bufnr,
      last_line,
      last_column,
      last_line,
      last_column,
      vim.split(str, '\n')
    )

    -- Get new position of text and update cursor
    last_line = vim.api.nvim_buf_line_count(state.window.bufnr) - 1
    last_line_content = vim.api.nvim_buf_get_lines(state.window.bufnr, -2, -1, false)
    last_column = #last_line_content[1]
    vim.api.nvim_win_set_cursor(state.window.id, { last_line + 1, last_column })
  end)
end

local function show_help()
  if not state.spinner then
    return
  end

  state.spinner:finish()

  local out = 'Press '

  for name, key in pairs(M.config.mappings) do
    if key then
      out = out .. "'" .. key .. "' to " .. name .. ', \n'
    end
  end

  state.spinner:set(out, -1)
end

local function complete()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  if col == 0 or #line == 0 then
    return
  end

  local prefix, cmp_start = unpack(vim.fn.matchstrpos(line:sub(1, col), '\\/\\k*$'))
  if not prefix then
    return
  end

  local items = {}
  local prompts_to_use = M.get_prompts()

  for name, prompt in pairs(prompts_to_use) do
    items[#items + 1] = {
      word = '/' .. name,
      kind = prompt.kind,
      info = prompt.prompt,
      detail = prompt.description or '',
      icase = 1,
      dup = 0,
      empty = 0,
    }
  end

  vim.fn.complete(cmp_start + 1, items)
end

--- Get the prompts to use.
---@param skip_system (boolean?)
function M.get_prompts(skip_system)
  local prompts_to_use = {}

  if not skip_system then
    for name, prompt in pairs(prompts) do
      prompts_to_use[name] = {
        prompt = prompt,
        kind = get_prompt_kind(name),
      }
    end
  end

  for name, prompt in pairs(M.config.prompts) do
    local val = prompt
    if type(prompt) == 'string' then
      val = {
        prompt = prompt,
        kind = get_prompt_kind(name),
      }
    elseif not val.kind then
      val.kind = get_prompt_kind(name)
    end

    prompts_to_use[name] = val
  end

  return prompts_to_use
end

--- Open the chat window.
---@param config (table | nil)
function M.open(config)
  config = vim.tbl_deep_extend('force', M.config, config or {})
  local selection = nil
  if type(config.selection) == 'function' then
    selection = config.selection()
  else
    selection = config.selection
  end
  state.selection = selection or {}

  local just_created = false

  if not state.window.bufnr or not vim.api.nvim_buf_is_valid(state.window.bufnr) then
    state.window.bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(state.window.bufnr, 'copilot-chat')
    vim.bo[state.window.bufnr].filetype = 'markdown'
    vim.treesitter.start(state.window.bufnr, 'markdown')
    just_created = true

    if config.mappings.complete then
      vim.keymap.set('i', config.mappings.complete, complete, { buffer = state.window.bufnr })
    end

    if config.mappings.reset then
      vim.keymap.set('n', config.mappings.reset, M.reset, { buffer = state.window.bufnr })
    end

    if config.mappings.close then
      vim.keymap.set('n', 'q', M.close, { buffer = state.window.bufnr })
    end

    if config.mappings.submit_prompt then
      vim.keymap.set('n', config.mappings.submit_prompt, function()
        local input, start_line, end_line, line_count =
          find_lines_between_separator_at_cursor(state.window.bufnr, M.config.separator)
        if input ~= '' and not is_copilot_reply(input) then
          -- If we are entering the input at the end, replace it
          if line_count == end_line then
            vim.api.nvim_buf_set_lines(state.window.bufnr, start_line, end_line, false, { '' })
          end
          M.ask(input, { selection = state.selection })
        end
      end, { buffer = state.window.bufnr })
    end

    if config.mappings.submit_code then
      vim.keymap.set('n', config.mappings.submit_code, function()
        if
          not state.selection
          or not state.selection.buffer
          or not state.selection.start_row
          or not state.selection.end_row
          or not vim.api.nvim_buf_is_valid(state.selection.buffer)
        then
          return
        end

        local input = find_lines_between_separator_at_cursor(state.window.bufnr, '```')
        if input ~= '' then
          vim.api.nvim_buf_set_text(
            state.selection.buffer,
            state.selection.start_row - 1,
            state.selection.start_col,
            state.selection.end_row - 1,
            state.selection.end_col,
            vim.split(input, '\n')
          )
        end
      end, { buffer = state.window.bufnr })
    end
  end

  if not state.spinner then
    state.spinner = Spinner(state.window.bufnr, M.config.name)
  end

  if not state.window.id or not vim.api.nvim_win_is_valid(state.window.id) then
    local win_opts = {
      style = 'minimal',
    }

    local layout = config.window.layout

    if layout == 'vertical' then
      win_opts.vertical = true
    elseif layout == 'horizontal' then
      win_opts.vertical = false
    elseif layout == 'float' then
      win_opts.relative = 'editor'
      win_opts.border = config.window.border
      win_opts.title = config.window.title
      win_opts.row = math.floor(vim.o.lines * 0.2)
      win_opts.col = math.floor(vim.o.columns * 0.1)
      win_opts.width = math.floor(vim.o.columns * 0.8)
      win_opts.height = math.floor(vim.o.lines * 0.6)
    end

    state.window.id = vim.api.nvim_open_win(state.window.bufnr, false, win_opts)
    vim.wo[state.window.id].wrap = true
    vim.wo[state.window.id].linebreak = true
    vim.wo[state.window.id].cursorline = true
    vim.wo[state.window.id].conceallevel = 2
    vim.wo[state.window.id].concealcursor = 'niv'

    if just_created then
      M.reset()
    end
  end

  vim.api.nvim_set_current_win(state.window.id)
end

--- Close the chat window and stop the Copilot model.
function M.close()
  if state.window.id and vim.api.nvim_win_is_valid(state.window.id) then
    vim.api.nvim_win_close(state.window.id, true)
    state.window.id = nil
  end

  if state.spinner then
    state.spinner:finish()
    state.spinner = nil
  end

  state.copilot:stop()
end

--- Toggle the chat window.
---@param config (table | nil)
function M.toggle(config)
  if state.window.id and vim.api.nvim_win_is_valid(state.window.id) then
    M.close()
  else
    M.open(config)
  end
end

--- Ask a question to the Copilot model.
---@param prompt (string)
---@param config (table | nil)
function M.ask(prompt, config)
  if not prompt then
    return
  end

  config = vim.tbl_deep_extend('force', M.config, config or {})

  local system_prompt, updated_prompt = update_prompts(prompt)
  if not system_prompt then
    system_prompt = config.system_prompt
  end

  if vim.trim(prompt) == '' then
    return
  end

  M.open(config)

  if config.clear_chat_on_new_prompt then
    M.reset()
  end

  if state.selection.prompt_extra then
    updated_prompt = updated_prompt .. ' ' .. state.selection.prompt_extra
  end

  return state.copilot:ask(updated_prompt, {
    selection = state.selection.lines,
    filetype = state.selection.filetype,
    system_prompt = system_prompt,
    model = config.model,
    temperature = config.temperature,
    on_start = function()
      state.spinner:start()
      append('**' .. M.config.name .. ':** ')
    end,
    on_done = function()
      append('\n\n' .. M.config.separator .. '\n\n')
      show_help()
    end,
    on_progress = append,
  })
end

--- Reset the chat window and show the help message.
function M.reset()
  state.copilot:reset()
  if state.window.bufnr and vim.api.nvim_buf_is_valid(state.window.bufnr) then
    vim.api.nvim_buf_set_lines(state.window.bufnr, 0, -1, true, {})
  end

  append('\n')
  show_help()
end

M.config = {
  system_prompt = prompts.COPILOT_INSTRUCTIONS,
  model = 'gpt-4',
  temperature = 0.1,
  debug = false,
  clear_chat_on_new_prompt = false,
  disable_extra_info = true,
  name = 'CopilotChat',
  separator = '---',
  prompts = {
    Explain = 'Explain how it works.',
    Tests = 'Briefly explain how selected code works then generate unit tests.',
    FixDiagnostic = {
      prompt = 'Please assist with the following diagnostic issue in file:',
      selection = select.diagnostics,
    },
  },
  selection = function()
    return select.visual() or select.line()
  end,
  window = {
    layout = 'vertical',
    width = 0.8,
    height = 0.6,
    border = 'single',
    title = 'Copilot Chat',
  },
  mappings = {
    close = 'q',
    reset = '<C-l>',
    complete = '<Tab>',
    submit_prompt = '<CR>',
    submit_code = '<C-y>',
  },
}
--- Set up the plugin
---@param config (table | nil)
--       - system_prompt: (string?).
--       - model: (string?) default: 'gpt-4'.
--       - temperature: (number?) default: 0.1.
--       - debug: (boolean?) default: false.
--       - clear_chat_on_new_prompt: (boolean?) default: false.
--       - disable_extra_info: (boolean?) default: true.
--       - name: (string?) default: 'CopilotChat'.
--       - separator: (string?) default: '---'.
--       - prompts: (table?).
--       - selection: (function | table | nil).
--       - window: (table?).
--       - mappings: (table?).
function M.setup(config)
  M.config = vim.tbl_deep_extend('force', M.config, config or {})
  state.copilot = Copilot(not M.config.disable_extra_info)
  debuginfo.setup()

  local logfile = string.format('%s/%s.log', vim.fn.stdpath('state'), 'CopilotChat.nvim')
  log.new({
    plugin = M.config.name,
    level = debug and 'trace' or 'error',
    outfile = logfile,
  }, true)
  log.logfile = logfile

  for name, prompt in pairs(M.get_prompts(true)) do
    vim.api.nvim_create_user_command('CopilotChat' .. name, function(args)
      local input = prompt.prompt
      if args.args and vim.trim(args.args) ~= '' then
        input = input .. ' ' .. args.args
      end
      M.ask(input, prompt)
    end, {
      nargs = '*',
      force = true,
      range = true,
      desc = prompt.description or ('CopilotChat.nvim ' .. name),
    })
  end

  vim.api.nvim_create_user_command('CopilotChat', function(args)
    local input = ''
    if args.args and vim.trim(args.args) ~= '' then
      input = input .. ' ' .. args.args
    end
    M.ask(input)
  end, {
    nargs = '*',
    force = true,
    range = true,
  })

  vim.api.nvim_create_user_command('CopilotChatOpen', M.open, { force = true })
  vim.api.nvim_create_user_command('CopilotChatClose', M.close, { force = true })
  vim.api.nvim_create_user_command('CopilotChatToggle', M.toggle, { force = true })
end

return M
