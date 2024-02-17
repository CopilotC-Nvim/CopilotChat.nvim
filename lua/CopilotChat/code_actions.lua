local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local telescope_pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local themes = require('telescope.themes')
local conf = require('telescope.config').values
local utils = require('CopilotChat.utils')

local help_actions = {}
local user_prompt_actions = {}

local function generate_fix_diagnostic_prompt()
  local diagnostic = utils.get_diagnostics()
  local file_name = vim.fn.expand('%:t')
  local line_number = vim.fn.line('.')
  return 'Please assist with fixing the following diagnostic issue in file: "'
    .. file_name
    .. ':'
    .. line_number
    .. '". '
    .. diagnostic
end

local function generate_explain_diagnostic_prompt()
  local diagnostic = utils.get_diagnostics()
  local file_name = vim.fn.expand('%:t')
  local line_number = vim.fn.line('.')
  return 'Please explain the following diagnostic issue in file: "'
    .. file_name
    .. ':'
    .. line_number
    .. '". '
    .. diagnostic
end

--- Help command for telescope picker
--- This will copy all the lines in the buffer to the unnamed register
--- Then will send the diagnostic to copilot chat
---@param prefix string
local function diagnostic_help_command(prefix)
  if prefix == nil then
    prefix = ''
  else
    prefix = prefix .. ' '
  end

  return function(prompt_bufnr, _)
    actions.select_default:replace(function()
      actions.close(prompt_bufnr)
      local selection = action_state.get_selected_entry()

      -- Select all the lines in the buffer to uname register
      vim.cmd('normal! ggVG"*y')

      -- Get value from the help_actions and execute the command
      local value = ''
      for _, action in pairs(help_actions) do
        if action.name == selection[1] then
          value = action.label
          break
        end
      end

      vim.cmd(prefix .. value)
    end)
    return true
  end
end

--- Prompt command for telescope picker
--- This will show all the user prompts in the telescope picker
--- Then will execute the command selected by the user
---@param prefix string
local function generate_prompt_command(prefix)
  if prefix == nil then
    prefix = ''
  else
    prefix = prefix .. ' '
  end

  return function(prompt_bufnr, _)
    actions.select_default:replace(function()
      actions.close(prompt_bufnr)
      local selection = action_state.get_selected_entry()

      -- Get value from the prompt_actions and execute the command
      local value = ''
      for _, action in pairs(user_prompt_actions) do
        if action.name == selection[1] then
          value = action.label
          break
        end
      end

      vim.cmd(prefix .. value)
    end)
    return true
  end
end

local function show_help_actions()
  help_actions = {
    {
      label = generate_fix_diagnostic_prompt(),
      name = 'Fix diagnostic',
    },
    {
      label = generate_explain_diagnostic_prompt(),
      name = 'Explain diagnostic',
    },
  }

  -- Filter all no diagnostics available actions
  help_actions = vim.tbl_filter(function(value)
    return value.label ~= 'No diagnostics available'
  end, help_actions)

  -- Show the menu with telescope pickers
  local opts = themes.get_dropdown({})
  local action_names = {}
  for _, value in pairs(help_actions) do
    table.insert(action_names, value.name)
  end
  telescope_pickers
    .new(opts, {
      prompt_title = 'Copilot Chat Help Actions',
      finder = finders.new_table({
        results = action_names,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = diagnostic_help_command('CopilotChat'),
    })
    :find()
end

--- Show prompt actions
---@param is_in_visual_mode boolean?
local function show_prompt_actions(is_in_visual_mode)
  -- Convert user prompts to a table of actions
  user_prompt_actions = {}

  for key, prompt in pairs(vim.g.copilot_chat_user_prompts) do
    table.insert(user_prompt_actions, { name = key, label = prompt })
  end

  local cmd = 'CopilotChat'

  if is_in_visual_mode then
    cmd = "'<,'>CopilotChatVisual"
  end

  -- Show the menu with telescope pickers
  local opts = themes.get_dropdown({})
  local action_names = {}
  for _, value in pairs(user_prompt_actions) do
    table.insert(action_names, value.name)
  end
  telescope_pickers
    .new(opts, {
      prompt_title = 'Copilot Chat Actions',
      finder = finders.new_table({
        results = action_names,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = generate_prompt_command(cmd),
    })
    :find()
end

return {
  show_help_actions = show_help_actions,
  show_prompt_actions = show_prompt_actions,
}
