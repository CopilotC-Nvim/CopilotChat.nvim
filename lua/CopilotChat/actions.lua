---@class CopilotChat.integrations.actions
---@field prompt string: The prompt to display
---@field selection fun(source: CopilotChat.config.source):CopilotChat.config.selection?
---@field actions table<string, string>: A table with the actions to pick from

local select = require('CopilotChat.select')
local chat = require('CopilotChat')

local M = {}

--- Diagnostic help actions
---@return CopilotChat.integrations.actions?: The help actions
function M.help_actions()
  local diagnostic = select.diagnostics({
    bufnr = vim.api.nvim_get_current_buf(),
    winnr = vim.api.nvim_get_current_win(),
  })
  if not diagnostic then
    return
  end

  return {
    prompt = 'Copilot Chat Help Actions',
    selection = select.buffer,
    actions = {
      ['Fix diagnostic'] = 'Please assist with fixing the following diagnostic issue in file: "'
        .. diagnostic.prompt_extra,
      ['Explain diagnostic'] = 'Please explain the following diagnostic issue in file: "'
        .. diagnostic.prompt_extra,
    },
  }
end

--- User prompt actions
---@return CopilotChat.integrations.actions?: The prompt actions
function M.prompt_actions()
  local actions = {}
  for name, prompt in pairs(chat.prompts(true)) do
    actions[name] = prompt.prompt
  end
  return {
    prompt = 'Copilot Chat Prompt Actions',
    selection = select.visual,
    actions = actions,
  }
end

--- Pick an action from a list of actions
---@param pick_actions CopilotChat.integrations.actions?: A table with the actions to pick from
---@param config CopilotChat.config?: The chat configuration
---@param opts table?: vim.ui.select options
function M.pick(pick_actions, config, opts)
  if not pick_actions or not pick_actions.actions or vim.tbl_isempty(pick_actions.actions) then
    return
  end

  config = vim.tbl_extend('force', {
    selection = pick_actions.selection,
  }, config or {})

  opts = vim.tbl_extend('force', {
    prompt = pick_actions.prompt .. '> ',
  }, opts or {})

  vim.ui.select(vim.tbl_keys(pick_actions.actions), opts, function(selected)
    if not selected then
      return
    end
    vim.defer_fn(function()
      chat.ask(pick_actions.actions[selected], config)
    end, 100)
  end)
end

return M
