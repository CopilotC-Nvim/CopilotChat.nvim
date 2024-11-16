local context = require('CopilotChat.context')
local utils = require('CopilotChat.utils')

---@class CopilotChat.config.context
---@field description string?
---@field input fun(callback: fun(input: string?), source: CopilotChat.source)?
---@field resolve fun(input: string?, source: CopilotChat.source):table<CopilotChat.context.embed>

return {
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
    description = 'Requires `git`. Includes current git diff in chat context. Supports input (default unstaged, also accepts commit number).',
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
  quickfix = {
    description = 'Includes quickfix list file contents in chat context.',
    resolve = function()
      return context.quickfix()
    end,
  },
}
