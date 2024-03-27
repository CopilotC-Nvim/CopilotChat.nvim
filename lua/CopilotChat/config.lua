local prompts = require('CopilotChat.prompts')
local select = require('CopilotChat.select')

--- @class CopilotChat.config.source
--- @field bufnr number
--- @field winnr number

---@class CopilotChat.config.selection
---@field lines string
---@field filename string?
---@field filetype string?
---@field start_row number?
---@field start_col number?
---@field end_row number?
---@field end_col number?
---@field prompt_extra string?

---@class CopilotChat.config.prompt
---@field prompt string?
---@field description string?
---@field kind string?
---@field mapping string?
---@field system_prompt string?
---@field callback fun(response: string, source: CopilotChat.config.source)?
---@field selection nil|fun(source: CopilotChat.config.source):CopilotChat.config.selection?

---@class CopilotChat.config.window
---@field layout string?
---@field relative string?
---@field border string?
---@field width number?
---@field height number?
---@field row number?
---@field col number?
---@field title string?
---@field footer string?
---@field zindex number?

---@class CopilotChat.config.mapping
---@field normal string?
---@field insert string?
---@field detail string?

---@class CopilotChat.config.mappings
---@field complete CopilotChat.config.mapping?
---@field close CopilotChat.config.mapping?
---@field reset CopilotChat.config.mapping?
---@field submit_prompt CopilotChat.config.mapping?
---@field accept_diff CopilotChat.config.mapping?
---@field yank_diff CopilotChat.config.mapping?
---@field show_diff CopilotChat.config.mapping?
---@field show_system_prompt CopilotChat.config.mapping?
---@field show_user_selection CopilotChat.config.mapping?

--- CopilotChat default configuration
---@class CopilotChat.config
---@field debug boolean?
---@field proxy string?
---@field allow_insecure boolean?
---@field system_prompt string?
---@field model string?
---@field temperature number?
---@field question_header string?
---@field answer_header string?
---@field error_header string?
---@field separator string?
---@field show_folds boolean?
---@field show_help boolean?
---@field auto_follow_cursor boolean?
---@field auto_insert_mode boolean?
---@field clear_chat_on_new_prompt boolean?
---@field context string?
---@field history_path string?
---@field callback fun(response: string, source: CopilotChat.config.source)?
---@field selection nil|fun(source: CopilotChat.config.source):CopilotChat.config.selection?
---@field prompts table<string, CopilotChat.config.prompt|string>?
---@field window CopilotChat.config.window?
---@field mappings CopilotChat.config.mappings?

return {
  debug = false, -- Enable debug logging
  proxy = nil, -- [protocol://]host[:port] Use this proxy
  allow_insecure = false, -- Allow insecure server connections

  system_prompt = prompts.COPILOT_INSTRUCTIONS, -- System prompt to use
  model = 'gpt-4', -- GPT model to use, 'gpt-3.5-turbo' or 'gpt-4'
  temperature = 0.1, -- GPT temperature

  question_header = '', -- Header to use for user questions
  answer_header = '**Copilot** ', -- Header to use for AI answers
  error_header = '**Error** ', -- Header to use for errors
  separator = '---', -- Separator to use in chat

  show_folds = true, -- Shows folds for sections in chat
  show_help = true, -- Shows help message as virtual lines when waiting for user input
  auto_follow_cursor = true, -- Auto-follow cursor in chat
  auto_insert_mode = false, -- Automatically enter insert mode when opening window and if auto follow cursor is enabled on new prompt
  clear_chat_on_new_prompt = false, -- Clears chat on every new prompt

  context = nil, -- Default context to use, 'buffers', 'buffer' or none (can be specified manually in prompt via @).
  history_path = vim.fn.stdpath('data') .. '/copilotchat_history', -- Default path to stored history
  callback = nil, -- Callback to use when ask response is received

  -- default selection (visual or line)
  selection = function(source)
    return select.visual(source) or select.line(source)
  end,

  -- default prompts
  prompts = {
    Explain = {
      prompt = '/COPILOT_EXPLAIN Write an explanation for the code above as paragraphs of text.',
    },
    Tests = {
      prompt = '/COPILOT_TESTS Write a set of detailed unit test functions for the code above.',
    },
    Fix = {
      prompt = '/COPILOT_FIX There is a problem in this code. Rewrite the code to show it with the bug fixed.',
    },
    Optimize = {
      prompt = '/COPILOT_REFACTOR Optimize the selected code to improve performance and readablilty.',
    },
    Docs = {
      prompt = '/COPILOT_REFACTOR Write documentation for the selected code. The reply should be a codeblock containing the original code with the documentation added as comments. Use the most appropriate documentation style for the programming language used (e.g. JSDoc for JavaScript, docstrings for Python etc.',
    },
    FixDiagnostic = {
      prompt = 'Please assist with the following diagnostic issue in file:',
      selection = select.diagnostics,
    },
    Commit = {
      prompt = 'Write commit message for the change with commitizen convention. Make sure the title has maximum 50 characters and message is wrapped at 72 characters. Wrap the whole message in code block with language gitcommit.',
      selection = select.gitdiff,
    },
    CommitStaged = {
      prompt = 'Write commit message for the change with commitizen convention. Make sure the title has maximum 50 characters and message is wrapped at 72 characters. Wrap the whole message in code block with language gitcommit.',
      selection = function(source)
        return select.gitdiff(source, true)
      end,
    },
  },

  -- default window options
  window = {
    layout = 'vertical', -- 'vertical', 'horizontal', 'float'
    -- Options below only apply to floating windows
    relative = 'editor', -- 'editor', 'win', 'cursor', 'mouse'
    border = 'single', -- 'none', single', 'double', 'rounded', 'solid', 'shadow'
    width = 0.8, -- fractional width of parent
    height = 0.6, -- fractional height of parent
    row = nil, -- row position of the window, default is centered
    col = nil, -- column position of the window, default is centered
    title = 'Copilot Chat', -- title of chat window
    footer = nil, -- footer of chat window
    zindex = 1, -- determines if window is on top or below other floating windows
  },

  -- default mappings (in tables first is normal mode, second is insert mode)
  mappings = {
    complete = {
      detail = 'Use @<Tab> or /<Tab> for options.',
      insert = '<Tab>',
    },
    close = {
      normal = 'q',
      insert = '<C-c>',
    },
    reset = {
      normal = '<C-l>',
      insert = '<C-l>',
    },
    submit_prompt = {
      normal = '<CR>',
      insert = '<C-m>',
    },
    accept_diff = {
      normal = '<C-y>',
      insert = '<C-y>',
    },
    yank_diff = {
      normal = 'gy',
    },
    show_diff = {
      normal = 'gd',
    },
    show_system_prompt = {
      normal = 'gp',
    },
    show_user_selection = {
      normal = 'gs',
    },
  },
}
