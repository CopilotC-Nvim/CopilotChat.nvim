local resources = require('CopilotChat.resources')
local utils = require('CopilotChat.utils')

---@class CopilotChat.config.functions.Function
---@field description string?
---@field schema table?
---@field group string?
---@field uri string?
---@field resolve fun(input: table, source: CopilotChat.source, prompt: string):table<CopilotChat.client.Resource>

---@type table<string, CopilotChat.config.functions.Function>
return {
  file = {
    group = 'copilot',
    uri = 'file://{path}',
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
      utils.schedule_main()
      local data, mimetype = resources.get_file(input.path)
      if not data then
        error('File not found: ' .. input.path)
      end

      return {
        {
          uri = 'file://' .. input.path,
          name = input.path,
          mimetype = mimetype,
          data = data,
        },
      }
    end,
  },

  glob = {
    group = 'copilot',
    uri = 'files://glob/{pattern}',
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
          uri = 'files://glob/' .. input.pattern,
          mimetype = 'text/plain',
          data = table.concat(files, '\n'),
        },
      }
    end,
  },

  grep = {
    group = 'copilot',
    uri = 'files://grep/{pattern}',
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
          uri = 'files://grep/' .. input.pattern,
          mimetype = 'text/plain',
          data = table.concat(files, '\n'),
        },
      }
    end,
  },

  buffer = {
    group = 'copilot',
    uri = 'buffer://{name}',
    description = 'Retrieves content from a specific buffer. Useful for discussing or analyzing code from a particular file that is currently loaded.',

    schema = {
      type = 'object',
      required = { 'name' },
      properties = {
        name = {
          type = 'string',
          description = 'Buffer filename to include in chat context.',
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
      local data, mimetype = resources.get_buffer(found_buf)
      if not data then
        error('Buffer not found: ' .. name)
      end
      return {
        {
          uri = 'buffer://' .. name,
          name = name,
          mimetype = mimetype,
          data = data,
        },
      }
    end,
  },

  buffers = {
    group = 'copilot',
    uri = 'buffers://{scope}',
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
      return vim
        .iter(vim.api.nvim_list_bufs())
        :filter(function(bufnr)
          return utils.buf_valid(bufnr)
            and vim.fn.buflisted(bufnr) == 1
            and (input.scope == 'listed' or #vim.fn.win_findbuf(bufnr) > 0)
        end)
        :map(function(bufnr)
          local name = vim.api.nvim_buf_get_name(bufnr)
          local data, mimetype = resources.get_buffer(bufnr)
          if not data then
            return nil
          end
          return {
            uri = 'buffer://' .. name,
            name = name,
            mimetype = mimetype,
            data = data,
          }
        end)
        :filter(function(file_data)
          return file_data ~= nil
        end)
        :totable()
    end,
  },

  quickfix = {
    group = 'copilot',
    uri = 'neovim://quickfix',
    description = 'Includes the content of all files referenced in the current quickfix list. Useful for discussing compilation errors, search results, or other collected locations.',

    resolve = function()
      utils.schedule_main()

      local items = vim.fn.getqflist()
      if not items or #items == 0 then
        return {}
      end

      local file_to_bufnr = {}
      for _, item in ipairs(items) do
        local filename = item.filename or vim.api.nvim_buf_get_name(item.bufnr)
        if filename then
          if item.bufnr and utils.buf_valid(item.bufnr) then
            file_to_bufnr[filename] = item.bufnr
          else
            file_to_bufnr[filename] = false
          end
        end
      end

      return vim
        .iter(vim.tbl_keys(file_to_bufnr))
        :map(function(file)
          local bufnr = file_to_bufnr[file]
          local data, mimetype, uri
          if bufnr and bufnr ~= false then
            data, mimetype = resources.get_buffer(bufnr)
            uri = 'buffer://' .. file
          else
            data, mimetype = resources.get_file(file)
            uri = 'file://' .. file
          end
          if not data then
            return nil
          end
          return {
            uri = uri,
            name = file,
            mimetype = mimetype,
            data = data,
          }
        end)
        :filter(function(file_data)
          return file_data ~= nil
        end)
        :totable()
    end,
  },

  diagnostics = {
    group = 'copilot',
    uri = 'neovim://diagnostics/{scope}/{severity}',
    description = 'Collects code diagnostics (errors, warnings, etc.) from specified buffers. Helpful for troubleshooting and fixing code issues.',

    schema = {
      type = 'object',
      required = { 'scope', 'severity' },
      properties = {
        scope = {
          type = 'string',
          description = 'Scope of buffers to use for retrieving diagnostics.',
          enum = { 'current', 'listed', 'visible' },
          default = 'current',
        },
        severity = {
          type = 'string',
          description = 'Minimum severity level of diagnostics to include.',
          enum = { 'error', 'warn', 'info', 'hint' },
          default = 'warn',
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
      else
        buffers = vim.tbl_filter(function(b)
          return utils.buf_valid(b) and vim.api.nvim_buf_get_name(b) == input.scope
        end, vim.api.nvim_list_bufs())
      end

      -- Collect diagnostics for each buffer
      for _, bufnr in ipairs(buffers) do
        local name = vim.api.nvim_buf_get_name(bufnr)
        local diagnostics = vim.diagnostic.get(bufnr, {
          severity = {
            min = vim.diagnostic.severity[input.severity:upper()],
          },
        })

        if #diagnostics > 0 then
          local diag_lines = {}
          for _, diag in ipairs(diagnostics) do
            local severity = vim.diagnostic.severity[diag.severity] or 'UNKNOWN'
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
            uri = 'neovim://diagnostics/' .. name,
            mimetype = 'text/plain',
            data = table.concat(diag_lines, '\n'),
          })
        end
      end

      return out
    end,
  },

  register = {
    group = 'copilot',
    uri = 'neovim://register/{register}',
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
          uri = 'neovim://register/' .. input.register,
          mimetype = 'text/plain',
          data = lines,
        },
      }
    end,
  },

  gitdiff = {
    group = 'copilot',
    uri = 'git://diff/{target}',
    description = 'Retrieves git diff information. Requires git to be installed. Useful for discussing code changes or explaining the purpose of modifications.',

    schema = {
      type = 'object',
      required = { 'target' },
      properties = {
        target = {
          type = 'string',
          description = 'Target to diff against.',
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

      if input.target == 'staged' then
        table.insert(cmd, '--staged')
      elseif input.target == 'unstaged' then
        table.insert(cmd, '--')
      else
        table.insert(cmd, input.target)
      end

      local out = utils.system(cmd)

      return {
        {
          uri = 'git://diff/' .. input.target,
          mimetype = 'text/plain',
          data = out.stdout,
        },
      }
    end,
  },

  gitstatus = {
    group = 'copilot',
    uri = 'git://status',
    description = 'Retrieves the status of the current git repository. Useful for discussing changes, commits, and other git-related tasks.',

    resolve = function(_, source)
      local cmd = {
        'git',
        '-C',
        source.cwd(),
        'status',
      }

      local out = utils.system(cmd)

      return {
        {
          uri = 'git://status',
          mimetype = 'text/plain',
          data = out.stdout,
        },
      }
    end,
  },

  url = {
    group = 'copilot',
    uri = 'https://{url}',
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
      if not input.url:match('^https?://') then
        input.url = 'https://' .. input.url
      end

      local data, mimetype = resources.get_url(input.url)
      if not data then
        error('URL not found: ' .. input.url)
      end

      return {
        {
          uri = input.url,
          mimetype = mimetype,
          data = data,
        },
      }
    end,
  },
}
