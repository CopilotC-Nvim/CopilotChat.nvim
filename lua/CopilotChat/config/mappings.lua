local async = require('plenary.async')
local copilot = require('CopilotChat')
local client = require('CopilotChat.client')
local constants = require('CopilotChat.constants')
local select = require('CopilotChat.select')
local utils = require('CopilotChat.utils')
local diff = require('CopilotChat.utils.diff')
local files = require('CopilotChat.utils.files')

--- Prepare a buffer for applying a diff
---@param filename string?
---@param source CopilotChat.source
---@return integer
local function prepare_diff_buffer(filename, source)
  if not filename then
    filename = vim.api.nvim_buf_get_name(source.bufnr)
  end

  local diff_bufnr = nil

  -- If buffer is not found, try to load it
  if not diff_bufnr then
    -- Try to find matching buffer first
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if files.filename_same(vim.api.nvim_buf_get_name(buf), filename) then
        diff_bufnr = buf
        break
      end
    end

    -- If still not found, create a new buffer
    if not diff_bufnr then
      diff_bufnr = vim.fn.bufadd(filename)
      vim.fn.bufload(diff_bufnr)
    end
  end

  -- If source exists, update it to point to the diff buffer
  if source and source.winnr and vim.api.nvim_win_is_valid(source.winnr) then
    source.bufnr = diff_bufnr
    vim.api.nvim_win_set_buf(source.winnr, diff_bufnr)
  end

  return diff_bufnr
end

---@class CopilotChat.config.mapping
---@field normal string?
---@field insert string?
---@field callback fun(source: CopilotChat.source)

---@class CopilotChat.config.mapping.yank_diff : CopilotChat.config.mapping
---@field register string?

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
---@field show_diff CopilotChat.config.mapping|false|nil
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
      local block = copilot.chat:get_block(constants.ROLE.ASSISTANT, true)
      if not block then
        return
      end

      local path = block.header.filename
      local bufnr = prepare_diff_buffer(path, source)
      local new_lines = diff.apply_diff(block, bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
      local first, last = diff.get_diff_region(block, bufnr)
      if first and last then
        select.set(bufnr, source.winnr, first, last)
        select.highlight(bufnr)
      end
    end,
  },

  jump_to_diff = {
    normal = 'gj',
    callback = function(source)
      local block = copilot.chat:get_block(constants.ROLE.ASSISTANT, true)
      if not block then
        return
      end

      local path = block.header.filename
      local bufnr = prepare_diff_buffer(path, source)
      local first, last = diff.get_diff_region(block, bufnr)
      if first and last and bufnr then
        select.set(bufnr, source.winnr, first, last)
        select.highlight(bufnr)
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
    callback = function(source)
      local block = copilot.chat:get_block(constants.ROLE.ASSISTANT, true)
      if not block then
        return
      end

      local path = block.header.filename
      local bufnr = prepare_diff_buffer(path, source)
      local new_lines = diff.apply_diff(block, bufnr)

      local opts = {
        filetype = vim.bo[bufnr].filetype,
        text = table.concat(new_lines, '\n'),
      }

      opts.on_show = function()
        vim.api.nvim_win_call(source.winnr, function()
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

      copilot.chat:overlay(opts)
    end,
  },

  quickfix_diffs = {
    normal = 'gqd',
    callback = function()
      local items = {}
      local messages = copilot.chat:get_messages()
      for _, message in ipairs(messages) do
        if message.section then
          for _, block in ipairs(message.section.blocks) do
            local text = string.format('%s (%s)', block.header.filename, block.header.filetype)
            if block.header.start_line and block.header.end_line then
              text = text .. string.format(' [lines %d-%d]', block.header.start_line, block.header.end_line)
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
        local selected_tools = copilot.resolve_tools(prompt, config)
        local selected_model = copilot.resolve_model(prompt, config)
        local resolved_resources = copilot.resolve_functions(prompt, config)

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

        local selection = select.get(source.bufnr)
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
          table.insert(lines, '```' .. files.mimetype_to_filetype(resource.mimetype))
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
