local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local telescope_pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local themes = require('telescope.themes')
local conf = require('telescope.config').values
local select = require('CopilotChat.select')
local chat = require('CopilotChat')

--- Help command for telescope picker
--- This will send whole buffer to copilot
--- Then will send the diagnostic to copilot chat
local function generate_diagnostic_help_command(config, help_actions)
  config = vim.tbl_deep_extend('force', { selection = select.buffer }, config or {})
  return function(prompt_bufnr, _)
    actions.select_default:replace(function()
      actions.close(prompt_bufnr)
      local selection = action_state.get_selected_entry()

      -- Get value from the help_actions and execute the command
      local value = ''
      for _, action in pairs(help_actions) do
        if action.name == selection[1] then
          value = action.label
          break
        end
      end

      chat.ask(value, config)
    end)
    return true
  end
end

--- Prompt command for telescope picker
--- This will show all the user prompts in the telescope picker
--- Then will execute the command selected by the user
local function generate_prompt_command(config, user_prompt_actions)
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

      chat.ask(value, config)
    end)
    return true
  end
end

local function show_help_actions(config)
  -- Convert diagnostic to a table of actions
  local help_actions = {}
  local diagnostic = select.diagnostics(vim.api.nvim_get_current_buf())
  if diagnostic then
    table.insert(help_actions, {
      label = 'Please assist with fixing the following diagnostic issue in file: "'
        .. diagnostic.prompt_extra
        .. '"',
      name = 'Fix diagnostic',
    })

    table.insert(help_actions, {
      label = 'Please explain the following diagnostic issue in file: "'
        .. diagnostic.prompt_extra
        .. '"',
      name = 'Explain diagnostic',
    })
  end

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
      attach_mappings = generate_diagnostic_help_command(config, help_actions),
    })
    :find()
end

--- Show prompt actions
local function show_prompt_actions(config)
  -- Convert user prompts to a table of actions
  local user_prompt_actions = {}
  for key, prompt in pairs(chat.prompts(true)) do
    table.insert(user_prompt_actions, { name = key, label = prompt.prompt })
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
      attach_mappings = generate_prompt_command(config, user_prompt_actions),
    })
    :find()
end

return {
  show_help_actions = show_help_actions,
  show_prompt_actions = show_prompt_actions,
}
