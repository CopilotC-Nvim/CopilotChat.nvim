local context = require('CopilotChat.context')
local utils = require('CopilotChat.utils')

---@class CopilotChat.config.context
---@field description string?
---@field input fun(callback: fun(input: string?), source: CopilotChat.source)?
---@field resolve fun(input: string?, source: CopilotChat.source, prompt: string):table<CopilotChat.context.embed>

---@type table<string, CopilotChat.config.context>
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

      utils.schedule_main()
      return {
        context.get_buffer(input),
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

      utils.schedule_main()
      return vim.tbl_map(
        context.get_buffer,
        vim.tbl_filter(function(b)
          return utils.buf_valid(b) and vim.fn.buflisted(b) == 1 and (input == 'listed' or #vim.fn.win_findbuf(b) > 0)
        end, vim.api.nvim_list_bufs())
      )
    end,
  },

  file = {
    description = 'Includes content of provided file in chat context. Supports input.',
    input = function(callback, source)
      local files = utils.scan_dir(source.cwd(), {
        max_count = 0,
      })

      utils.schedule_main()
      vim.ui.select(files, {
        prompt = 'Select a file> ',
      }, callback)
    end,
    resolve = function(input)
      if not input or input == '' then
        return {}
      end

      utils.schedule_main()
      return {
        context.get_file(utils.filepath(input), utils.filetype(input)),
      }
    end,
  },

  files = {
    description = 'Includes all non-hidden files in the current workspace in chat context. Supports input (glob pattern).',
    input = function(callback)
      vim.ui.input({
        prompt = 'Enter glob> ',
      }, callback)
    end,
    resolve = function(input, source)
      local files = utils.scan_dir(source.cwd(), {
        glob = input,
      })

      utils.schedule_main()
      files = vim.tbl_filter(
        function(file)
          return file.ft ~= nil
        end,
        vim.tbl_map(function(file)
          return {
            name = utils.filepath(file),
            ft = utils.filetype(file),
          }
        end, files)
      )

      return vim
        .iter(files)
        :map(function(file)
          return context.get_file(file.name, file.ft)
        end)
        :filter(function(file_data)
          return file_data ~= nil
        end)
        :totable()
    end,
  },

  filenames = {
    description = 'Includes names of all non-hidden files in the current workspace in chat context. Supports input (glob pattern).',
    input = function(callback)
      vim.ui.input({
        prompt = 'Enter glob> ',
      }, callback)
    end,
    resolve = function(input, source)
      local out = {}
      local files = utils.scan_dir(source.cwd(), {
        glob = input,
      })

      local chunk_size = 100
      for i = 1, #files, chunk_size do
        local chunk = {}
        for j = i, math.min(i + chunk_size - 1, #files) do
          table.insert(chunk, files[j])
        end

        local chunk_number = math.floor(i / chunk_size)
        local chunk_name = chunk_number == 0 and 'file_map' or 'file_map' .. tostring(chunk_number)

        table.insert(out, {
          content = table.concat(chunk, '\n'),
          filename = chunk_name,
          filetype = 'text',
          score = 0.1,
        })
      end

      return out
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
      local cmd = {
        'git',
        '-C',
        source.cwd(),
        'diff',
        '--no-color',
        '--no-ext-diff',
      }

      if input == 'staged' then
        table.insert(cmd, '--staged')
      elseif input == 'unstaged' then
        table.insert(cmd, '--')
      else
        table.insert(cmd, input)
      end

      local out = utils.system(cmd)

      return {
        {
          content = out.stdout,
          filename = 'git_diff_' .. input,
          filetype = 'diff',
        },
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
        context.get_url(input),
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

      utils.schedule_main()
      local lines = vim.fn.getreg(input)
      if not lines or lines == '' then
        return {}
      end

      return {
        {
          content = lines,
          filename = 'vim_register_' .. input,
          filetype = '',
        },
      }
    end,
  },

  quickfix = {
    description = 'Includes quickfix list file contents in chat context.',
    resolve = function()
      utils.schedule_main()

      local items = vim.fn.getqflist()
      if not items or #items == 0 then
        return {}
      end

      local unique_files = {}
      for _, item in ipairs(items) do
        local filename = item.filename or vim.api.nvim_buf_get_name(item.bufnr)
        if filename then
          unique_files[filename] = true
        end
      end

      local files = vim.tbl_filter(
        function(file)
          return file.ft ~= nil
        end,
        vim.tbl_map(function(file)
          return {
            name = utils.filepath(file),
            ft = utils.filetype(file),
          }
        end, vim.tbl_keys(unique_files))
      )

      return vim
        .iter(files)
        :map(function(file)
          return context.get_file(file.name, file.ft)
        end)
        :filter(function(file_data)
          return file_data ~= nil
        end)
        :totable()
    end,
  },

  system = {
    description = [[Includes output of provided system shell command in chat context. Supports input.

Important:
- Only use system commands as last resort, they are run every time the context is requested.
- For example instead of curl use the url context, instead of finding and grepping try to check if there is any context that can query the data you need instead.
- If you absolutely need to run a system command, try to use read-only commands and avoid commands that modify the system state.
]],
    input = function(callback)
      vim.ui.input({
        prompt = 'Enter command> ',
      }, callback)
    end,
    resolve = function(input)
      if not input or input == '' then
        return {}
      end

      utils.schedule_main()

      local shell, shell_flag
      if vim.fn.has('win32') == 1 then
        shell, shell_flag = 'cmd.exe', '/c'
      else
        shell, shell_flag = 'sh', '-c'
      end

      local out = utils.system({ shell, shell_flag, input })
      if not out then
        return {}
      end

      local out_type = 'command_output'
      local out_text = out.stdout
      if out.code ~= 0 then
        out_type = 'command_error'
        if out.stderr and out.stderr ~= '' then
          out_text = out.stderr
        elseif not out_text or out_text == '' then
          out_text = 'Command failed with exit code ' .. out.code
        end
      end

      return {
        {
          content = out_text,
          filename = out_type .. '_' .. input:gsub('[^%w]', '_'):sub(1, 20),
          filetype = 'text',
        },
      }
    end,
  },
}
