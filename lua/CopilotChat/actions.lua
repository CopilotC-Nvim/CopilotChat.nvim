---@class CopilotChat.integrations.actions
---@field prompt string: The prompt to display
---@field actions table<string, CopilotChat.config.prompt>: A table with the actions to pick from

local chat = require('CopilotChat')
local utils = require('CopilotChat.utils')

local M = {}

function M.help_actions()
  utils.deprecate('help_actions()', 'prompt_actions()')
  return M.prompt_actions()
end

--- User prompt actions
---@param config CopilotChat.config.shared?: The chat configuration
---@return CopilotChat.integrations.actions?: The prompt actions
function M.prompt_actions(config)
  local actions = {}
  for name, prompt in pairs(chat.prompts()) do
    if prompt.prompt then
      actions[name] = vim.tbl_extend('keep', prompt, config or {})
    end
  end
  return {
    prompt = 'Copilot Chat Prompt Actions',
    actions = actions,
  }
end

--- Pick an action from a list of actions
---@param pick_actions CopilotChat.integrations.actions?: A table with the actions to pick from
---@param opts table?: vim.ui.select options
function M.pick(pick_actions, opts)
  if not pick_actions or not pick_actions.actions or vim.tbl_isempty(pick_actions.actions) then
    return
  end

  opts = vim.tbl_extend('force', {
    prompt = pick_actions.prompt .. '> ',
  }, opts or {})

  vim.ui.select(vim.tbl_keys(pick_actions.actions), opts, function(selected)
    if not selected then
      return
    end
    vim.defer_fn(function()
      chat.ask(pick_actions.actions[selected].prompt, pick_actions.actions[selected])
    end, 100)
  end)
end

return M
