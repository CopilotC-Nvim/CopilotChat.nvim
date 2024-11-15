local cmp = require('cmp')
local chat = require('CopilotChat')

local Source = {}

function Source:get_trigger_characters()
  return chat.complete_info().triggers
end

function Source:get_keyword_pattern()
  return chat.complete_info().pattern
end

function Source:complete(params, callback)
  chat.complete_items(function(items)
    items = vim.tbl_map(function(item)
      return {
        label = item.word,
        kind = cmp.lsp.CompletionItemKind.Keyword,
      }
    end, items)

    local prefix = string.lower(params.context.cursor_before_line:sub(params.offset))

    callback({
      items = vim.tbl_filter(function(item)
        return vim.startswith(item.label:lower(), prefix:lower())
      end, items),
    })
  end)
end

---@param completion_item lsp.CompletionItem
---@param callback fun(completion_item: lsp.CompletionItem|nil)
function Source:execute(completion_item, callback)
  callback(completion_item)
  vim.api.nvim_set_option_value('buflisted', false, { buf = 0 })
end

local M = {}

--- Setup the nvim-cmp source for copilot-chat window
function M.setup()
  cmp.register_source('copilot-chat', Source)
  cmp.setup.filetype('copilot-chat', {
    sources = {
      { name = 'copilot-chat' },
    },
  })
end

return M
