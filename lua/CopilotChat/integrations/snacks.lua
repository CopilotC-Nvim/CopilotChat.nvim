local snacks = require('snacks')
local chat = require('CopilotChat')
local utils = require('CopilotChat.utils')

local M = {}

--- Pick an action from a list of actions
---@param pick_actions CopilotChat.integrations.actions?: A table with the actions to pick from
---@param opts table?: snacks options
---@deprecated Use |CopilotChat.select_prompt| instead
function M.pick(pick_actions, opts)
  if not pick_actions or not pick_actions.actions or vim.tbl_isempty(pick_actions.actions) then
    return
  end

  utils.return_to_normal_mode()
  opts = vim.tbl_extend('force', {
    items = vim.tbl_map(function(name)
      return {
        id = name,
        text = name,
        file = name,
        preview = {
          text = pick_actions.actions[name].prompt,
          ft = 'text',
        },
      }
    end, vim.tbl_keys(pick_actions.actions)),
    preview = 'preview',
    win = {
      preview = {
        wo = {
          wrap = true,
          linebreak = true,
        },
      },
    },
    title = pick_actions.prompt,
    confirm = function(picker)
      local selected = picker:current()
      if selected then
        local action = pick_actions.actions[selected.id]
        vim.defer_fn(function()
          chat.ask(action.prompt, action)
        end, 100)
      end
      picker:close()
    end,
  }, opts or {})

  snacks.picker(opts)
end

return M
