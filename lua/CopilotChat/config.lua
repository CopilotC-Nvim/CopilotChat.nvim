local prompts = require('CopilotChat.prompts')
local select = require('CopilotChat.select')

---@class CopilotChat.config.selection
---@field buffer number
---@field lines string
---@field filetype string?
---@field start_row number?
---@field start_col number?
---@field end_row number?
---@field end_col number?
---@field prompt_extra string?

---@class CopilotChat.config.prompt
---@field prompt string?
---@field selection function|table?
---@field mapping string?
---@field description string?

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

---@class CopilotChat.config.mappings
---@field close string?
---@field reset string?
---@field complete_after_slash string?
---@field submit_prompt string?
---@field accept_diff string?
---@field show_diff string?

--- CopilotChat default configuration
---@class CopilotChat.config
---@field system_prompt string?
---@field model string?
---@field temperature number?
---@field debug boolean?
---@field show_user_selection boolean?
---@field show_system_prompt boolean?
---@field show_folds boolean?
---@field clear_chat_on_new_prompt boolean?
---@field auto_follow_cursor boolean?
---@field name string?
---@field separator string?
---@field prompts table<string, CopilotChat.config.prompt|string>?
---@field selection nil|CopilotChat.config.selection|fun():CopilotChat.config.selection?
---@field window CopilotChat.config.window?
---@field mappings CopilotChat.config.mappings?
return {
  system_prompt = prompts.COPILOT_INSTRUCTIONS, -- System prompt to use
  model = 'gpt-4', -- GPT model to use
  temperature = 0.1, -- GPT temperature
  debug = false, -- Enable debug logging
  show_user_selection = true, -- Shows user selection in chat
  show_system_prompt = false, -- Shows system prompt in chat
  show_folds = true, -- Shows folds for sections in chat
  clear_chat_on_new_prompt = false, -- Clears chat on every new prompt
  auto_follow_cursor = true, -- Auto-follow cursor in chat
  name = 'CopilotChat', -- Name to use in chat
  separator = '---', -- Separator to use in chat
  -- default prompts
  prompts = {
    Explain = {
      prompt = 'Explain how it works.',
    },
    Tests = {
      prompt = 'Briefly explain how selected code works then generate unit tests.',
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
      selection = function()
        return select.gitdiff(true)
      end,
    },
  },
  -- default selection (visual or line)
  selection = function()
    return select.visual() or select.line()
  end,
  -- default window options
  window = {
    layout = 'vertical', -- 'vertical', 'horizontal', 'float'
    relative = 'editor', -- 'editor', 'win', 'cursor', 'mouse'
    border = 'single', -- 'none', single', 'double', 'rounded', 'solid', 'shadow'
    width = 0.8, -- fractional width of parent
    height = 0.6, -- fractional height of parent
    row = nil, -- row position of the window, default is centered
    col = nil, -- column position of the window, default is centered
    title = 'Copilot Chat', -- title of chat window
    footer = nil, -- footer of chat window
  },
  -- default mappings
  mappings = {
    close = 'q',
    reset = '<C-l>',
    complete_after_slash = '<Tab>',
    submit_prompt = '<CR>',
    accept_diff = '<C-y>',
    show_diff = '<C-d>',
  },
}
