local tools = require('CopilotChat.tools')
local utils = require('CopilotChat.utils')

---@class CopilotChat.config.tools.Content
---@field type 'text' | 'image' | 'audio' | 'resource' | 'error'

---@class CopilotChat.config.tools.ErrorContent : CopilotChat.config.tools.Content
---@field type 'error'
---@field data string

---@class CopilotChat.config.tools.TextContent : CopilotChat.config.tools.Content
---@field type 'text'
---@field data string

---@class CopilotChat.config.tools.ImageContent : CopilotChat.config.tools.Content
---@field type 'image'
---@field data string
---@field mimetype string

---@class CopilotChat.config.tools.AudioContent : CopilotChat.config.tools.Content
---@field type 'image'
---@field data string
---@field mimetype string

---@class CopilotChat.config.tools.ResourceContent : CopilotChat.config.tools.Content
---@field type 'resource'
---@field uri string
---@field data string
---@field mimetype string

---@class CopilotChat.config.tools.Tool
---@field description string?
---@field schema table?
---@field resolve fun(input: table, source: CopilotChat.source, prompt: string):table<CopilotChat.config.tools.Content>

---@type table<string, CopilotChat.config.tools.Tool>
return {
  buffer = {
    description = 'Includes specified buffer in chat context.',

    schema = {
      type = 'object',
      properties = {
        bufnr = {
          type = 'integer',
          description = 'Buffer number to include in chat context.',
          enum = function()
            return vim.tbl_map(
              function(buf)
                return buf
              end,
              vim.tbl_filter(function(buf)
                return utils.buf_valid(buf) and vim.fn.buflisted(buf) == 1
              end, vim.api.nvim_list_bufs())
            )
          end,
        },
      },
    },

    resolve = function(input, source)
      utils.schedule_main()
      return {
        tools.get_buffer(input.bufnr or source.bufnr),
      }
    end,
  },

  buffers = {
    description = 'Includes all buffers in chat context.',

    schema = {
      type = 'object',
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
    description = 'Includes content of provided file in chat context.',

    schema = {
      type = 'object',
      required = { 'file' },
      properties = {
        file = {
          type = 'string',
          description = 'File to include in chat context.',
          enum = function(source)
            return utils.scan_dir(source.cwd(), {
              max_count = 0,
            })
          end,
        },
      },
    },

    resolve = function(input)
      utils.schedule_main()
      return {
        tools.get_file(utils.filepath(input.file), utils.filetype(input.file)),
      }
    end,
  },

  files = {
    description = 'Includes all non-hidden files in the current workspace in chat context.',

    schema = {
      type = 'object',
      properties = {
        glob = {
          type = 'string',
          description = 'Glob pattern to match files.',
          default = '**/*',
        },
      },
    },

    resolve = function(input, source)
      local files = utils.scan_dir(source.cwd(), {
        glob = input.glob,
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
          return tools.get_file(file.name, file.ft)
        end)
        :filter(function(file_data)
          return file_data ~= nil
        end)
        :totable()
    end,
  },

  filenames = {
    description = 'Includes names of all non-hidden files in the current workspace in chat context.',

    schema = {
      type = 'object',
      properties = {
        glob = {
          type = 'string',
          description = 'Glob pattern to match files.',
          default = '**/*',
        },
      },
    },

    resolve = function(input, source)
      local out = {}
      local files = utils.scan_dir(source.cwd(), {
        glob = input.glob,
      })

      local chunk_size = 100
      for i = 1, #files, chunk_size do
        local chunk = {}
        for j = i, math.min(i + chunk_size - 1, #files) do
          table.insert(chunk, files[j])
        end

        table.insert(out, {
          type = 'text',
          data = table.concat(chunk, '\n'),
        })
      end

      return out
    end,
  },

  diagnostics = {
    description = 'Includes diagnostics of specified buffers in chat context.',

    schema = {
      type = 'object',
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
    description = 'Requires `git`. Includes current git diff in chat context.',

    schema = {
      type = 'object',
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
    description = 'Includes content of provided URL in chat context.',

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
    description = 'Includes contents of register in chat context.',

    schema = {
      type = 'object',
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
          return tools.get_file(file.name, file.ft)
        end)
        :filter(function(file_data)
          return file_data ~= nil
        end)
        :totable()
    end,
  },

  system = {
    description = [[Includes output of provided system shell command in chat context.

Important:
- Only use system commands as last resort, they are run every time the context is requested.
- For example instead of curl use the url context, instead of finding and grepping try to check if there is any context that can query the data you need instead.
- If you absolutely need to run a system command, try to use read-only commands and avoid commands that modify the system state.
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
          return {
            {
              type = 'error',
              data = out.stderr,
            },
          }
        else
          return {
            {
              type = 'error',
              data = 'Command failed with exit code ' .. out.code,
            },
          }
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
