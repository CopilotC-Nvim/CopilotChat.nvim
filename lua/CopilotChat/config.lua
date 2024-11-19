local prompts = require('CopilotChat.prompts')
local context = require('CopilotChat.context')
local select = require('CopilotChat.select')
local utils = require('CopilotChat.utils')

--- @class CopilotChat.config.source
--- @field bufnr number
--- @field winnr number

---@class CopilotChat.config.selection.diagnostic
---@field content string
---@field start_line number
---@field end_line number
---@field severity string

---@class CopilotChat.config.selection
---@field content string
---@field start_line number?
---@field end_line number?
---@field filename string?
---@field filetype string?
---@field bufnr number?
---@field diagnostics table<CopilotChat.config.selection.diagnostic>?

---@class CopilotChat.config.context
---@field description string?
---@field input fun(callback: fun(input: string?))?
---@field resolve fun(input: string?, source: CopilotChat.config.source):table<CopilotChat.copilot.embed>

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
---@field toggle_sticky CopilotChat.config.mapping?
---@field accept_diff CopilotChat.config.mapping?
---@field yank_diff CopilotChat.config.mapping?
---@field show_diff CopilotChat.config.mapping?
---@field show_system_prompt CopilotChat.config.mapping?
---@field show_user_selection CopilotChat.config.mapping?
---@field show_help CopilotChat.config.mapping?

--- CopilotChat default configuration
---@class CopilotChat.config
---@field debug boolean?
---@field log_level string?
---@field proxy string?
---@field allow_insecure boolean?
---@field system_prompt string?
---@field model string?
---@field agent string?
---@field context string?
---@field temperature number?
---@field question_header string?
---@field answer_header string?
---@field error_header string?
---@field separator string?
---@field chat_autocomplete boolean?
---@field show_folds boolean?
---@field show_help boolean?
---@field auto_follow_cursor boolean?
---@field auto_insert_mode boolean?
---@field clear_chat_on_new_prompt boolean?
---@field highlight_selection boolean?
---@field highlight_headers boolean?
---@field history_path string?
---@field callback fun(response: string, source: CopilotChat.config.source)?
---@field selection nil|fun(source: CopilotChat.config.source):CopilotChat.config.selection?
---@field contexts table<string, CopilotChat.config.context>?
---@field prompts table<string, CopilotChat.config.prompt|string>?
---@field window CopilotChat.config.window?
---@field mappings CopilotChat.config.mappings?
return {
  debug = false, -- Enable debug logging (same as 'log_level = 'debug')
  log_level = 'info', -- Log level to use, 'trace', 'debug', 'info', 'warn', 'error', 'fatal'
  proxy = nil, -- [protocol://]host[:port] Use this proxy
  allow_insecure = false, -- Allow insecure server connections

  system_prompt = prompts.COPILOT_INSTRUCTIONS, -- System prompt to use (can be specified manually in prompt via /).
  model = 'gpt-4o', -- Default model to use, see ':CopilotChatModels' for available models (can be specified manually in prompt via $).
  agent = 'copilot', -- Default agent to use, see ':CopilotChatAgents' for available agents (can be specified manually in prompt via @).
  context = nil, -- Default context to use (can be specified manually in prompt via #).
  temperature = 0.1, -- GPT result temperature

  question_header = '## User ', -- Header to use for user questions
  answer_header = '## Copilot ', -- Header to use for AI answers
  error_header = '## Error ', -- Header to use for errors
  separator = '───', -- Separator to use in chat

  chat_autocomplete = true, -- Enable chat autocompletion (when disabled, requires manual `mappings.complete` trigger)
  show_folds = true, -- Shows folds for sections in chat
  show_help = true, -- Shows help message as virtual lines when waiting for user input
  auto_follow_cursor = true, -- Auto-follow cursor in chat
  auto_insert_mode = false, -- Automatically enter insert mode when opening window and on new prompt
  insert_at_end = false, -- Move cursor to end of buffer when inserting text
  clear_chat_on_new_prompt = false, -- Clears chat on every new prompt
  highlight_selection = true, -- Highlight selection
  highlight_headers = true, -- Highlight headers in chat, disable if using markdown renderers (like render-markdown.nvim)

  history_path = vim.fn.stdpath('data') .. '/copilotchat_history', -- Default path to stored history
  callback = nil, -- Callback to use when ask response is received

  -- default selection
  selection = function(source)
    return select.visual(source) or select.buffer(source)
  end,

  -- default contexts
  contexts = {
    buffer = {
      description = 'Includes specified buffer in chat context (default current). Supports input.',
      input = function(callback)
        vim.ui.select(
          vim.tbl_map(
            function(buf)
              return { id = buf, name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':p:.') }
            end,
            vim.tbl_filter(function(buf)
              return utils.buf_valid(buf) and vim.fn.buflisted(buf) == 1
            end, vim.api.nvim_list_bufs())
          ),
          {
            prompt = 'Select a buffer> ',
            format_item = function(item)
              return item.name
            end,
          },
          function(choice)
            callback(choice and choice.id)
          end
        )
      end,
      resolve = function(input, source)
        return {
          context.buffer(input and tonumber(input) or source.bufnr),
        }
      end,
    },
    buffers = {
      description = 'Includes all buffers in chat context (default listed). Supports input.',
      input = function(callback)
        vim.ui.select({ 'listed', 'visible' }, {
          prompt = 'Select buffer scope> ',
        }, callback)
      end,
      resolve = function(input)
        input = input or 'listed'
        return vim.tbl_map(
          context.buffer,
          vim.tbl_filter(function(b)
            return utils.buf_valid(b)
              and vim.fn.buflisted(b) == 1
              and (input == 'listed' or #vim.fn.win_findbuf(b) > 0)
          end, vim.api.nvim_list_bufs())
        )
      end,
    },
    file = {
      description = 'Includes content of provided file in chat context. Supports input.',
      input = function(callback)
        local files = vim.tbl_filter(function(file)
          return vim.fn.isdirectory(file) == 0
        end, vim.fn.glob('**/*', false, true))

        vim.ui.select(files, {
          prompt = 'Select a file> ',
        }, callback)
      end,
      resolve = function(input)
        return {
          context.file(input),
        }
      end,
    },
    files = {
      description = 'Includes all non-hidden filenames in the current workspace in chat context. Supports input.',
      input = function(callback)
        vim.ui.input({
          prompt = 'Enter a file pattern> ',
          default = '**/*',
        }, callback)
      end,
      resolve = function(input)
        return context.files(input)
      end,
    },
    git = {
      description = 'Includes current git diff in chat context (default unstaged). Supports input.',
      input = function(callback)
        vim.ui.select({ 'unstaged', 'staged' }, {
          prompt = 'Select diff type> ',
        }, callback)
      end,
      resolve = function(input, source)
        return {
          context.gitdiff(input, source.bufnr),
        }
      end,
    },
  },

  -- default prompts
  prompts = {
    Explain = {
      prompt = '> /COPILOT_EXPLAIN\n\nWrite an explanation for the selected code and diagnostics as paragraphs of text.',
    },
    Review = {
      prompt = '> /COPILOT_REVIEW\n\nReview the selected code.',
      callback = function(response, source)
        local diagnostics = {}
        for line in response:gmatch('[^\r\n]+') do
          if line:find('^line=') then
            local start_line = nil
            local end_line = nil
            local message = nil
            local single_match, message_match = line:match('^line=(%d+): (.*)$')
            if not single_match then
              local start_match, end_match, m_message_match = line:match('^line=(%d+)-(%d+): (.*)$')
              if start_match and end_match then
                start_line = tonumber(start_match)
                end_line = tonumber(end_match)
                message = m_message_match
              end
            else
              start_line = tonumber(single_match)
              end_line = start_line
              message = message_match
            end

            if start_line and end_line then
              table.insert(diagnostics, {
                lnum = start_line - 1,
                end_lnum = end_line - 1,
                col = 0,
                message = message,
                severity = vim.diagnostic.severity.WARN,
                source = 'Copilot Review',
              })
            end
          end
        end
        vim.diagnostic.set(
          vim.api.nvim_create_namespace('copilot_diagnostics'),
          source.bufnr,
          diagnostics
        )
      end,
    },
    Fix = {
      prompt = '> /COPILOT_GENERATE\n\nThere is a problem in this code. Rewrite the code to show it with the bug fixed.',
    },
    Optimize = {
      prompt = '> /COPILOT_GENERATE\n\nOptimize the selected code to improve performance and readability.',
    },
    Docs = {
      prompt = '> /COPILOT_GENERATE\n\nPlease add documentation comments to the selected code.',
    },
    Tests = {
      prompt = '> /COPILOT_GENERATE\n\nPlease generate tests for my code.',
    },
    Commit = {
      prompt = '> #git:staged\n\nWrite commit message for the change with commitizen convention. Make sure the title has maximum 50 characters and message is wrapped at 72 characters. Wrap the whole message in code block with language gitcommit.',
    },
  },

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

  -- default mappings
  mappings = {
    complete = {
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
      insert = '<C-s>',
    },
    toggle_sticky = {
      detail = 'Makes line under cursor sticky or deletes sticky line.',
      normal = 'gr',
    },
    accept_diff = {
      normal = '<C-y>',
      insert = '<C-y>',
    },
    yank_diff = {
      normal = 'gy',
      register = '"',
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
    show_help = {
      normal = 'gh',
    },
  },
}
