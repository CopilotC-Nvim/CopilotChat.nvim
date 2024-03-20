local default_config = require('CopilotChat.config')
local log = require('plenary.log')
local Copilot = require('CopilotChat.copilot')
local Chat = require('CopilotChat.chat')
local Overlay = require('CopilotChat.overlay')
local context = require('CopilotChat.context')
local prompts = require('CopilotChat.prompts')
local debuginfo = require('CopilotChat.debuginfo')
local tiktoken = require('CopilotChat.tiktoken')

local M = {}
local plugin_name = 'CopilotChat.nvim'

--- @class CopilotChat.state
--- @field copilot CopilotChat.Copilot?
--- @field chat CopilotChat.Chat?
--- @field source CopilotChat.config.source?
--- @field config CopilotChat.config?
--- @field last_system_prompt string?
--- @field last_code_output string?
--- @field diff CopilotChat.Overlay?
--- @field system_prompt CopilotChat.Overlay?
--- @field user_selection CopilotChat.Overlay?
local state = {
  copilot = nil,
  chat = nil,
  source = nil,
  config = nil,

  -- Tracking for overlays
  last_system_prompt = nil,
  last_code_output = nil,

  -- Overlays
  diff = nil,
  system_prompt = nil,
  user_selection = nil,
}

local function blend_color_with_neovim_bg(color_name, blend)
  local color_int = vim.api.nvim_get_hl(0, { name = color_name }).fg
  local bg_int = vim.api.nvim_get_hl(0, { name = 'Normal' }).bg

  if not color_int or not bg_int then
    return
  end

  local color = { (color_int / 65536) % 256, (color_int / 256) % 256, color_int % 256 }
  local bg = { (bg_int / 65536) % 256, (bg_int / 256) % 256, bg_int % 256 }
  local r = math.floor((color[1] * blend + bg[1] * (100 - blend)) / 100)
  local g = math.floor((color[2] * blend + bg[2] * (100 - blend)) / 100)
  local b = math.floor((color[3] * blend + bg[3] * (100 - blend)) / 100)
  return string.format('#%02x%02x%02x', r, g, b)
end

local function find_lines_between_separator(lines, pattern, at_least_one)
  local line_count = #lines
  local separator_line_start = 1
  local separator_line_finish = line_count
  local found_one = false

  -- Find the last occurrence of the separator
  for i = line_count, 1, -1 do -- Reverse the loop to start from the end
    local line = lines[i]
    if string.find(line, pattern) then
      if i < (separator_line_finish + 1) and (not at_least_one or found_one) then
        separator_line_start = i + 1
        break -- Exit the loop as soon as the condition is met
      end

      found_one = true
      separator_line_finish = i - 1
    end
  end

  if at_least_one and not found_one then
    return {}, 1, 1, 0
  end

  -- Extract everything between the last and next separator
  local result = {}
  for i = separator_line_start, separator_line_finish do
    table.insert(result, lines[i])
  end

  return result, separator_line_start, separator_line_finish, line_count
end

local function update_prompts(prompt, system_prompt)
  local prompts_to_use = M.prompts()
  local try_again = false
  local result = string.gsub(prompt, [[/[%w_]+]], function(match)
    local found = prompts_to_use[string.sub(match, 2)]
    if found then
      if found.kind == 'user' then
        local out = found.prompt
        if string.match(out, [[/[%w_]+]]) then
          try_again = true
        end
        return out
      elseif found.kind == 'system' then
        system_prompt = found.prompt
        return ''
      end
    end

    return match
  end)

  if try_again then
    return update_prompts(result, system_prompt)
  end

  return system_prompt, result
end

--- Append a string to the chat window.
---@param str (string)
local function append(str)
  state.chat:append(str)
  if M.config.auto_follow_cursor then
    state.chat:follow()
  end
end

local function complete()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  if col == 0 or #line == 0 then
    return
  end

  local prefix, cmp_start = unpack(vim.fn.matchstrpos(line:sub(1, col), '\\/\\|@\\k*$'))
  if not prefix then
    return
  end

  local items = {}
  local prompts_to_use = M.prompts()

  for name, prompt in pairs(prompts_to_use) do
    items[#items + 1] = {
      word = '/' .. name,
      kind = prompt.kind,
      info = prompt.prompt,
      menu = prompt.description or '',
      icase = 1,
      dup = 0,
      empty = 0,
    }
  end

  items[#items + 1] = {
    word = '@buffers',
    kind = 'context',
    menu = 'Use all loaded buffers as context',
    icase = 1,
    dup = 0,
    empty = 0,
  }

  items[#items + 1] = {
    word = '@buffer',
    kind = 'context',
    menu = 'Use the current buffer as context',
    icase = 1,
    dup = 0,
    empty = 0,
  }

  items = vim.tbl_filter(function(item)
    return vim.startswith(item.word:lower(), prefix:lower())
  end, items)

  vim.fn.complete(cmp_start + 1, items)
end

local function get_selection()
  local bufnr = state.source.bufnr
  local winnr = state.source.winnr
  if
    state.config
    and state.config.selection
    and vim.api.nvim_buf_is_valid(bufnr)
    and vim.api.nvim_win_is_valid(winnr)
  then
    return state.config.selection(state.source) or {}
  end
  return {}
end

--- Get the prompts to use.
---@param skip_system boolean|nil
function M.prompts(skip_system)
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
---@param config CopilotChat.config?
---@param source CopilotChat.config.source?
function M.open(config, source, no_focus)
  local should_reset = config and config.window ~= nil and not vim.tbl_isempty(config.window)
  config = vim.tbl_deep_extend('force', M.config, config or {})
  state.config = config
  state.source = vim.tbl_extend('keep', source or {}, {
    bufnr = vim.api.nvim_get_current_buf(),
    winnr = vim.api.nvim_get_current_win(),
  })

  -- Exit visual mode if we are in visual mode
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<esc>', true, false, true), 'x', false)

  -- Recreate the window if the layout has changed
  if should_reset then
    M.close()
  end

  state.chat:open(config)
  if not no_focus then
    state.chat:focus()
    state.chat:follow()
  end
end

--- Close the chat window and stop the Copilot model.
function M.close()
  state.copilot:stop()
  state.chat:close()
end

--- Toggle the chat window.
---@param config CopilotChat.config|nil
---@param source CopilotChat.config.source?
function M.toggle(config, source)
  if state.chat:visible() then
    M.close()
  else
    M.open(config, source)
  end
end

--- Ask a question to the Copilot model.
---@param prompt string
---@param config CopilotChat.config|nil
---@param source CopilotChat.config.source?
function M.ask(prompt, config, source)
  M.open(config, source, true)

  config = vim.tbl_deep_extend('force', M.config, config or {})
  local selection = get_selection()
  state.chat:focus()

  prompt = prompt or ''
  local system_prompt, updated_prompt = update_prompts(prompt, config.system_prompt)
  if vim.trim(prompt) == '' then
    return
  end

  if config.clear_chat_on_new_prompt then
    M.reset()
  end

  state.last_system_prompt = system_prompt
  local filetype = selection.filetype or vim.bo[state.source.bufnr].filetype
  local filename = selection.filename or vim.api.nvim_buf_get_name(state.source.bufnr)
  if selection.prompt_extra then
    updated_prompt = updated_prompt .. ' ' .. selection.prompt_extra
  end

  if state.copilot:stop() then
    append('\n\n' .. config.separator .. '\n\n')
  end

  append(updated_prompt)
  append('\n\n**' .. config.name .. '** ' .. config.separator .. '\n\n')
  state.chat:follow()

  local selected_context = config.context
  if string.find(prompt, '@buffers') then
    selected_context = 'buffers'
  elseif string.find(prompt, '@buffer') then
    selected_context = 'buffer'
  end
  updated_prompt = string.gsub(updated_prompt, '@buffers?%s*', '')

  local function on_error(err)
    vim.schedule(function()
      append('\n\n**Error** ' .. config.separator .. '\n\n')
      append('```\n' .. err .. '\n```')
      append('\n\n' .. config.separator .. '\n\n')
      state.chat:finish()
    end)
  end

  context.find_for_query(state.copilot, {
    context = selected_context,
    prompt = updated_prompt,
    selection = selection.lines,
    filename = filename,
    filetype = filetype,
    bufnr = state.source.bufnr,
    on_error = on_error,
    on_done = function(embeddings)
      state.copilot:ask(updated_prompt, {
        selection = selection.lines,
        embeddings = embeddings,
        filename = filename,
        filetype = filetype,
        system_prompt = system_prompt,
        model = config.model,
        temperature = config.temperature,
        on_error = on_error,
        on_done = function(response, token_count)
          vim.schedule(function()
            append('\n\n' .. config.separator .. '\n\n')
            if tiktoken.available() and token_count and token_count > 0 then
              state.chat:finish(token_count .. ' tokens used')
            else
              state.chat:finish()
            end
            if config.callback then
              config.callback(response)
            end
          end)
        end,
        on_progress = function(token)
          vim.schedule(function()
            append(token)
          end)
        end,
      })
    end,
  })
end

--- Reset the chat window and show the help message.
function M.reset()
  state.copilot:reset()
  vim.schedule(function()
    state.chat:clear()
    append('\n')
    state.chat:finish()
  end)
end

--- Save the chat history to a file.
---@param name string?
---@param history_path string?
function M.save(name, history_path)
  if not name or vim.trim(name) == '' then
    name = 'default'
  else
    name = vim.trim(name)
  end

  history_path = history_path or M.config.history_path
  state.copilot:save(name, history_path)
end

--- Load the chat history from a file.
---@param name string?
---@param history_path string?
function M.load(name, history_path)
  if not name or vim.trim(name) == '' then
    name = 'default'
  else
    name = vim.trim(name)
  end

  history_path = history_path or M.config.history_path
  state.copilot:reset()
  state.chat:clear()

  local history = state.copilot:load(name, history_path)
  for i, message in ipairs(history) do
    if message.role == 'user' then
      if i > 1 then
        append('\n\n' .. M.config.separator .. '\n\n')
      else
        append('\n')
      end
      append(message.content)
    elseif message.role == 'assistant' then
      append('\n\n**' .. M.config.name .. '** ' .. M.config.separator .. '\n\n')
      append(message.content)
    end
  end

  if #history == 0 then
    append('\n')
  else
    append('\n\n' .. M.config.separator .. '\n')
  end

  state.chat:finish()
  M.open()
end

--- Enables/disables debug
---@param debug boolean
function M.debug(debug)
  M.config.debug = debug
  local logfile = string.format('%s/%s.log', vim.fn.stdpath('state'), plugin_name)
  log.new({
    plugin = plugin_name,
    level = debug and 'debug' or 'info',
    outfile = logfile,
  }, true)
  log.logfile = logfile
end

--- Set up the plugin
---@param config CopilotChat.config|nil
function M.setup(config)
  M.config = vim.tbl_deep_extend('force', default_config, config or {})
  state.copilot = Copilot(M.config.proxy, M.config.allow_insecure)
  local mark_ns = vim.api.nvim_create_namespace('copilot-chat-marks')
  local hl_ns = vim.api.nvim_create_namespace('copilot-chat-highlights')

  vim.api.nvim_set_hl(hl_ns, '@diff.plus', { bg = blend_color_with_neovim_bg('DiffAdd', 20) })
  vim.api.nvim_set_hl(hl_ns, '@diff.minus', { bg = blend_color_with_neovim_bg('DiffDelete', 20) })
  vim.api.nvim_set_hl(hl_ns, '@diff.delta', { bg = blend_color_with_neovim_bg('DiffChange', 20) })

  local overlay_help = M.config.mappings.close
      and ("'" .. M.config.mappings.close .. "' to close overlay.'")
    or ''

  state.diff = Overlay(
    'copilot-diff',
    mark_ns,
    hl_ns,
    "'"
      .. M.config.mappings.close
      .. "' to close diff.\n'"
      .. M.config.mappings.accept_diff
      .. "' to accept diff.\n"
      .. overlay_help,
    function(bufnr)
      if M.config.mappings.close then
        vim.keymap.set('n', M.config.mappings.close, function()
          state.diff:restore(state.chat.winnr, state.chat.bufnr)
        end, { buffer = bufnr })
      end
      if M.config.mappings.accept_diff then
        vim.keymap.set('n', M.config.mappings.accept_diff, function()
          local current = state.last_code_output
          if not current then
            return
          end

          local selection = get_selection()
          if not selection.start_row or not selection.end_row then
            return
          end

          local lines = vim.split(current, '\n')
          if #lines > 0 then
            vim.api.nvim_buf_set_text(
              state.source.bufnr,
              selection.start_row - 1,
              selection.start_col - 1,
              selection.end_row - 1,
              selection.end_col,
              lines
            )
          end
        end, { buffer = bufnr })
      end
    end
  )

  state.system_prompt = Overlay(
    'copilot-system-prompt',
    mark_ns,
    hl_ns,
    overlay_help,
    function(bufnr)
      if M.config.mappings.close then
        vim.keymap.set('n', M.config.mappings.close, function()
          state.system_prompt:restore(state.chat.winnr, state.chat.bufnr)
        end, { buffer = bufnr })
      end
    end
  )

  state.user_selection = Overlay(
    'copilot-user-selection',
    mark_ns,
    hl_ns,
    overlay_help,
    function(bufnr)
      if M.config.mappings.close then
        vim.keymap.set('n', M.config.mappings.close, function()
          state.user_selection:restore(state.chat.winnr, state.chat.bufnr)
        end, { buffer = bufnr })
      end
    end
  )

  local chat_help = ''
  if M.config.show_help then
    local chat_keys = vim.tbl_keys(M.config.mappings)
    table.sort(chat_keys, function(a, b)
      return M.config.mappings[a] < M.config.mappings[b]
    end)

    for _, name in ipairs(chat_keys) do
      local key = M.config.mappings[name]
      if key then
        chat_help = chat_help .. "'" .. key .. "' to " .. name:gsub('_', ' ') .. '\n'
      end
    end

    chat_help = chat_help
      .. '@'
      .. M.config.mappings.complete
      .. ' or /'
      .. M.config.mappings.complete
      .. ' for different completion options.'
  end

  state.chat = Chat(mark_ns, chat_help, function(bufnr)
    if M.config.mappings.complete then
      vim.keymap.set('i', M.config.mappings.complete, complete, { buffer = bufnr })
    end

    if M.config.mappings.reset then
      vim.keymap.set('n', M.config.mappings.reset, M.reset, { buffer = bufnr })
    end

    if M.config.mappings.close then
      vim.keymap.set('n', M.config.mappings.close, M.close, { buffer = bufnr })
    end

    if M.config.mappings.submit_prompt then
      vim.keymap.set('n', M.config.mappings.submit_prompt, function()
        local chat_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local lines, start_line, end_line, line_count =
          find_lines_between_separator(chat_lines, M.config.separator .. '$')
        local input = vim.trim(table.concat(lines, '\n'))
        if input ~= '' then
          -- If we are entering the input at the end, replace it
          if line_count == end_line then
            vim.api.nvim_buf_set_lines(bufnr, start_line, end_line, false, { '' })
          end
          M.ask(input, state.config, state.source)
        end
      end, { buffer = bufnr })
    end

    if M.config.mappings.accept_diff then
      vim.keymap.set('n', M.config.mappings.accept_diff, function()
        local selection = get_selection()
        if not selection.start_row or not selection.end_row then
          return
        end

        local chat_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local section_lines =
          find_lines_between_separator(chat_lines, M.config.separator .. '$', true)
        local lines = find_lines_between_separator(section_lines, '^```%w*$', true)
        if #lines > 0 then
          vim.api.nvim_buf_set_text(
            state.source.bufnr,
            selection.start_row - 1,
            selection.start_col - 1,
            selection.end_row - 1,
            selection.end_col,
            lines
          )
        end
      end, { buffer = bufnr })
    end

    if M.config.mappings.show_diff then
      vim.keymap.set('n', M.config.mappings.show_diff, function()
        local selection = get_selection()

        if not selection or not selection.start_row or not selection.end_row then
          return
        end

        local chat_lines = vim.api.nvim_buf_get_lines(state.chat.bufnr, 0, -1, false)
        local section_lines =
          find_lines_between_separator(chat_lines, M.config.separator .. '$', true)
        local lines =
          table.concat(find_lines_between_separator(section_lines, '^```%w*$', true), '\n')
        if vim.trim(lines) ~= '' then
          state.last_code_output = lines

          local filetype = selection.filetype or vim.bo[state.source.bufnr].filetype

          local diff = tostring(vim.diff(selection.lines, lines, {
            result_type = 'unified',
            ignore_blank_lines = true,
            ignore_whitespace = true,
            ignore_whitespace_change = true,
            ignore_whitespace_change_at_eol = true,
            ignore_cr_at_eol = true,
            algorithm = 'myers',
            ctxlen = #selection.lines,
          }))

          state.diff:show(diff, filetype, 'diff', state.chat.winnr)
        end
      end, {
        buffer = bufnr,
      })
    end

    if M.config.mappings.show_system_prompt then
      vim.keymap.set('n', M.config.mappings.show_system_prompt, function()
        local prompt = state.last_system_prompt or M.config.system_prompt
        if not prompt then
          return
        end

        state.system_prompt:show(prompt, 'markdown', 'markdown', state.chat.winnr)
      end, { buffer = bufnr })
    end

    if M.config.mappings.show_user_selection then
      vim.keymap.set('n', M.config.mappings.show_user_selection, function()
        local selection = get_selection()
        if not selection or not selection.start_row or not selection.end_row then
          return
        end

        local filetype = selection.filetype or vim.bo[state.source.bufnr].filetype
        local lines = selection.lines
        if vim.trim(lines) ~= '' then
          state.user_selection:show(lines, filetype, filetype, state.chat.winnr)
        end
      end, { buffer = bufnr })
    end

    append('\n')
    state.chat:finish()
  end)

  tiktoken.setup()
  debuginfo.setup()
  M.debug(M.config.debug)

  for name, prompt in pairs(M.prompts(true)) do
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
  vim.api.nvim_create_user_command('CopilotChatReset', M.reset, { force = true })

  local function complete_load()
    local options = vim.tbl_map(function(file)
      return vim.fn.fnamemodify(file, ':t:r')
    end, vim.fn.glob(M.config.history_path .. '/*', true, true))

    if not vim.tbl_contains(options, 'default') then
      table.insert(options, 1, 'default')
    end

    return options
  end

  vim.api.nvim_create_user_command('CopilotChatSave', function(args)
    M.save(args.args)
  end, { nargs = '*', force = true, complete = complete_load })
  vim.api.nvim_create_user_command('CopilotChatLoad', function(args)
    M.load(args.args)
  end, { nargs = '*', force = true, complete = complete_load })
end

return M
