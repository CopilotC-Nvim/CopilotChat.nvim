local tools = require('CopilotChat.tools')
local utils = require('CopilotChat.utils')

---@class CopilotChat.config.tools.Tool
---@field description string?
---@field schema table?
---@field resolve fun(input: table, source: CopilotChat.source, prompt: string):table<CopilotChat.tools.Content>

---@type table<string, CopilotChat.config.tools.Tool>
return {
  buffer = {
    description = 'Retrieves content from a specific buffer. Useful for discussing or analyzing code from a particular file that is currently loaded.',
    schema = {
      type = 'object',
      required = { 'name' },
      properties = {
        name = {
          type = 'string',
          description = 'Buffer name to include in chat context.',
          enum = function()
            return vim
              .iter(vim.api.nvim_list_bufs())
              :filter(function(buf)
                return buf and utils.buf_valid(buf) and vim.fn.buflisted(buf) == 1
              end)
              :map(function(buf)
                return vim.api.nvim_buf_get_name(buf)
              end)
              :totable()
          end,
        },
      },
    },

    resolve = function(input, source)
      utils.schedule_main()
      local name = input.name or vim.api.nvim_buf_get_name(source.bufnr)
      local found_buf = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(buf) == name then
          found_buf = buf
          break
        end
      end
      if not found_buf then
        error('Buffer not found: ' .. name)
      end
      return {
        tools.get_buffer(found_buf),
      }
    end,
  },

  buffers = {
    description = 'Fetches content from multiple buffers. Helps with discussing or analyzing code across multiple files simultaneously.',

    schema = {
      type = 'object',
      required = { 'scope' },
      properties = {
        scope = {
          type = 'string',
          description = 'Scope of buffers to include in chat context.',
          enum = { 'listed', 'visible' },
          default = 'listed',
        },
      },
    },

    resolve = function(input)
      utils.schedule_main()
      return vim.tbl_map(
        tools.get_buffer,
        vim.tbl_filter(function(b)
          return utils.buf_valid(b)
            and vim.fn.buflisted(b) == 1
            and (input.scope == 'listed' or #vim.fn.win_findbuf(b) > 0)
        end, vim.api.nvim_list_bufs())
      )
    end,
  },

  file = {
    description = 'Reads content from a specified file path, even if the file is not currently loaded as a buffer.',

    schema = {
      type = 'object',
      required = { 'path' },
      properties = {
        path = {
          type = 'string',
          description = 'Path to file to include in chat context.',
          enum = function(source)
            return utils.glob(source.cwd(), {
              max_count = 0,
            })
          end,
        },
      },
    },

    resolve = function(input)
      return {
        tools.get_file(utils.filepath(input.path), utils.filetype(input.path)),
      }
    end,
  },

  glob = {
    description = 'Lists filenames matching a pattern in your workspace. Useful for discovering relevant files or understanding the project structure.',

    schema = {
      type = 'object',
      required = { 'pattern' },
      properties = {
        pattern = {
          type = 'string',
          description = 'Glob pattern to match files.',
          default = '**/*',
        },
      },
    },

    resolve = function(input, source)
      local files = utils.glob(source.cwd(), {
        pattern = input.pattern,
      })

      return {
        {
          type = 'text',
          data = table.concat(files, '\n'),
        },
      }
    end,
  },

  grep = {
    description = 'Searches for a pattern across files in your workspace. Helpful for finding specific code elements or patterns.',

    schema = {
      type = 'object',
      required = { 'pattern' },
      properties = {
        pattern = {
          type = 'string',
          description = 'Pattern to search for.',
        },
      },
    },

    resolve = function(input, source)
      local files = utils.grep(source.cwd(), {
        pattern = input.pattern,
      })

      return {
        {
          type = 'text',
          data = table.concat(files, '\n'),
        },
      }
    end,
  },

  quickfix = {
    description = 'Includes the content of all files referenced in the current quickfix list. Useful for discussing compilation errors, search results, or other collected locations.',

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

      return vim
        .iter(vim.tbl_keys(unique_files))
        :map(function(file)
          return tools.get_file(utils.filepath(file), utils.filetype(file))
        end)
        :filter(function(file_data)
          return file_data ~= nil
        end)
        :totable()
    end,
  },

  diagnostics = {
    description = 'Collects code diagnostics (errors, warnings, etc.) from specified buffers. Helpful for troubleshooting and fixing code issues.',

    schema = {
      type = 'object',
      required = { 'scope' },
      properties = {
        scope = {
          type = 'string',
          description = 'Scope of buffers to use for retrieving diagnostics.',
          enum = { 'current', 'listed', 'visible' },
          default = 'current',
        },
      },
    },

    resolve = function(input, source)
      utils.schedule_main()
      local out = {}
      local scope = input.scope or 'current'
      local buffers = {}

      -- Get buffers based on scope
      if scope == 'current' then
        if source and source.bufnr and utils.buf_valid(source.bufnr) then
          buffers = { source.bufnr }
        end
      elseif scope == 'listed' then
        buffers = vim.tbl_filter(function(b)
          return utils.buf_valid(b) and vim.fn.buflisted(b) == 1
        end, vim.api.nvim_list_bufs())
      elseif scope == 'visible' then
        buffers = vim.tbl_filter(function(b)
          return utils.buf_valid(b) and vim.fn.buflisted(b) == 1 and #vim.fn.win_findbuf(b) > 0
        end, vim.api.nvim_list_bufs())
      end

      -- Collect diagnostics for each buffer
      for _, bufnr in ipairs(buffers) do
        local filename = vim.api.nvim_buf_get_name(bufnr)
        local diagnostics = vim.diagnostic.get(bufnr)

        if #diagnostics > 0 then
          local diag_lines = {}
          table.insert(diag_lines, string.format('# %s DIAGNOSTICS', filename))

          for _, diag in ipairs(diagnostics) do
            local severity = ({ 'ERROR', 'WARN', 'INFO', 'HINT' })[diag.severity] or 'UNKNOWN'
            local line_text = vim.api.nvim_buf_get_lines(bufnr, diag.lnum, diag.lnum + 1, false)[1] or ''

            table.insert(
              diag_lines,
              string.format(
                '%s line=%d-%d: %s\n  > %s',
                severity,
                diag.lnum + 1,
                diag.end_lnum and (diag.end_lnum + 1) or (diag.lnum + 1),
                diag.message,
                line_text
              )
            )
          end

          table.insert(out, {
            type = 'text',
            data = table.concat(diag_lines, '\n'),
          })
        end
      end

      return out
    end,
  },

  git = {
    description = 'Retrieves git diff information. Requires git to be installed. Useful for discussing code changes or explaining the purpose of modifications.',

    schema = {
      type = 'object',
      required = { 'diff' },
      properties = {
        diff = {
          type = 'string',
          description = 'Git diff to include in chat context.',
          enum = { 'unstaged', 'staged', '<sha>' },
          default = 'unstaged',
        },
      },
    },

    resolve = function(input, source)
      local cmd = {
        'git',
        '-C',
        source.cwd(),
        'diff',
        '--no-color',
        '--no-ext-diff',
      }

      if input.diff == 'staged' then
        table.insert(cmd, '--staged')
      elseif input.diff == 'unstaged' then
        table.insert(cmd, '--')
      else
        table.insert(cmd, input.diff)
      end

      local out = utils.system(cmd)

      return {
        {
          type = 'text',
          data = out.stdout,
        },
      }
    end,
  },

  url = {
    description = 'Fetches content from a specified URL. Useful for referencing documentation, examples, or other online resources.',

    schema = {
      type = 'object',
      required = { 'url' },
      properties = {
        url = {
          type = 'string',
          description = 'URL to include in chat context.',
        },
      },
    },

    resolve = function(input)
      utils.schedule_main()
      return {
        tools.get_url(input.url),
      }
    end,
  },

  register = {
    description = 'Provides access to the content of a specified Vim register. Useful for discussing yanked text, clipboard content, or previously executed commands.',

    schema = {
      type = 'object',
      required = { 'register' },
      properties = {
        register = {
          type = 'string',
          description = 'Register to include in chat context.',
          enum = {
            '+',
            '*',
            '"',
            '0',
            '-',
            '.',
            '%',
            ':',
            '#',
            '=',
            '/',
          },
          default = '+',
        },
      },
    },

    resolve = function(input)
      utils.schedule_main()
      local lines = vim.fn.getreg(input.register)
      if not lines or lines == '' then
        return {}
      end

      return {
        {
          type = 'text',
          data = lines,
        },
      }
    end,
  },

  system = {
    description = [[Executes a system shell command and retrieves its output.

Important:
- Prefer specialized tools when available (e.g., use 'url' instead of 'curl', use 'grep' or 'glob' instead of 'find' commands).
- When necessary, use read-only commands that don't modify system state. Avoid commands that perform writes or destructive operations.
]],

    schema = {
      type = 'object',
      required = { 'command' },
      properties = {
        command = {
          type = 'string',
          description = 'System command to include in chat context.',
        },
      },
    },

    resolve = function(input)
      utils.schedule_main()

      local shell, shell_flag
      if vim.fn.has('win32') == 1 then
        shell, shell_flag = 'cmd.exe', '/c'
      else
        shell, shell_flag = 'sh', '-c'
      end

      local out = utils.system({ shell, shell_flag, input.command })
      if not out then
        return {}
      end

      if out.code ~= 0 then
        if out.stderr and out.stderr ~= '' then
          error(out.stderr)
        else
          error('Command failed with exit code ' .. out.code)
        end
      end

      return {
        {
          type = 'text',
          data = out.stdout,
        },
      }
    end,
  },
}
