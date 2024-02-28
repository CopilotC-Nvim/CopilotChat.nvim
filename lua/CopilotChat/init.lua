local log = require('plenary.log')
local Copilot = require('CopilotChat.copilot')
local Chat = require('CopilotChat.chat')
local prompts = require('CopilotChat.prompts')
local select = require('CopilotChat.select')
local debuginfo = require('CopilotChat.debuginfo')

local M = {}
local plugin_name = 'CopilotChat.nvim'
local state = {
  copilot = nil,
  chat = nil,
  selection = nil,
  window = nil,
}

function CopilotChatFoldExpr(lnum, separator)
  local line = vim.fn.getline(lnum)
  vim.print(line)
  if string.match(line, separator .. '$') then
    return '>1'
  end

  return '='
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
        system_prompt = found.prompt
      end
    end

    return ''
  end)

  return system_prompt, result
end

local function append(str)
  vim.schedule(function()
    local last_line, last_column = state.chat:append(str)

    if not state.window or not vim.api.nvim_win_is_valid(state.window) then
      state.copilot:stop()
      return
    end

    vim.api.nvim_win_set_cursor(state.window, { last_line + 1, last_column })
  end)
end

local function show_help()
  if not state.chat then
    return
  end

  local out = 'Press '
  for name, key in pairs(M.config.mappings) do
    if key then
      out = out .. "'" .. key .. "' to " .. name .. ', '
    end
  end

  state.chat.spinner:finish()
  state.chat.spinner:set(out, -1)
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
  local function get_prompt_kind(name)
    return vim.startswith(name, 'COPILOT_') and 'system' or 'user'
  end

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
  local should_reset = config and config.window ~= nil and not vim.tbl_isempty(config.window)

  config = vim.tbl_deep_extend('force', M.config, config or {})
  local selection = nil
  if type(config.selection) == 'function' then
    selection = config.selection()
  else
    selection = config.selection
  end
  state.selection = selection or {}

  local just_created = false

  if not state.chat or not state.chat:valid() then
    state.chat = Chat(plugin_name)
    just_created = true

    if config.mappings.complete then
      vim.keymap.set('i', config.mappings.complete, complete, { buffer = state.chat.bufnr })
    end

    if config.mappings.reset then
      vim.keymap.set('n', config.mappings.reset, M.reset, { buffer = state.chat.bufnr })
    end

    if config.mappings.close then
      vim.keymap.set('n', 'q', M.close, { buffer = state.chat.bufnr })
    end

    if config.mappings.submit_prompt then
      vim.keymap.set('n', config.mappings.submit_prompt, function()
        local input, start_line, end_line, line_count =
          find_lines_between_separator_at_cursor(state.chat.bufnr, config.separator)
        if input ~= '' and not vim.startswith(vim.trim(input), '**' .. config.name .. ':**') then
          -- If we are entering the input at the end, replace it
          if line_count == end_line then
            vim.api.nvim_buf_set_lines(state.chat.bufnr, start_line, end_line, false, { '' })
          end
          M.ask(input, { selection = state.selection })
        end
      end, { buffer = state.chat.bufnr })
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

        local input = find_lines_between_separator_at_cursor(state.chat.bufnr, '```')
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
      end, { buffer = state.chat.bufnr })
    end
  end

  -- Recreate the window if the layout has changed
  if should_reset then
    M.close()
  end

  if not state.window or not vim.api.nvim_win_is_valid(state.window) then
    local win_opts = {
      style = 'minimal',
    }

    local layout = config.window.layout

    if layout == 'vertical' then
      win_opts.vertical = true
    elseif layout == 'horizontal' then
      win_opts.vertical = false
    elseif layout == 'float' then
      win_opts.relative = config.window.relative
      win_opts.border = config.window.border
      win_opts.title = config.window.title
      win_opts.footer = config.window.footer
      win_opts.row = config.window.row or math.floor(vim.o.lines * ((1 - config.window.height) / 2))
      win_opts.col = config.window.col
        or math.floor(vim.o.columns * ((1 - config.window.width) / 2))
      win_opts.width = math.floor(vim.o.columns * config.window.width)
      win_opts.height = math.floor(vim.o.lines * config.window.height)
    end

    state.window = vim.api.nvim_open_win(state.chat.bufnr, false, win_opts)
    vim.wo[state.window].wrap = true
    vim.wo[state.window].linebreak = true
    vim.wo[state.window].cursorline = true
    vim.wo[state.window].conceallevel = 2
    vim.wo[state.window].concealcursor = 'niv'
    if config.show_folds then
      vim.wo[state.window].foldcolumn = '1'
      vim.wo[state.window].foldmethod = 'expr'
      vim.wo[state.window].foldexpr = "v:lua.CopilotChatFoldExpr(v:lnum, '"
        .. config.separator
        .. "')"
    else
      vim.wo[state.window].foldcolumn = '0'
    end

    if just_created then
      M.reset()
    end
  end

  vim.api.nvim_set_current_win(state.window)
end

--- Close the chat window and stop the Copilot model.
function M.close()
  state.copilot:stop()

  if state.chat then
    state.chat.spinner:finish()
  end

  if state.window and vim.api.nvim_win_is_valid(state.window) then
    vim.api.nvim_win_close(state.window, true)
    state.window = nil
  end
end

--- Toggle the chat window.
---@param config (table | nil)
function M.toggle(config)
  if state.window and vim.api.nvim_win_is_valid(state.window) then
    M.close()
  else
    M.open(config)
  end
end

--- Ask a question to the Copilot model.
---@param prompt (string)
---@param config (table | nil)
function M.ask(prompt, config)
  M.open(config)

  if not prompt or prompt == '' then
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

  if config.clear_chat_on_new_prompt then
    M.reset()
  end

  if state.selection.prompt_extra then
    updated_prompt = updated_prompt .. ' ' .. state.selection.prompt_extra
  end

  local finish = false
  if config.show_system_prompt then
    finish = true
    append(' **System prompt** ---\n```\n' .. system_prompt .. '```\n')
  end
  if config.show_user_selection and state.selection and state.selection.lines ~= '' then
    finish = true
    append(
      ' **Selection** ---\n```'
        .. (state.selection.filetype or '')
        .. '\n'
        .. state.selection.lines
        .. '\n```'
    )
  end
  if finish then
    append('\n' .. config.separator .. '\n\n')
  end

  append(updated_prompt)

  return state.copilot:ask(updated_prompt, {
    selection = state.selection.lines,
    filetype = state.selection.filetype,
    system_prompt = system_prompt,
    model = config.model,
    temperature = config.temperature,
    on_start = function()
      append('\n\n **' .. config.name .. '** ' .. config.separator .. '\n\n')
      state.chat.spinner:start()
    end,
    on_done = function()
      append('\n\n' .. config.separator .. '\n\n')
      show_help()
    end,
    on_progress = function(token)
      append(token)
    end,
  })
end

--- Reset the chat window and show the help message.
function M.reset()
  state.copilot:reset()
  if state.chat then
    state.chat:clear()
    append('\n')
    show_help()
  end
end

M.config = {
  system_prompt = prompts.COPILOT_INSTRUCTIONS,
  model = 'gpt-4',
  temperature = 0.1,
  debug = false, -- Enable debug logging
  show_user_selection = true, -- Shows user selection in chat
  show_system_prompt = false, -- Shows system prompt in chat
  show_folds = true, -- Shows folds for sections in chat
  clear_chat_on_new_prompt = false, -- Clears chat on every new prompt
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
    layout = 'vertical', -- 'vertical', 'horizontal', 'float'
    -- Options for float layout
    relative = 'editor', -- 'editor', 'win', 'cursor', 'mouse'
    border = 'single', -- 'none', single', 'double', 'rounded', 'solid', 'shadow'
    width = 0.8, -- fractional width of parent
    height = 0.6, -- fractional height of parent
    row = nil, -- row position of the window, default is centered
    col = nil, -- column position of the window, default is centered
    title = 'Copilot Chat',
    footer = nil,
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
  state.copilot = Copilot()
  debuginfo.setup()

  local logfile = string.format('%s/%s.log', vim.fn.stdpath('state'), plugin_name)
  log.new({
    plugin = plugin_name,
    level = M.config.debug and 'trace' or 'warn',
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
      desc = prompt.description or (plugin_name .. ' ' .. name),
    })

    if prompt.mapping then
      vim.keymap.set({ 'n', 'v' }, prompt.mapping, function()
        M.ask(prompt.prompt, prompt)
      end, { desc = prompt.description or (plugin_name .. ' ' .. name) })
    end
  end

  vim.api.nvim_create_user_command('CopilotChat', function(args)
    M.ask(args.args)
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
