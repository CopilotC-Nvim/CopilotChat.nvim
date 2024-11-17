local utils = require('CopilotChat.utils')

local M = {}

function M.setup()
  utils.deprecate('CopilotChat.integrations.cmp.setup', 'config.chat_autocomplete=true')
end

return M
