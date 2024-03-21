---@class CopilotChat.integrations.actions
---@field prompt string: The prompt to display
---@field actions table<string, CopilotChat.config.prompt>: A table with the actions to pick from

local select = require('CopilotChat.select')
local chat = require('CopilotChat')

local M = {}

--- Diagnostic help actions
---@return CopilotChat.integrations.actions?: The help actions
function M.help_actions()
  local bufnr = vim.api.nvim_get_current_buf()
  local winnr = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(winnr)
  local line_diagnostics = vim.lsp.diagnostic.get_line_diagnostics(bufnr, cursor[1] - 1)

  if #line_diagnostics == 0 then
    return nil
  end

  return {
    prompt = 'Copilot Chat Help Actions',
    actions = {
      ['Fix diagnostic'] = {
        prompt = 'Please assist with fixing the following diagnostic issue in file: "',
        selection = select.diagnostics,
      },
      ['Explain diagnostic'] = {
        prompt = 'Please explain the following diagnostic issue in file: "',
        selection = select.diagnostics,
      },
    },
  }
end

--- User prompt actions
---@return CopilotChat.integrations.actions?: The prompt actions
function M.prompt_actions()
  local actions = {}
  for name, prompt in pairs(chat.prompts(true)) do
    actions[name] = prompt
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
