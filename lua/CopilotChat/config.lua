local prompts = require('CopilotChat.prompts')
local context = require('CopilotChat.context')
local select = require('CopilotChat.select')
local utils = require('CopilotChat.utils')

---@class CopilotChat.config.context
---@field description string?
---@field input fun(callback: fun(input: string?), source: CopilotChat.source)?
---@field resolve fun(input: string?, source: CopilotChat.source):table<CopilotChat.context.embed>

---@class CopilotChat.config.prompt : CopilotChat.config.shared
---@field prompt string?
---@field description string?
---@field mapping string?

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

---@class CopilotChat.config.mapping.register : CopilotChat.config.mapping
---@field register string?

---@class CopilotChat.config.mappings
---@field complete CopilotChat.config.mapping?
---@field close CopilotChat.config.mapping?
---@field reset CopilotChat.config.mapping?
---@field submit_prompt CopilotChat.config.mapping?
---@field toggle_sticky CopilotChat.config.mapping?
---@field accept_diff CopilotChat.config.mapping?
---@field jump_to_diff CopilotChat.config.mapping?
---@field quickfix_diffs CopilotChat.config.mapping?
---@field yank_diff CopilotChat.config.mapping.register?
---@field show_diff CopilotChat.config.mapping?
---@field show_info CopilotChat.config.mapping?
---@field show_context CopilotChat.config.mapping?
---@field show_help CopilotChat.config.mapping?

---@class CopilotChat.config.shared
---@field system_prompt string?
---@field model string?
---@field agent string?
---@field context string|table<string>|nil
---@field temperature number?
---@field headless boolean?
---@field callback fun(response: string, source: CopilotChat.source)?
---@field selection nil|fun(source: CopilotChat.source):CopilotChat.select.selection?
---@field window CopilotChat.config.window?
---@field show_help boolean?
---@field show_folds boolean?
---@field highlight_selection boolean?
---@field highlight_headers boolean?
---@field auto_follow_cursor boolean?
---@field auto_insert_mode boolean?
---@field insert_at_end boolean?
---@field clear_chat_on_new_prompt boolean?

--- CopilotChat default configuration
---@class CopilotChat.config : CopilotChat.config.shared
---@field debug boolean?
---@field log_level string?
---@field proxy string?
---@field allow_insecure boolean?
---@field chat_autocomplete boolean?
---@field history_path string?
---@field question_header string?
---@field answer_header string?
---@field error_header string?
---@field separator string?
---@field contexts table<string, CopilotChat.config.context>?
---@field prompts table<string, CopilotChat.config.prompt|string>?
---@field mappings CopilotChat.config.mappings?
return {

  -- Shared config starts here (can be passed to functions at runtime and configured via setup function)

  system_prompt = prompts.COPILOT_INSTRUCTIONS, -- System prompt to use (can be specified manually in prompt via /).
  model = 'gpt-4o', -- Default model to use, see ':CopilotChatModels' for available models (can be specified manually in prompt via $).
  agent = 'copilot', -- Default agent to use, see ':CopilotChatAgents' for available agents (can be specified manually in prompt via @).
  context = nil, -- Default context or array of contexts to use (can be specified manually in prompt via #).
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
  history_path = vim.fn.stdpath('data') .. '/copilotchat_history', -- Default path to stored history

  question_header = '## User ', -- Header to use for user questions
  answer_header = '## Copilot ', -- Header to use for AI answers
  error_header = '## Error ', -- Header to use for errors
  separator = '───', -- Separator to use in chat

  -- default contexts
  contexts = {
    buffer = {
      description = 'Includes specified buffer in chat context. Supports input (default current).',
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
        input = input and tonumber(input) or source.bufnr
        return {
          context.buffer(input),
        }
      end,
    },
    buffers = {
      description = 'Includes all buffers in chat context. Supports input (default listed).',
      input = function(callback)
        vim.ui.select({ 'listed', 'visible' }, {
          prompt = 'Select buffer scope> ',
        }, callback)
      end,
      resolve = function(input)
        input = input or 'listed'
        return context.buffers(input)
      end,
    },
    file = {
      description = 'Includes content of provided file in chat context. Supports input.',
      input = function(callback, source)
        local cwd = utils.win_cwd(source.winnr)
        local files = vim.tbl_filter(function(file)
          return vim.fn.isdirectory(file) == 0
        end, vim.fn.glob(cwd .. '/**/*', false, true))

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
      description = 'Includes all non-hidden files in the current workspace in chat context. Supports input (default list).',
      input = function(callback)
        local choices = utils.kv_list({
          list = 'Only lists file names',
          full = 'Includes file content for each file found. Can be slow on large workspaces, use with care.',
        })

        vim.ui.select(choices, {
          prompt = 'Select files content> ',
          format_item = function(choice)
            return choice.key .. ' - ' .. choice.value
          end,
        }, function(choice)
          callback(choice and choice.key)
        end)
      end,
      resolve = function(input, source)
        return context.files(source.winnr, input == 'full')
      end,
    },
    git = {
      description = 'Requires `git`. Includes current git diff in chat context. Supports input (default unstaged).',
      input = function(callback)
        vim.ui.select({ 'unstaged', 'staged' }, {
          prompt = 'Select diff type> ',
        }, callback)
      end,
      resolve = function(input, source)
        input = input or 'unstaged'
        return {
          context.gitdiff(input, source.winnr),
        }
      end,
    },
    url = {
      description = 'Includes content of provided URL in chat context. Supports input.',
      input = function(callback)
        vim.ui.input({
          prompt = 'Enter URL> ',
          default = 'https://',
        }, callback)
      end,
      resolve = function(input)
        return {
          context.url(input),
        }
      end,
    },
    register = {
      description = 'Includes contents of register in chat context. Supports input (default +, e.g clipboard).',
      input = function(callback)
        local choices = utils.kv_list({
          ['+'] = 'synchronized with the system clipboard',
          ['*'] = 'synchronized with the selection clipboard',
          ['"'] = 'last deleted, changed, or yanked content',
          ['0'] = 'last yank',
          ['-'] = 'deleted or changed content smaller than one line',
          ['.'] = 'last inserted text',
          ['%'] = 'name of the current file',
          [':'] = 'most recent executed command',
          ['#'] = 'alternate buffer',
          ['='] = 'result of an expression',
          ['/'] = 'last search pattern',
        })

        vim.ui.select(choices, {
          prompt = 'Select a register> ',
          format_item = function(choice)
            return choice.key .. ' - ' .. choice.value
          end,
        }, function(choice)
          callback(choice and choice.key)
        end)
      end,
      resolve = function(input)
        input = input or '+'
        return {
          context.register(input),
        }
      end,
    },
  },

  -- default prompts
  prompts = {
    Explain = {
      prompt = '> /COPILOT_EXPLAIN\n\nWrite an explanation for the selected code as paragraphs of text.',
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
    jump_to_diff = {
      normal = 'gj',
    },
    quickfix_diffs = {
      normal = 'gq',
    },
    yank_diff = {
      normal = 'gy',
      register = '"',
    },
    show_diff = {
      normal = 'gd',
    },
    show_info = {
      normal = 'gi',
    },
    show_context = {
      normal = 'gc',
    },
    show_help = {
      normal = 'gh',
    },
  },
}
