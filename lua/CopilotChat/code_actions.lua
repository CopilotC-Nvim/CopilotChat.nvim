local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local telescope_pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local themes = require('telescope.themes')
local conf = require('telescope.config').values
local utils = require('CopilotChat.utils')

local help_actions = {}

local function fix_diagnostic()
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

local function explain_diagnostic()
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

local function nvim_command(prefix)
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

local function show_help_actions()
  help_actions = {
    {
      label = fix_diagnostic(),
      name = 'Fix diagnostic',
    },
    {
      label = explain_diagnostic(),
      name = 'Explain diagnostic',
    },
  }

  -- Filter all no diagnostics available actions
  help_actions = vim.tbl_filter(function(value)
    return value.label ~= 'No diagnostics available'
  end, help_actions)

  -- Show the menu with telescope pickers
  local opts = themes.get_dropdown({})
  local picker_names = {}
  for _, value in pairs(help_actions) do
    table.insert(picker_names, value.name)
  end
  telescope_pickers
    .new(opts, {
      prompt_title = 'Copilot Chat Help Actions',
      finder = finders.new_table({
        results = picker_names,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = nvim_command('CopilotChat'),
    })
    :find()
end

return {
  show_help_actions = show_help_actions,
}
