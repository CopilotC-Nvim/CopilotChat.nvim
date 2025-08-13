---@alias CopilotChat.config.Layout 'vertical'|'horizontal'|'float'|'replace'

---@class CopilotChat.config.Window
---@field layout? CopilotChat.config.Layout|fun():CopilotChat.config.Layout
---@field relative 'editor'|'win'|'cursor'|'mouse'?
---@field border 'none'|'single'|'double'|'rounded'|'solid'|'shadow'?
---@field width number?
---@field height number?
---@field row number?
---@field col number?
---@field title string?
---@field footer string?
---@field zindex number?
---@field blend number?

---@class CopilotChat.config.Shared
---@field system_prompt nil|string|fun(source: CopilotChat.source):string
---@field model string?
---@field tools string|table<string>|nil
---@field sticky string|table<string>|nil
---@field language string?
---@field temperature number?
---@field headless boolean?
---@field callback nil|fun(response: CopilotChat.client.Message, source: CopilotChat.source)
---@field remember_as_sticky boolean?
---@field selection false|nil|fun(source: CopilotChat.source):CopilotChat.select.Selection?
---@field window CopilotChat.config.Window?
---@field show_help boolean?
---@field show_folds boolean?
---@field highlight_selection boolean?
---@field highlight_headers boolean?
---@field auto_follow_cursor boolean?
---@field auto_insert_mode boolean?
---@field insert_at_end boolean?
---@field clear_chat_on_new_prompt boolean?

--- CopilotChat default configuration
---@class CopilotChat.config.Config : CopilotChat.config.Shared
---@field debug boolean?
---@field log_level 'trace'|'debug'|'info'|'warn'|'error'|'fatal'?
---@field proxy string?
---@field allow_insecure boolean?
---@field chat_autocomplete boolean?
---@field log_path string?
---@field history_path string?
---@field headers table<string, string>?
---@field separator string?
---@field providers table<string, CopilotChat.config.providers.Provider>?
---@field functions table<string, CopilotChat.config.functions.Function>?
---@field prompts table<string, CopilotChat.config.prompts.Prompt|string>?
---@field mappings CopilotChat.config.mappings?
return {

  -- Shared config starts here (can be passed to functions at runtime and configured via setup function)

  system_prompt = require('CopilotChat.config.prompts').COPILOT_INSTRUCTIONS.system_prompt, -- System prompt to use (can be specified manually in prompt via /).

  model = 'gpt-4.1', -- Default model to use, see ':CopilotChatModels' for available models (can be specified manually in prompt via $).
  tools = nil, -- Default tool or array of tools (or groups) to share with LLM (can be specified manually in prompt via @).
  sticky = nil, -- Default sticky prompt or array of sticky prompts to use at start of every new chat (can be specified manually in prompt via >).
  language = 'English', -- Default language to use for answers

  temperature = 0.1, -- Result temperature
  headless = false, -- Do not write to chat buffer and use history (useful for using custom processing)
  callback = nil, -- Function called when full response is received
  remember_as_sticky = true, -- Remember config as sticky prompts when asking questions

  -- default selection
  selection = require('CopilotChat.select').visual,

  -- default window options
  window = {
    layout = 'vertical', -- 'vertical', 'horizontal', 'float', 'replace', or a function that returns the layout
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
    blend = 0, -- window blend (transparency), 0-100, 0 is opaque, 100 is fully transparent
  },

  show_help = true, -- Shows help message as virtual lines when waiting for user input
  show_folds = true, -- Shows folds for sections in chat
  highlight_selection = true, -- Highlight selection
  highlight_headers = true, -- Highlight headers in chat
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

  headers = {
    user = '## User ', -- Header to use for user questions
    assistant = '## Copilot ', -- Header to use for AI answers
    tool = '## Tool ', -- Header to use for tool calls
  },

  separator = '───', -- Separator to use in chat

  -- default providers
  providers = require('CopilotChat.config.providers'),

  -- default functions
  functions = require('CopilotChat.config.functions'),

  -- default prompts
  prompts = require('CopilotChat.config.prompts'),

  -- default mappings
  mappings = require('CopilotChat.config.mappings'),
}
