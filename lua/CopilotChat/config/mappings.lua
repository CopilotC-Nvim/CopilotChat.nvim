local async = require('plenary.async')
local copilot = require('CopilotChat')
local client = require('CopilotChat.client')
local constants = require('CopilotChat.constants')
local utils = require('CopilotChat.utils')

---@class CopilotChat.config.mappings.Diff
---@field change string
---@field reference string
---@field filename string
---@field filetype string
---@field start_line number
---@field end_line number
---@field bufnr number?

--- Get diff data from a block
---@param block CopilotChat.ui.chat.Block?
---@return CopilotChat.config.mappings.Diff?
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
    filename = utils.uri_to_filename(header.filename)
    filetype = header.filetype or utils.filetype(filename)
    start_line = header.start_line
    end_line = header.end_line

    -- Try to find matching buffer and window
    bufnr = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local win_buf = vim.api.nvim_win_get_buf(win)
      if utils.filename_same(vim.api.nvim_buf_get_name(win_buf), header.filename) then
        bufnr = win_buf
        break
      end
    end

    -- If we found a valid buffer, get the reference content
    if bufnr and utils.buf_valid(bufnr) then
      local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
      reference = table.concat(lines, '\n')
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
---@param diff CopilotChat.config.mappings.Diff?
---@param source CopilotChat.source?
---@return CopilotChat.config.mappings.Diff?
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
---@field complete CopilotChat.config.mapping|false|nil
---@field close CopilotChat.config.mapping|false|nil
---@field reset CopilotChat.config.mapping|false|nil
---@field submit_prompt CopilotChat.config.mapping|false|nil
---@field toggle_sticky CopilotChat.config.mapping|false|nil
---@field accept_diff CopilotChat.config.mapping|false|nil
---@field jump_to_diff CopilotChat.config.mapping|false|nil
---@field quickfix_diffs CopilotChat.config.mapping|false|nil
---@field yank_diff CopilotChat.config.mapping.yank_diff|false|nil
---@field show_diff CopilotChat.config.mapping.show_diff|false|nil
---@field show_info CopilotChat.config.mapping|false|nil
---@field show_help CopilotChat.config.mapping|false|nil
return {
  complete = {
    insert = '<Tab>',
    callback = function()
      require('CopilotChat.completion').complete()
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
      local message = copilot.chat:get_message(constants.ROLE.USER, true)
      if not message then
        return
      end

      copilot.ask(message.content)
    end,
  },

  toggle_sticky = {
    normal = 'grr',
    callback = function()
      local message = copilot.chat:get_message(constants.ROLE.USER)
      local section = message and message.section
      if not section then
        return
      end

      local cursor = vim.api.nvim_win_get_cursor(copilot.chat.winnr)
      if cursor[1] < section.start_line or cursor[1] > section.end_line then
        return
      end

      local current_line = vim.trim(vim.api.nvim_get_current_line())
      if current_line == '' then
        return
      end

      local cur_line = cursor[1]
      vim.api.nvim_buf_set_lines(copilot.chat.bufnr, cur_line - 1, cur_line, false, {})

      if vim.startswith(current_line, '> ') then
        return
      end

      copilot.chat:add_sticky(current_line)
      vim.api.nvim_win_set_cursor(copilot.chat.winnr, cursor)
    end,
  },

  clear_stickies = {
    normal = 'grx',
    callback = function()
      local message = copilot.chat:get_message(constants.ROLE.USER)
      local section = message and message.section
      if not section then
        return
      end

      local lines = utils.split_lines(message.content)
      local new_lines = {}
      local changed = false

      for _, line in ipairs(lines) do
        if not vim.startswith(vim.trim(line), '> ') then
          table.insert(new_lines, line)
        else
          changed = true
        end
      end

      if changed then
        message.content = table.concat(new_lines, '\n')
        copilot.chat:add_message(message, true)
      end
    end,
  },

  accept_diff = {
    normal = '<C-y>',
    insert = '<C-y>',
    callback = function(source)
      local diff = get_diff(copilot.chat:get_block(constants.ROLE.ASSISTANT, true))
      diff = prepare_diff_buffer(diff, source)
      if not diff then
        return
      end

      local lines = utils.split_lines(diff.change)
      vim.api.nvim_buf_set_lines(diff.bufnr, diff.start_line - 1, diff.end_line, false, lines)
      copilot.set_selection(diff.bufnr, diff.start_line, diff.end_line)
    end,
  },

  jump_to_diff = {
    normal = 'gj',
    callback = function(source)
      local diff = get_diff(copilot.chat:get_block(constants.ROLE.ASSISTANT, true))
      diff = prepare_diff_buffer(diff, source)
      if not diff then
        return
      end

      copilot.set_selection(diff.bufnr, diff.start_line, diff.end_line)
    end,
  },

  quickfix_answers = {
    normal = 'gqa',
    callback = function()
      local items = {}
      for i, message in ipairs(copilot.chat.messages) do
        if message.section and message.role == constants.ROLE.ASSISTANT then
          local prev_message = copilot.chat.messages[i - 1]
          local text = ''
          if prev_message then
            text = prev_message.content
          end

          table.insert(items, {
            bufnr = copilot.chat.bufnr,
            lnum = message.section.start_line,
            end_lnum = message.section.end_line,
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

      for _, message in ipairs(copilot.chat.messages) do
        if message.section then
          for _, block in ipairs(message.section.blocks) do
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
      end
    end,
  },

  yank_diff = {
    normal = 'gy',
    register = '"', -- Default register to use for yanking
    callback = function()
      local block = copilot.chat:get_block(constants.ROLE.ASSISTANT, true)
      if not block then
        return
      end

      vim.fn.setreg(copilot.config.mappings.yank_diff.register, block.content)
    end,
  },

  show_diff = {
    normal = 'gd',
    full_diff = false, -- Show full diff instead of unified diff when showing diff window
    callback = function(source)
      local diff = get_diff(copilot.chat:get_block(constants.ROLE.ASSISTANT, true))
      diff = prepare_diff_buffer(diff, source)
      if not diff then
        return
      end

      local opts = {
        filetype = diff.filetype,
        syntax = 'diff',
      }

      if copilot.config.mappings.show_diff.full_diff then
        local original = utils.buf_valid(diff.bufnr) and vim.api.nvim_buf_get_lines(diff.bufnr, 0, -1, false) or {}

        if #original > 0 then
          -- Find all diffs from the same file in this section
          local message = copilot.chat:get_message(constants.ROLE.ASSISTANT, true)
          local section = message and message.section
          local same_file_diffs = {}
          if section then
            for _, block in ipairs(section.blocks) do
              local block_diff = get_diff(block)
              if block_diff and block_diff.bufnr == diff.bufnr then
                table.insert(same_file_diffs, block_diff)
              end
            end
          end

          -- Ensure we at least apply the current diff
          if #same_file_diffs == 0 then
            table.insert(same_file_diffs, diff)
          end

          -- Sort diffs by start_line in descending order (apply from bottom to top)
          table.sort(same_file_diffs, function(a, b)
            return a.start_line > b.start_line
          end)

          local result = vim.deepcopy(original)

          -- Apply diffs from bottom to top so line numbers remain valid
          for _, d in ipairs(same_file_diffs) do
            local change_lines = utils.split_lines(d.change)

            -- Remove original lines (from end to start to avoid index shifting)
            for i = d.end_line, d.start_line, -1 do
              if result[i] then
                table.remove(result, i)
              end
            end

            -- Insert replacement lines at start_line
            for i = #change_lines, 1, -1 do
              table.insert(result, d.start_line, change_lines[i])
            end
          end

          opts.text = table.concat(result, '\n')
        else
          opts.text = diff.change
        end

        opts.on_show = function()
          vim.api.nvim_win_call(vim.fn.bufwinid(diff.bufnr), function()
            vim.cmd('diffthis')
          end)

          vim.api.nvim_win_call(copilot.chat.winnr, function()
            vim.cmd('diffthis')
          end)
        end

        opts.on_hide = function()
          vim.api.nvim_win_call(copilot.chat.winnr, function()
            vim.cmd('diffoff')
          end)
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

      copilot.chat:overlay(opts)
    end,
  },

  show_info = {
    normal = 'gc',
    callback = function(source)
      local message = copilot.chat:get_message(constants.ROLE.USER, true)
      if not message then
        return
      end

      local lines = {}
      local config, prompt = copilot.resolve_prompt(message.content)
      local system_prompt = config.system_prompt

      async.run(function()
        local infos = client:info()
        local selected_model = copilot.resolve_model(prompt, config)
        local selected_tools, resolved_resources = copilot.resolve_functions(prompt, config)
        selected_tools = vim.tbl_map(function(tool)
          return tool.name
        end, selected_tools)

        utils.schedule_main()
        table.insert(lines, '**Logs**: `' .. copilot.config.log_path .. '`')
        table.insert(lines, '**History**: `' .. copilot.config.history_path .. '`')
        table.insert(lines, '')

        for provider, infolines in pairs(infos) do
          table.insert(lines, '**Provider**: `' .. provider .. '`')
          for _, line in ipairs(infolines) do
            table.insert(lines, line)
          end
          table.insert(lines, '')
        end

        if source and utils.buf_valid(source.bufnr) then
          local source_name = vim.api.nvim_buf_get_name(source.bufnr)
          table.insert(lines, '**Source**: `' .. source_name .. '`')
          table.insert(lines, '')
        end

        if selected_model then
          table.insert(lines, '**Model**: `' .. selected_model .. '`')
          table.insert(lines, '')
        end

        if not utils.empty(selected_tools) then
          table.insert(lines, '**Tools**')
          table.insert(lines, '```')
          table.insert(lines, table.concat(selected_tools, ', '))
          table.insert(lines, '```')
          table.insert(lines, '')
        end

        if system_prompt then
          table.insert(lines, '**System Prompt**')
          table.insert(lines, '````')
          for _, line in ipairs(vim.split(vim.trim(system_prompt), '\n')) do
            table.insert(lines, line)
          end
          table.insert(lines, '````')
          table.insert(lines, '')
        end

        local selection = copilot.get_selection()
        if selection then
          table.insert(lines, '**Selection**')
          table.insert(lines, '')
          table.insert(
            lines,
            string.format('**%s** (%s-%s)', selection.filename, selection.start_line, selection.end_line)
          )
          table.insert(lines, string.format('````%s', selection.filetype))
          for _, line in ipairs(vim.split(selection.content, '\n')) do
            table.insert(lines, line)
          end
          table.insert(lines, '````')
          table.insert(lines, '')
        end

        if not utils.empty(resolved_resources) then
          table.insert(lines, '**Resources**')
          table.insert(lines, '')
        end

        for _, resource in ipairs(resolved_resources) do
          local resource_lines = vim.split(resource.data, '\n')
          local preview = vim.list_slice(resource_lines, 1, math.min(10, #resource_lines))
          local header = string.format('**%s** (%s lines)', resource.uri, #resource_lines)
          if #resource_lines > 10 then
            header = header .. ' (truncated)'
          end

          table.insert(lines, header)
          table.insert(lines, '```' .. utils.mimetype_to_filetype(resource.mimetype))
          for _, line in ipairs(preview) do
            table.insert(lines, line)
          end
          table.insert(lines, '```')
          table.insert(lines, '')
        end

        copilot.chat:overlay({
          text = vim.trim(table.concat(lines, '\n')) .. '\n',
        })
      end)
    end,
  },

  show_help = {
    normal = 'gh',
    callback = function()
      local chat_help = '**`Special tokens`**\n'
      chat_help = chat_help .. '`@<function>` to share function\n'
      chat_help = chat_help .. '`#<function>` to add resource\n'
      chat_help = chat_help .. '`#<function>:<input>` to add resource with input\n'
      chat_help = chat_help .. '`/<prompt>` to select a prompt\n'
      chat_help = chat_help .. '`$<model>` to select a model\n'
      chat_help = chat_help .. '`> <text>` to make a sticky prompt (copied to next prompt)\n'

      chat_help = chat_help .. '\n**`Mappings`**\n'
      local chat_keys = vim.tbl_keys(copilot.config.mappings)
      table.sort(chat_keys, function(a, b)
        a = copilot.config.mappings[a]
        a = a and (a.normal or a.insert) or ''
        b = copilot.config.mappings[b]
        b = b and (b.normal or b.insert) or ''
        return a < b
      end)
      for _, name in ipairs(chat_keys) do
        local info = utils.key_to_info(name, copilot.config.mappings[name], '`')
        if info ~= '' then
          chat_help = chat_help .. info .. '\n'
        end
      end

      copilot.chat:overlay({
        text = chat_help,
      })
    end,
  },
}
