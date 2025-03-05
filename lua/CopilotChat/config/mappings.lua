---@class CopilotChat.ui.Diff.Diff
---@field change string
---@field reference string
---@field filename string
---@field filetype string
---@field start_line number
---@field end_line number
---@field bufnr number?

local async = require('plenary.async')
local copilot = require('CopilotChat')
local utils = require('CopilotChat.utils')

---@param block CopilotChat.ui.Chat.Section.Block?
---@return CopilotChat.ui.Diff.Diff?
local function get_diff(block)
  -- If no block found, return nil
  if not block then
    return nil
  end

  -- Initialize variables with selection if available
  local header = block.header
  local selection = copilot.get_selection()
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

--- Prepare a buffer for applying a diff
---@param diff CopilotChat.ui.Diff.Diff?
---@param source CopilotChat.source?
---@return CopilotChat.ui.Diff.Diff?
local function prepare_diff_buffer(diff, source)
  if not diff then
    return diff
  end

  local diff_bufnr = diff.bufnr

  -- If buffer is not found, try to load it
  if not diff_bufnr then
    -- Try to find matching buffer first
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if utils.filename_same(vim.api.nvim_buf_get_name(buf), diff.filename) then
        diff_bufnr = buf
        break
      end
    end

    -- If still not found, create a new buffer
    if not diff_bufnr then
      diff_bufnr = vim.fn.bufadd(diff.filename)
      vim.fn.bufload(diff_bufnr)
    end

    diff.bufnr = diff_bufnr
  end

  -- If source exists, update it to point to the diff buffer
  if source and source.winnr and vim.api.nvim_win_is_valid(source.winnr) then
    source.bufnr = diff_bufnr
    vim.api.nvim_win_set_buf(source.winnr, diff_bufnr)
  end

  return diff
end

---@class CopilotChat.config.mapping
---@field normal string?
---@field insert string?
---@field callback fun(source: CopilotChat.source)

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
    callback = function()
      copilot.trigger_complete(true)
    end,
  },

  close = {
    normal = 'q',
    insert = '<C-c>',
    callback = function()
      copilot.close()
    end,
  },

  reset = {
    normal = '<C-l>',
    insert = '<C-l>',
    callback = function()
      copilot.reset()
    end,
  },

  submit_prompt = {
    normal = '<CR>',
    insert = '<C-s>',
    callback = function()
      local section = copilot.chat:get_closest_section()
      if not section or section.answer then
        return
      end

      copilot.ask(section.content)
    end,
  },

  toggle_sticky = {
    normal = 'gr',
    callback = function()
      local section = copilot.chat:get_closest_section()
      if not section or section.answer then
        return
      end

      local current_line = vim.trim(vim.api.nvim_get_current_line())
      if current_line == '' then
        return
      end

      local cursor = vim.api.nvim_win_get_cursor(0)
      local cur_line = cursor[1]
      vim.api.nvim_buf_set_lines(copilot.chat.bufnr, cur_line - 1, cur_line, false, {})

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
      vim.api.nvim_buf_set_lines(
        copilot.chat.bufnr,
        insert_line - 1,
        insert_line - 1,
        false,
        to_insert
      )
      vim.api.nvim_win_set_cursor(0, cursor)
    end,
  },

  accept_diff = {
    normal = '<C-y>',
    insert = '<C-y>',
    callback = function(source)
      local diff_data = get_diff(copilot.chat:get_closest_block())
      diff_data = prepare_diff_buffer(diff_data, source)
      if diff_data then
        local lines = vim.split(diff_data.change, '\n', { trimempty = false })
        vim.api.nvim_buf_set_lines(
          diff_data.bufnr,
          diff_data.start_line - 1,
          diff_data.end_line,
          false,
          lines
        )
        copilot.set_selection(
          diff_data.bufnr,
          diff_data.start_line,
          diff_data.start_line + #lines - 1
        )
      end
    end,
  },

  jump_to_diff = {
    normal = 'gj',
    callback = function(source)
      local diff_data = get_diff(copilot.chat:get_closest_block())
      diff_data = prepare_diff_buffer(diff_data, source)
      if diff_data then
        copilot.set_selection(diff_data.bufnr, diff_data.start_line, diff_data.end_line)
      end
    end,
  },

  quickfix_answers = {
    normal = 'gqa',
    callback = function()
      local items = {}
      for i, section in ipairs(copilot.chat.sections) do
        if section.answer then
          local prev_section = copilot.chat.sections[i - 1]
          local text = ''
          if prev_section then
            text = prev_section.content
          end

          table.insert(items, {
            bufnr = copilot.chat.bufnr,
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
    callback = function()
      local selection = copilot.get_selection()
      local items = {}

      for _, section in ipairs(copilot.chat.sections) do
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
            bufnr = copilot.chat.bufnr,
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
    callback = function()
      local block = copilot.chat:get_closest_block()
      if not block then
        return
      end

      vim.fn.setreg(copilot.config.mappings.yank_diff.register, block.content)
    end,
  },

  show_diff = {
    normal = 'gd',
    full_diff = false, -- Show full diff instead of unified diff when showing diff window
    callback = function()
      local diff = get_diff(copilot.chat:get_closest_block())
      if not diff then
        return
      end

      local opts = {
        filetype = diff.filetype,
        syntax = 'diff',
      }

      if copilot.config.mappings.show_diff.full_diff then
        -- Create modified version by applying the change
        local modified = {}
        if utils.buf_valid(diff.bufnr) then
          modified = vim.api.nvim_buf_get_lines(diff.bufnr, 0, -1, false)
        end
        local change_lines = vim.split(diff.change, '\n')

        -- Replace the lines in the modified content
        if #modified > 0 then
          local start_idx = diff.start_line - 1
          local end_idx = diff.end_line - 1
          for _ = start_idx, end_idx do
            table.remove(modified, start_idx)
          end
          for i, line in ipairs(change_lines) do
            table.insert(modified, start_idx + i - 1, line)
          end
        else
          modified = change_lines
        end

        opts.text = table.concat(modified, '\n')

        opts.on_show = function()
          vim.cmd('diffthis')
          vim.api.nvim_set_current_win(vim.fn.bufwinid(diff.bufnr))
          vim.api.nvim_win_set_cursor(0, { diff.start_line, 0 })
          vim.cmd('diffthis')
          vim.api.nvim_set_current_win(copilot.chat.winnr)
          vim.api.nvim_win_set_cursor(copilot.chat.winnr, { diff.start_line, 0 })
        end

        opts.on_hide = function()
          vim.cmd('diffoff')
        end
      else
        opts.text = tostring(vim.diff(diff.reference, diff.change, {
          result_type = 'unified',
          ignore_blank_lines = true,
          ignore_whitespace = true,
          ignore_whitespace_change = true,
          ignore_whitespace_change_at_eol = true,
          ignore_cr_at_eol = true,
          algorithm = 'myers',
          ctxlen = #diff.reference,
        }))
      end

      copilot.chat:show_overlay(opts)
    end,
  },

  show_info = {
    normal = 'gi',
    callback = function()
      local section = copilot.chat:get_closest_section()
      if not section or section.answer then
        return
      end

      local lines = {}
      local config, prompt = copilot.resolve_prompt(section.content)
      local system_prompt = config.system_prompt

      async.run(function()
        local selected_agent = copilot.resolve_agent(prompt, config)
        local selected_model = copilot.resolve_model(prompt, config)

        utils.schedule_main()
        table.insert(lines, '**Logs**: `' .. copilot.config.log_path .. '`')
        table.insert(lines, '**History**: `' .. copilot.config.history_path .. '`')
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

        copilot.chat:show_overlay({
          text = vim.trim(table.concat(lines, '\n')) .. '\n',
        })
      end)
    end,
  },

  show_context = {
    normal = 'gc',
    callback = function()
      local section = copilot.chat:get_closest_section()
      if not section or section.answer then
        return
      end

      local lines = {}

      local selection = copilot.get_selection()
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
        local embeddings = copilot.resolve_context(section.content)

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

        utils.schedule_main()
        copilot.chat:show_overlay({
          text = vim.trim(table.concat(lines, '\n')) .. '\n',
        })
      end)
    end,
  },

  show_help = {
    normal = 'gh',
    callback = function()
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

      copilot.chat:show_overlay({
        text = chat_help,
      })
    end,
  },
}
