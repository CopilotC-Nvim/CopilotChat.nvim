local fzflua = require('fzf-lua')
local chat = require('CopilotChat')
local utils = require('CopilotChat.utils')

local M = {}

--- Pick an action from a list of actions
---@param pick_actions CopilotChat.integrations.actions?: A table with the actions to pick from
---@param opts table?: fzf-lua options
---@deprecated Use |CopilotChat.select_prompt| instead
function M.pick(pick_actions, opts)
  if not pick_actions or not pick_actions.actions or vim.tbl_isempty(pick_actions.actions) then
    return
  end

  utils.return_to_normal_mode()
  opts = vim.tbl_extend('force', {
    prompt = pick_actions.prompt .. '> ',
    preview = function(items)
      return pick_actions.actions[items[1]].prompt
    end,
    winopts = {
      preview = {
        wrap = 'wrap',
      },
    },
    actions = {
      ['default'] = function(selected)
        if not selected or vim.tbl_isempty(selected) then
          return
        end
        vim.defer_fn(function()
          chat.ask(pick_actions.actions[selected[1]].prompt, pick_actions.actions[selected[1]])
        end, 100)
      end,
    },
  }, opts or {})

  fzflua.fzf_exec(vim.tbl_keys(pick_actions.actions), opts)
end

return M
