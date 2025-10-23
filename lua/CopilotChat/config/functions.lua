local resources = require('CopilotChat.resources')
local utils = require('CopilotChat.utils')
local files = require('CopilotChat.utils.files')

--- Get diagnostics for a buffer and format them as text
---@param bufnr number
---@param start_line number?
---@param end_line number?
---@return string
local function get_diagnostics_text(bufnr, start_line, end_line)
  local diagnostics = vim.diagnostic.get(bufnr, {
    severity = { min = vim.diagnostic.severity.HINT },
  })

  if #diagnostics == 0 then
    return ''
  end

  local diag_lines = { '\n--- Diagnostics ---' }
  for _, diag in ipairs(diagnostics) do
    local diag_lnum = diag.lnum + 1
    -- If range is specified, filter diagnostics within range
    if not start_line or (diag_lnum >= start_line and diag_lnum <= end_line) then
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
  end

  return #diag_lines > 1 and table.concat(diag_lines, '\n') or ''
end

---@class CopilotChat.config.functions.Function
---@field description string?
---@field schema table?
---@field group string?
---@field uri string?
---@field resolve fun(input: table, source: CopilotChat.ui.chat.Source):CopilotChat.client.Resource[]

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
            return files.glob(source.cwd(), {
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

      utils.schedule_main()
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

  buffer = {
    group = 'copilot',
    uri = 'neovim://buffer/{scope}',
    description = 'Retrieves content from buffer(s) with diagnostics. Scope can be a buffer number, filename, or one of: active, visible, listed, quickfix.',

    schema = {
      type = 'object',
      required = { 'scope' },
      properties = {
        scope = {
          type = 'string',
          description = 'Buffer scope: active (current), visible (shown in windows), listed (all listed buffers), quickfix (buffers in quickfix list), or a specific buffer number/filename.',
          enum = function()
            local opts = {
              { display = 'active (current buffer)', value = 'active' },
              { display = 'visible (all visible buffers)', value = 'visible' },
              { display = 'listed (all listed buffers)', value = 'listed' },
              { display = 'quickfix (buffers in quickfix)', value = 'quickfix' },
            }

            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
              if utils.buf_valid(buf) and vim.fn.buflisted(buf) == 1 then
                local name = vim.api.nvim_buf_get_name(buf)
                if name and name ~= '' then
                  local display_name = vim.fn.fnamemodify(name, ':~:.')
                  table.insert(opts, { display = display_name, value = name })
                end
              end
            end
            return opts
          end,
          default = 'active',
        },
      },
    },

    resolve = function(input, source)
      utils.schedule_main()
      local scope = input.scope or 'active'
      local buffers = {}

      -- Determine which buffers to include based on scope
      if scope == 'active' then
        if source and source.bufnr and utils.buf_valid(source.bufnr) then
          buffers = { source.bufnr }
        end
      elseif scope == 'visible' then
        buffers = vim.tbl_filter(function(b)
          return utils.buf_valid(b) and vim.fn.buflisted(b) == 1 and #vim.fn.win_findbuf(b) > 0
        end, vim.api.nvim_list_bufs())
      elseif scope == 'listed' then
        buffers = vim.tbl_filter(function(b)
          return utils.buf_valid(b) and vim.fn.buflisted(b) == 1
        end, vim.api.nvim_list_bufs())
      elseif scope == 'quickfix' then
        local items = vim.fn.getqflist()
        local file_to_bufnr = {}
        for _, item in ipairs(items) do
          local filename = item.filename or vim.api.nvim_buf_get_name(item.bufnr)
          if filename and item.bufnr and utils.buf_valid(item.bufnr) then
            file_to_bufnr[filename] = item.bufnr
          end
        end
        buffers = vim.tbl_values(file_to_bufnr)
      elseif tonumber(scope) then
        local bufnr = tonumber(scope)
        if utils.buf_valid(bufnr) then
          buffers = { bufnr }
        end
      end

      if #buffers == 0 then
        error('No buffers found for input: ' .. scope)
      end

      local results = {}
      for _, bufnr in ipairs(buffers) do
        local name = vim.api.nvim_buf_get_name(bufnr)
        local data, mimetype = resources.get_buffer(bufnr)
        if data then
          local diag_text = get_diagnostics_text(bufnr)
          if diag_text ~= '' then
            data = data .. diag_text
          end

          table.insert(results, {
            uri = 'buffer://' .. bufnr,
            name = name,
            mimetype = mimetype,
            data = data,
          })
        end
      end

      return results
    end,
  },

  selection = {
    group = 'copilot',
    uri = 'neovim://selection',
    description = 'Includes the content of the current visual selection with diagnostics. Useful for discussing specific code snippets or text blocks.',

    resolve = function(_, source)
      utils.schedule_main()

      local select = require('CopilotChat.select')
      local selection = select.get(source.bufnr)
      if not selection then
        return {}
      end

      local data = selection.content
      local diag_text = get_diagnostics_text(source.bufnr, selection.start_line, selection.end_line)
      if diag_text ~= '' then
        data = data .. diag_text
      end

      return {
        {
          uri = 'neovim://selection',
          name = selection.filename,
          mimetype = files.mimetype_to_filetype(selection.filetype),
          data = data,
          annotations = {
            start_line = selection.start_line,
            end_line = selection.end_line,
          },
        },
      }
    end,
  },

  clipboard = {
    group = 'copilot',
    uri = 'neovim://clipboard',
    description = 'Provides access to the system clipboard content. Useful for discussing copied text or code snippets.',

    resolve = function()
      utils.schedule_main()
      local lines = vim.fn.getreg('+')
      if not lines or lines == '' then
        return {}
      end

      return {
        {
          uri = 'neovim://clipboard',
          mimetype = 'text/plain',
          data = lines,
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
      local out = files.glob(source.cwd(), {
        pattern = input.pattern,
      })

      return {
        {
          uri = 'files://glob/' .. input.pattern,
          mimetype = 'text/plain',
          data = table.concat(out, '\n'),
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
      local out = files.grep(source.cwd(), {
        pattern = input.pattern,
      })

      return {
        {
          uri = 'files://grep/' .. input.pattern,
          mimetype = 'text/plain',
          data = table.concat(out, '\n'),
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

  bash = {
    group = 'copilot',
    description = 'Executes a bash command and returns its output. Useful for running shell commands, checking file contents, or gathering system information.',

    schema = {
      type = 'object',
      required = { 'command' },
      properties = {
        command = {
          type = 'string',
          description = 'Bash command to execute.',
        },
      },
    },

    resolve = function(input, source)
      local cmd = { 'bash', '-c', input.command }
      local out = utils.system(cmd, source.cwd())

      return {
        {
          data = out.stdout,
        },
      }
    end,
  },

  edit = {
    group = 'copilot',
    description = 'Applies a unified diff to a file. The diff should be in unified diff format (similar to diff -U0 output).',

    schema = {
      type = 'object',
      required = { 'filename', 'diff' },
      properties = {
        filename = {
          type = 'string',
          description = 'Path to file to edit.',
        },
        diff = {
          type = 'string',
          description = 'Unified diff content to apply to the file.',
        },
      },
    },

    resolve = function(input, source)
      utils.schedule_main()

      local select = require('CopilotChat.select')
      local diff = require('CopilotChat.utils.diff')

      -- Find or create the buffer for the file
      local filename = input.filename
      local diff_bufnr = nil

      -- Try to find matching buffer first
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if files.filename_same(vim.api.nvim_buf_get_name(buf), filename) then
          diff_bufnr = buf
          break
        end
      end

      -- If still not found, try to load or create buffer
      if not diff_bufnr then
        diff_bufnr = vim.fn.bufadd(filename)
        vim.fn.bufload(diff_bufnr)
      end

      -- Get current buffer content
      local lines = vim.api.nvim_buf_get_lines(diff_bufnr, 0, -1, false)
      local content = table.concat(lines, '\n')

      -- Apply the unified diff
      local new_lines, applied, first, last = diff.apply_unified_diff(input.diff, content)

      if applied then
        -- Apply changes to buffer
        vim.api.nvim_buf_set_lines(diff_bufnr, 0, -1, false, new_lines)

        -- If source window is valid, switch to the edited buffer and highlight changes
        if source and source.winnr and vim.api.nvim_win_is_valid(source.winnr) then
          vim.api.nvim_win_set_buf(source.winnr, diff_bufnr)
          if first and last then
            select.set(diff_bufnr, source.winnr, first, last)
            select.highlight(diff_bufnr)
          end
        end

        return {
          {
            data = string.format('Successfully applied diff to %s (lines %d-%d)', filename, first or 0, last or 0),
          },
        }
      else
        error('Failed to apply diff to ' .. filename)
      end
    end,
  },
}
