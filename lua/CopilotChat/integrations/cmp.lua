local cmp = require('cmp')
local chat = require('CopilotChat')

local Source = {}

function Source:get_trigger_characters()
  return { '@', '/' }
end

function Source:get_keyword_pattern()
  return [[\%(@\|/\)\k*]]
end

function Source:complete(params, callback)
  local items = {}
  local prompts_to_use = chat.prompts()

  local prefix = string.lower(params.context.cursor_before_line:sub(params.offset))
  local prefix_len = #prefix
  local checkAdd = function(word)
    if word:lower():sub(1, prefix_len) == prefix then
      items[#items + 1] = {
        label = word,
        kind = cmp.lsp.CompletionItemKind.Keyword,
      }
    end
  end
  for name, _ in pairs(prompts_to_use) do
    checkAdd('/' .. name)
  end
  checkAdd('@buffers')
  checkAdd('@buffer')

  callback({ items = items })
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
