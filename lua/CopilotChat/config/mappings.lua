local async = require('plenary.async')
local copilot = require('CopilotChat')
local utils = require('CopilotChat.utils')

---@param chat CopilotChat.ui.Chat
---@return CopilotChat.ui.Diff.Diff?
local function get_diff(chat)
  local config = chat.config
  local block = chat:get_closest_block()

  -- If no block found, return nil
  if not block then
    return nil
  end

  -- Initialize variables with selection if available
  local header = block.header
  local selection = copilot.get_selection(config)
  local reference = selection and selection.content
  local start_line = selection and selection.start_line
  local end_line = selection and selection.end_line
  local filename = selection and selection.filename
  local filetype = selection and selection.filetype
  local bufnr = selection and selection.bufnr

  -- If we have header info, use it as source of truth
  if header.start_line and header.end_line then
    -- Try to find matching buffer and window
    bufnr = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local win_buf = vim.api.nvim_win_get_buf(win)
      if utils.filename_same(vim.api.nvim_buf_get_name(win_buf), header.filename) then
        bufnr = win_buf
        break
      end
    end

    filename = header.filename
    filetype = header.filetype or vim.filetype.match({ filename = filename })
    start_line = header.start_line
    end_line = header.end_line

    -- If we found a valid buffer, get the reference content
    if bufnr and utils.buf_valid(bufnr) then
      reference =
        table.concat(vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false), '\n')
      filetype = vim.bo[bufnr].filetype
    end
  end

  -- If we are missing info, there is no diff to be made
  if not start_line or not end_line or not filename then
    return nil
  end

  return {
    change = block.content,
    reference = reference or '',
    filetype = filetype or '',
    filename = filename,
    start_line = start_line,
    end_line = end_line,
    bufnr = bufnr,
  }
end

---@param winnr number
---@param bufnr number
---@param start_line number
---@param end_line number
---@param config CopilotChat.config.shared
local function jump_to_diff(winnr, bufnr, start_line, end_line, config)
  pcall(vim.api.nvim_buf_set_mark, bufnr, '<', start_line, 0, {})
  pcall(vim.api.nvim_buf_set_mark, bufnr, '>', end_line, 0, {})
  pcall(vim.api.nvim_buf_set_mark, bufnr, '[', start_line, 0, {})
  pcall(vim.api.nvim_buf_set_mark, bufnr, ']', end_line, 0, {})
  pcall(vim.api.nvim_win_set_cursor, winnr, { start_line, 0 })
  copilot.update_selection(config)
end

---@param diff CopilotChat.ui.Diff.Diff?
---@param config CopilotChat.config.shared
local function apply_diff(diff, config)
  if not diff or not diff.bufnr then
    return
  end

  local winnr = vim.fn.win_findbuf(diff.bufnr)[1]
  if not winnr then
    return
  end

  local lines = vim.split(diff.change, '\n', { trimempty = false })
  vim.api.nvim_buf_set_lines(diff.bufnr, diff.start_line - 1, diff.end_line, false, lines)
  jump_to_diff(winnr, diff.bufnr, diff.start_line, diff.start_line + #lines - 1, config)
end

---@class CopilotChat.config.mapping
---@field normal string?
---@field insert string?
---@field detail string?
---@field callback fun(overlay: CopilotChat.ui.Overlay, diff: CopilotChat.ui.Diff, chat: CopilotChat.ui.Chat, source: CopilotChat.source)

---@class CopilotChat.config.mapping.yank_diff : CopilotChat.config.mapping
---@field register string?

---@class CopilotChat.config.mapping.show_diff : CopilotChat.config.mapping
---@field full_diff boolean?

---@class CopilotChat.config.mappings
---@field complete CopilotChat.config.mapping?
---@field close CopilotChat.config.mapping?
---@field reset CopilotChat.config.mapping?
---@field submit_prompt CopilotChat.config.mapping?
---@field toggle_sticky CopilotChat.config.mapping?
---@field accept_diff CopilotChat.config.mapping?
---@field jump_to_diff CopilotChat.config.mapping?
---@field quickfix_diffs CopilotChat.config.mapping?
---@field yank_diff CopilotChat.config.mapping.yank_diff?
---@field show_diff CopilotChat.config.mapping.show_diff?
---@field show_info CopilotChat.config.mapping?
---@field show_context CopilotChat.config.mapping?
---@field show_help CopilotChat.config.mapping?
return {
  complete = {
    insert = '<Tab>',
    callback = function(overlay, diff, chat)
      copilot.trigger_complete(true)
    end,
  },

  close = {
    normal = 'q',
    insert = '<C-c>',
    callback = function(overlay, diff, chat)
      copilot.close()
    end,
  },

  reset = {
    normal = '<C-l>',
    insert = '<C-l>',
    callback = function(overlay, diff, chat)
      copilot.reset()
    end,
  },

  submit_prompt = {
    normal = '<CR>',
    insert = '<C-s>',
    callback = function(overlay, diff, chat)
      local section = chat:get_closest_section()
      if not section or section.answer then
        return
      end

      copilot.ask(section.content)
    end,
  },

  toggle_sticky = {
    detail = 'Makes line under cursor sticky or deletes sticky line.',
    normal = 'gr',
    callback = function(overlay, diff, chat)
      local section = chat:get_closest_section()
      if not section or section.answer then
        return
      end

      local current_line = vim.trim(vim.api.nvim_get_current_line())
      if current_line == '' then
        return
      end

      local cursor = vim.api.nvim_win_get_cursor(0)
      local cur_line = cursor[1]
      vim.api.nvim_buf_set_lines(chat.bufnr, cur_line - 1, cur_line, false, {})

      if vim.startswith(current_line, '> ') then
        return
      end

      local lines = vim.split(section.content, '\n')
      local insert_line = 1
      local first_one = true

      for i = insert_line, #lines do
        local line = lines[i]
        if line and vim.trim(line) ~= '' then
          if vim.startswith(line, '> ') then
            first_one = false
          else
            break
          end
        elseif i >= 2 then
          break
        end

        insert_line = insert_line + 1
      end

      insert_line = section.start_line + insert_line - 1
      local to_insert = first_one and { '> ' .. current_line, '' } or { '> ' .. current_line }
      vim.api.nvim_buf_set_lines(chat.bufnr, insert_line - 1, insert_line - 1, false, to_insert)
      vim.api.nvim_win_set_cursor(0, cursor)
    end,
  },

  accept_diff = {
    normal = '<C-y>',
    insert = '<C-y>',
    callback = function(overlay, diff, chat, source)
      apply_diff(get_diff(chat), chat.config)
    end,
  },

  jump_to_diff = {
    normal = 'gj',
    callback = function(overlay, diff, chat, source)
      if not source or not source.winnr or not vim.api.nvim_win_is_valid(source.winnr) then
        return
      end

      local diff = get_diff(chat)
      if not diff then
        return
      end

      local diff_bufnr = diff.bufnr

      -- If buffer is not found, try to load it
      if not diff_bufnr then
        diff_bufnr = vim.fn.bufadd(diff.filename)
        vim.fn.bufload(diff_bufnr)
      end

      source.bufnr = diff_bufnr
      vim.api.nvim_win_set_buf(source.winnr, diff_bufnr)

      jump_to_diff(source.winnr, diff_bufnr, diff.start_line, diff.end_line, chat.config)
    end,
  },

  quickfix_answers = {
    normal = 'gqa',
    callback = function(overlay, diff, chat)
      local items = {}
      for i, section in ipairs(chat.sections) do
        if section.answer then
          local prev_section = chat.sections[i - 1]
          local text = ''
          if prev_section then
            text = vim.trim(
              table.concat(
                vim.api.nvim_buf_get_lines(
                  chat.bufnr,
                  prev_section.start_line - 1,
                  prev_section.end_line,
                  false
                ),
                ' '
              )
            )
          end

          table.insert(items, {
            bufnr = chat.bufnr,
            lnum = section.start_line,
            end_lnum = section.end_line,
            text = text,
          })
        end
      end

      vim.fn.setqflist(items)
      vim.cmd('copen')
    end,
  },

  quickfix_diffs = {
    normal = 'gqd',
    callback = function(overlay, diff, chat)
      local selection = copilot.get_selection(chat.config)
      local items = {}

      for _, section in ipairs(chat.sections) do
        for _, block in ipairs(section.blocks) do
          local header = block.header

          if not header.start_line and selection then
            header.filename = selection.filename .. ' (selection)'
            header.start_line = selection.start_line
            header.end_line = selection.end_line
          end

          local text = string.format('%s (%s)', header.filename, header.filetype)
          if header.start_line and header.end_line then
            text = text .. string.format(' [lines %d-%d]', header.start_line, header.end_line)
          end

          table.insert(items, {
            bufnr = chat.bufnr,
            lnum = block.start_line,
            end_lnum = block.end_line,
            text = text,
          })
        end
      end

      vim.fn.setqflist(items)
      vim.cmd('copen')
    end,
  },

  yank_diff = {
    normal = 'gy',
    register = '"', -- Default register to use for yanking
    callback = function(overlay, diff, chat)
      local block = chat:get_closest_block()
      if not block then
        return
      end

      vim.fn.setreg(copilot.config.mappings.yank_diff.register, block.content)
    end,
  },

  show_diff = {
    normal = 'gd',
    full_diff = false, -- Show full diff instead of unified diff when showing diff window
    callback = function(overlay, diff, chat)
      local content = get_diff(chat)
      if not content then
        return
      end

      diff:show(content, chat.winnr, copilot.config.mappings.show_diff.full_diff)
    end,
  },

  show_info = {
    normal = 'gi',
    callback = function(overlay, diff, chat)
      local section = chat:get_closest_section()
      if not section or section.answer then
        return
      end

      local lines = {}
      local prompt, config = copilot.resolve_prompts(section.content, chat.config)
      local system_prompt = config.system_prompt

      async.run(function()
        local _, selected_agent = pcall(copilot.resolve_agent, prompt, config)
        local _, selected_model = pcall(copilot.resolve_model, prompt, config)

        async.util.scheduler()
        table.insert(lines, '**Logs**: `' .. chat.config.log_path .. '`')
        table.insert(lines, '**History**: `' .. chat.config.history_path .. '`')
        table.insert(lines, '**Temp Files**: `' .. vim.fn.fnamemodify(os.tmpname(), ':h') .. '`')
        table.insert(lines, '')

        if selected_model then
          table.insert(lines, '**Model**: `' .. selected_model .. '`')
          table.insert(lines, '')
        end

        if selected_agent then
          table.insert(lines, '**Agent**: `' .. selected_agent .. '`')
          table.insert(lines, '')
        end

        if system_prompt then
          table.insert(lines, '**System Prompt**')
          table.insert(lines, '```')
          for _, line in ipairs(vim.split(vim.trim(system_prompt), '\n')) do
            table.insert(lines, line)
          end
          table.insert(lines, '```')
          table.insert(lines, '')
        end

        overlay:show(vim.trim(table.concat(lines, '\n')) .. '\n', chat.winnr, 'markdown')
      end)
    end,
  },

  show_context = {
    normal = 'gc',
    callback = function(overlay, diff, chat)
      local section = chat:get_closest_section()
      if not section or section.answer then
        return
      end

      local lines = {}

      local selection = copilot.get_selection(chat.config)
      if selection then
        table.insert(lines, '**Selection**')
        table.insert(lines, '```' .. selection.filetype)
        for _, line in ipairs(vim.split(selection.content, '\n')) do
          table.insert(lines, line)
        end
        table.insert(lines, '```')
        table.insert(lines, '')
      end

      async.run(function()
        local embeddings = {}
        if section and not section.answer then
          embeddings = copilot.resolve_embeddings(section.content, chat.config)
        end

        for _, embedding in ipairs(embeddings) do
          local embed_lines = vim.split(embedding.content, '\n')
          local preview = vim.list_slice(embed_lines, 1, math.min(10, #embed_lines))
          local header = string.format('**%s** (%s lines)', embedding.filename, #embed_lines)
          if #embed_lines > 10 then
            header = header .. ' (truncated)'
          end

          table.insert(lines, header)
          table.insert(lines, '```' .. embedding.filetype)
          for _, line in ipairs(preview) do
            table.insert(lines, line)
          end
          table.insert(lines, '```')
          table.insert(lines, '')
        end

        async.util.scheduler()
        overlay:show(vim.trim(table.concat(lines, '\n')) .. '\n', chat.winnr, 'markdown')
      end)
    end,
  },

  show_help = {
    normal = 'gh',
    callback = function(overlay, diff, chat)
      local chat_help = '**`Special tokens`**\n'
      chat_help = chat_help .. '`@<agent>` to select an agent\n'
      chat_help = chat_help .. '`#<context>` to select a context\n'
      chat_help = chat_help .. '`#<context>:<input>` to select input for context\n'
      chat_help = chat_help .. '`/<prompt>` to select a prompt\n'
      chat_help = chat_help .. '`$<model>` to select a model\n'
      chat_help = chat_help .. '`> <text>` to make a sticky prompt (copied to next prompt)\n'

      chat_help = chat_help .. '\n**`Mappings`**\n'
      local chat_keys = vim.tbl_keys(copilot.config.mappings)
      table.sort(chat_keys, function(a, b)
        a = copilot.config.mappings[a]
        a = a.normal or a.insert
        b = copilot.config.mappings[b]
        b = b.normal or b.insert
        return a < b
      end)
      for _, name in ipairs(chat_keys) do
        if name ~= 'close' then
          local info = utils.key_to_info(name, copilot.config.mappings[name], '`')
          if info ~= '' then
            chat_help = chat_help .. info .. '\n'
          end
        end
      end
      overlay:show(chat_help, chat.winnr, 'markdown')
    end,
  },
}
