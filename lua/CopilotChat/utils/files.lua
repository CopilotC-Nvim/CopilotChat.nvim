local async = require('plenary.async')

local M = {}

M.scan_args = {
  max_count = 2500,
  max_depth = 50,
  no_ignore = false,
}

local function filter_files(files, max_count)
  local filetype = require('plenary.filetype')

  files = vim.tbl_filter(function(file)
    if file == nil or file == '' then
      return false
    end

    local ft = filetype.detect(file, {
      fs_access = false,
    })

    if ft == '' or not ft then
      return false
    end

    return true
  end, files)
  if max_count and max_count > 0 then
    files = vim.list_slice(files, 1, max_count)
  end

  return files
end

---@class CopilotChat.utils.ScanOpts
---@field max_count number? The maximum number of files to scan
---@field max_depth number? The maximum depth to scan
---@field pattern? string The glob pattern to match files
---@field hidden? boolean Whether to include hidden files
---@field no_ignore? boolean Whether to respect or ignore .gitignore

--- Scan a directory
---@param path string
---@param opts CopilotChat.utils.ScanOpts?
---@async
M.glob = async.wrap(function(path, opts, callback)
  opts = vim.tbl_deep_extend('force', M.scan_args, opts or {})

  -- Use ripgrep if available
  if vim.fn.executable('rg') == 1 then
    local cmd = { 'rg' }

    if opts.pattern then
      table.insert(cmd, '-g')
      table.insert(cmd, opts.pattern)
    end

    if opts.max_depth then
      table.insert(cmd, '--max-depth')
      table.insert(cmd, tostring(opts.max_depth))
    end

    if opts.no_ignore then
      table.insert(cmd, '--no-ignore')
    end

    if opts.hidden then
      table.insert(cmd, '--hidden')
    end

    table.insert(cmd, '--files')

    vim.system(cmd, { cwd = path, text = true }, function(result)
      local files = {}
      if result and result.code == 0 and result.stdout ~= '' then
        files = filter_files(vim.split(result.stdout, '\n'), opts.max_count)
      end

      callback(files)
    end)

    return
  end

  -- Fallback to vim.uv.fs_scandir
  local matchers = {}
  if opts.pattern then
    local file_pattern = vim.glob.to_lpeg(opts.pattern)
    local path_pattern = vim.lpeg.P(path .. '/') * file_pattern

    table.insert(matchers, function(name, dir)
      return file_pattern:match(name) or path_pattern:match(dir .. '/' .. name)
    end)
  end

  if not opts.hidden then
    table.insert(matchers, function(name)
      return not name:match('^%.')
    end)
  end

  local data = {}
  local next_dir = { path }
  local current_depths = { [path] = 1 }

  local function read_dir(err, fd)
    local current_dir = table.remove(next_dir, 1)
    local depth = current_depths[current_dir] or 1

    if not err and fd then
      while true do
        local name, typ = vim.uv.fs_scandir_next(fd)
        if name == nil then
          break
        end

        local full_path = current_dir .. '/' .. name

        if typ == 'directory' and not name:match('^%.git') then
          if not opts.max_depth or depth < opts.max_depth then
            table.insert(next_dir, full_path)
            current_depths[full_path] = depth + 1
          end
        else
          local match = true
          for _, matcher in ipairs(matchers) do
            if not matcher(name, current_dir) then
              match = false
              break
            end
          end

          if match then
            table.insert(data, full_path)
          end
        end
      end
    end

    if #next_dir == 0 then
      callback(data)
    else
      vim.uv.fs_scandir(next_dir[1], read_dir)
    end
  end

  vim.uv.fs_scandir(path, read_dir)
end, 3)

--- Grep a directory
---@param path string The path to search
---@param opts CopilotChat.utils.ScanOpts?
M.grep = async.wrap(function(path, opts, callback)
  opts = vim.tbl_deep_extend('force', M.scan_args, opts or {})
  local cmd = {}

  if vim.fn.executable('rg') == 1 then
    table.insert(cmd, 'rg')

    if opts.max_depth then
      table.insert(cmd, '--max-depth')
      table.insert(cmd, tostring(opts.max_depth))
    end

    if opts.no_ignore then
      table.insert(cmd, '--no-ignore')
    end

    if opts.hidden then
      table.insert(cmd, '--hidden')
    end

    table.insert(cmd, '--files-with-matches')
    table.insert(cmd, '--ignore-case')

    if opts.pattern then
      table.insert(cmd, '-e')
      table.insert(cmd, "'" .. opts.pattern .. "'")
    end
  elseif vim.fn.executable('grep') == 1 then
    table.insert(cmd, 'grep')
    table.insert(cmd, '-rli')

    if opts.pattern then
      table.insert(cmd, '-e')
      table.insert(cmd, "'" .. opts.pattern .. "'")
    end
  end

  if vim.tbl_isempty(cmd) then
    error('No executable found for grep')
    return
  end

  vim.system(cmd, { cwd = path, text = true }, function(result)
    local files = {}
    if result and result.code == 0 and result.stdout ~= '' then
      files = filter_files(vim.split(result.stdout, '\n'), opts.max_count)
    end

    callback(files)
  end)
end, 3)

--- Read a file
---@param path string The file path
---@async
function M.read_file(path)
  local err, fd = async.uv.fs_open(path, 'r', 438)
  if err or not fd then
    return nil
  end

  local err, stat = async.uv.fs_fstat(fd)
  if err or not stat then
    async.uv.fs_close(fd)
    return nil
  end

  local err, data = async.uv.fs_read(fd, stat.size, 0)
  async.uv.fs_close(fd)
  if err or not data then
    return nil
  end
  return data
end

--- Write data to a file
---@param path string The file path
---@param data string The data to write
---@return boolean
function M.write_file(path, data)
  M.schedule_main()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':p:h'), 'p')

  local err, fd = async.uv.fs_open(path, 'w', 438)
  if err or not fd then
    return false
  end

  local err = async.uv.fs_write(fd, data, 0)
  if err then
    async.uv.fs_close(fd)
    return false
  end

  async.uv.fs_close(fd)
  return true
end

--- Check if file paths are the same
---@param file1 string? The first file path
---@param file2 string? The second file path
---@return boolean
function M.filename_same(file1, file2)
  if not file1 or not file2 then
    return false
  end
  return vim.fs.normalize(file1) == vim.fs.normalize(file2)
end

--- Get the filetype of a file
---@param filename string The file name
---@return string|nil
function M.filetype(filename)
  local filetype = require('plenary.filetype')

  local ft = filetype.detect(filename, {
    fs_access = false,
  })

  if ft == '' or not ft and not vim.in_fast_event() then
    return vim.filetype.match({ filename = filename })
  end

  return ft
end

--- Get the mimetype from filetype
---@param filetype string?
---@return string
function M.filetype_to_mimetype(filetype)
  if not filetype or filetype == '' then
    return 'text/plain'
  end
  if filetype == 'json' or filetype == 'yaml' then
    return 'application/' .. filetype
  end
  if filetype == 'html' or filetype == 'css' then
    return 'text/' .. filetype
  end
  if filetype:find('/') then
    return filetype
  end
  return 'text/x-' .. filetype
end

--- Get the filetype from mimetype
---@param mimetype string?
---@return string
function M.mimetype_to_filetype(mimetype)
  if not mimetype or mimetype == '' then
    return 'text'
  end

  local out = mimetype:gsub('^text/x%-', '')
  out = out:gsub('^text/', '')
  out = out:gsub('^application/', '')
  out = out:gsub('^image/', '')
  out = out:gsub('^video/', '')
  out = out:gsub('^audio/', '')
  return out
end

--- Convert a URI to a file name
---@param uri string The URI
---@return string
function M.uri_to_filename(uri)
  if not uri or uri == '' then
    return uri
  end
  local ok, fname = pcall(vim.uri_to_fname, uri)
  if not ok or not fname or fname == '' then
    return uri
  end
  return fname
end

return M
