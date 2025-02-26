local prompts = require('CopilotChat.config.prompts')
local select = require('CopilotChat.select')

---@class CopilotChat.config.window
---@field layout 'vertical'|'horizontal'|'float'|'replace'?
---@field relative 'editor'|'win'|'cursor'|'mouse'?
---@field border 'none'|'single'|'double'|'rounded'|'solid'|'shadow'?
---@field width number?
---@field height number?
---@field row number?
---@field col number?
---@field title string?
---@field footer string?
---@field zindex number?

---@class CopilotChat.config.shared
---@field system_prompt string?
---@field model string?
---@field agent string?
---@field context string|table<string>|nil
---@field sticky string|table<string>|nil
---@field temperature number?
---@field headless boolean?
---@field callback fun(response: string, source: CopilotChat.source)?
---@field selection false|nil|fun(source: CopilotChat.source):CopilotChat.select.selection?
---@field window CopilotChat.config.window?
---@field show_help boolean?
---@field show_folds boolean?
---@field highlight_selection boolean?
---@field highlight_headers boolean?
---@field references_display 'virtual'|'write'?
---@field auto_follow_cursor boolean?
---@field auto_insert_mode boolean?
---@field insert_at_end boolean?
---@field clear_chat_on_new_prompt boolean?

--- CopilotChat default configuration
---@class CopilotChat.config : CopilotChat.config.shared
---@field debug boolean?
---@field log_level 'trace'|'debug'|'info'|'warn'|'error'|'fatal'?
---@field proxy string?
---@field allow_insecure boolean?
---@field chat_autocomplete boolean?
---@field log_path string?
---@field history_path string?
---@field question_header string?
---@field answer_header string?
---@field error_header string?
---@field separator string?
---@field providers table<string, CopilotChat.Provider>?
---@field contexts table<string, CopilotChat.config.context>?
---@field prompts table<string, CopilotChat.config.prompt|string>?
---@field mappings CopilotChat.config.mappings?
return {

  -- Shared config starts here (can be passed to functions at runtime and configured via setup function)

  system_prompt = prompts.COPILOT_INSTRUCTIONS.system_prompt, -- System prompt to use (can be specified manually in prompt via /).

  model = 'gpt-4o', -- Default model to use, see ':CopilotChatModels' for available models (can be specified manually in prompt via $).
  agent = 'none', -- Default agent to use, see ':CopilotChatAgents' for available agents (can be specified manually in prompt via @).
  context = nil, -- Default context or array of contexts to use (can be specified manually in prompt via #).
  sticky = nil, -- Default sticky prompt or array of sticky prompts to use at start of every new chat.

  temperature = 0.1, -- GPT result temperature
  headless = false, -- Do not write to chat buffer and use history(useful for using callback for custom processing)
  callback = nil, -- Callback to use when ask response is received

  -- default selection
  selection = function(source)
    return select.visual(source) or select.buffer(source)
  end,

  -- default window options
  window = {
    layout = 'vertical', -- 'vertical', 'horizontal', 'float', 'replace'
    width = 0.5, -- fractional width of parent, or absolute width in columns when > 1
    height = 0.5, -- fractional height of parent, or absolute height in rows when > 1
    -- Options below only apply to floating windows
    relative = 'editor', -- 'editor', 'win', 'cursor', 'mouse'
    border = 'single', -- 'none', single', 'double', 'rounded', 'solid', 'shadow'
    row = nil, -- row position of the window, default is centered
    col = nil, -- column position of the window, default is centered
    title = 'Copilot Chat', -- title of chat window
    footer = nil, -- footer of chat window
    zindex = 1, -- determines if window is on top or below other floating windows
  },

  show_help = true, -- Shows help message as virtual lines when waiting for user input
  show_folds = true, -- Shows folds for sections in chat
  highlight_selection = true, -- Highlight selection
  highlight_headers = true, -- Highlight headers in chat, disable if using markdown renderers (like render-markdown.nvim)
  references_display = 'virtual', -- 'virtual', 'write', Display references in chat as virtual text or write to buffer
  auto_follow_cursor = true, -- Auto-follow cursor in chat
  auto_insert_mode = false, -- Automatically enter insert mode when opening window and on new prompt
  insert_at_end = false, -- Move cursor to end of buffer when inserting text
  clear_chat_on_new_prompt = false, -- Clears chat on every new prompt

  -- Static config starts here (can be configured only via setup function)

  debug = false, -- Enable debug logging (same as 'log_level = 'debug')
  log_level = 'info', -- Log level to use, 'trace', 'debug', 'info', 'warn', 'error', 'fatal'
  proxy = nil, -- [protocol://]host[:port] Use this proxy
  allow_insecure = false, -- Allow insecure server connections

  chat_autocomplete = true, -- Enable chat autocompletion (when disabled, requires manual `mappings.complete` trigger)

  log_path = vim.fn.stdpath('state') .. '/CopilotChat.log', -- Default path to log file
  history_path = vim.fn.stdpath('data') .. '/copilotchat_history', -- Default path to stored history

  question_header = '## User ', -- Header to use for user questions
  answer_header = '## Copilot ', -- Header to use for AI answers
  error_header = '## Error ', -- Header to use for errors
  separator = '───', -- Separator to use in chat

  -- default providers
  providers = require('CopilotChat.config.providers'),

  -- default contexts
  contexts = require('CopilotChat.config.contexts'),

  -- default prompts
  prompts = prompts,

  -- default mappings
  mappings = require('CopilotChat.config.mappings'),
}
