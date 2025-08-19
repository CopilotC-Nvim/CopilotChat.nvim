local async = require('plenary.async')
local curl = require('plenary.curl')
local log = require('plenary.log')

local M = {}
M.timers = {}

M.scan_args = {
  max_count = 2500,
  max_depth = 50,
  no_ignore = false,
}

M.curl_args = {
  timeout = 30000,
  raw = {
    '--retry',
    '2',
    '--retry-delay',
    '1',
    '--keepalive-time',
    '60',
    '--no-compressed',
    '--connect-timeout',
    '10',
    '--tcp-nodelay',
    '--no-buffer',
  },
}

---@class Class
---@field new fun(...):table
---@field init fun(self, ...)

--- Create class
---@param fn function The class constructor
---@param parent table? The parent class
---@return Class
function M.class(fn, parent)
  local out = {}
  out.__index = out

  local mt = {
    __call = function(cls, ...)
      return cls.new(...)
    end,
  }

  if parent then
    mt.__index = parent
  end

  setmetatable(out, mt)

  function out.new(...)
    local self = setmetatable({}, out)
    fn(self, ...)
    return self
  end

  function out.init(self, ...)
    fn(self, ...)
  end

  return out
end

---@class OrderedMap<K, V>
---@field set fun(self:OrderedMap, key:any, value:any)
---@field get fun(self:OrderedMap, key:any):any
---@field keys fun(self:OrderedMap):table
---@field values fun(self:OrderedMap):table

--- Create an ordered map
---@generic K, V
---@return OrderedMap<K, V>
function M.ordered_map()
  return {
    _keys = {},
    _data = {},
    set = function(self, key, value)
      if not self._data[key] then
        table.insert(self._keys, key)
      end
      self._data[key] = value
    end,

    get = function(self, key)
      return self._data[key]
    end,

    keys = function(self)
      return self._keys
    end,

    values = function(self)
      local result = {}
      for _, key in ipairs(self._keys) do
        table.insert(result, self._data[key])
      end
      return result
    end,
  }
end

--- Convert arguments to a table
---@param ... any The arguments
---@return table
function M.to_table(...)
  local result = {}
  for i = 1, select('#', ...) do
    local x = select(i, ...)
    if type(x) == 'table' then
      for _, v in ipairs(x) do
        table.insert(result, v)
      end
    elseif x ~= nil then
      table.insert(result, x)
    end
  end
  return result
end

---@class StringBuffer
---@field add fun(self:StringBuffer, s:string)
---@field set fun(self:StringBuffer, s:string)
---@field tostring fun(self:StringBuffer):string

--- Create a string buffer for efficient string concatenation
---@return StringBuffer
function M.string_buffer()
  return {
    _buf = { '' },

    add = function(self, s)
      table.insert(self._buf, s)
      -- Keep track of lengths to know when to merge
      for i = #self._buf - 1, 1, -1 do
        if #self._buf[i] > #self._buf[i + 1] then
          break
        end
        self._buf[i] = self._buf[i] .. table.remove(self._buf)
      end
    end,

    set = function(self, s)
      self._buf = { s }
    end,

    -- Get final string
    tostring = function(self)
      return table.concat(self._buf)
    end,
  }
end

--- Writes text to a temporary file and returns path
---@param text string The text to write
---@return string
function M.temp_file(text)
  local temp_file = os.tmpname()
  local f = io.open(temp_file, 'w+')
  if f == nil then
    error('Could not open file: ' .. temp_file)
  end
  f:write(text)
  f:close()
  return temp_file
end

--- Return to normal mode
function M.return_to_normal_mode()
  local mode = vim.fn.mode():lower()
  if mode:find('v') then
    vim.cmd([[execute "normal! \<Esc>"]])
  end
  vim.cmd('stopinsert')
end

--- Debounce a function
function M.debounce(id, fn, delay)
  if M.timers[id] then
    M.timers[id]:stop()
    M.timers[id] = nil
  end
  M.timers[id] = vim.defer_fn(fn, delay)
end

--- Check if a buffer is valid
--- Check if the buffer is not a terminal
---@param bufnr number? The buffer number
---@return boolean
function M.buf_valid(bufnr)
  return bufnr
      and vim.api.nvim_buf_is_valid(bufnr)
      and vim.api.nvim_buf_is_loaded(bufnr)
      and vim.bo[bufnr].buftype ~= 'terminal'
    or false
end

--- Check if file paths are the same
---@param file1 string? The first file path
---@param file2 string? The second file path
---@return boolean
function M.filename_same(file1, file2)
  if not file1 or not file2 then
    return false
  end
  return vim.fn.fnamemodify(file1, ':p') == vim.fn.fnamemodify(file2, ':p')
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
  if not ok or M.empty(fname) then
    return uri
  end
  return fname
end

--- Get the file name
---@param filepath string The file path
---@return string
function M.filename(filepath)
  return vim.fs.basename(filepath)
end

--- Generate a UUID
---@return string
function M.uuid()
  local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
  return (
    string.gsub(template, '[xy]', function(c)
      local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
      return string.format('%x', v)
    end)
  )
end

--- Make a string from arguments
---@vararg any The arguments
---@return string
function M.make_string(...)
  local t = {}
  for i = 1, select('#', ...) do
    local x = select(i, ...)

    if type(x) == 'table' then
      x = vim.inspect(x)
    else
      x = tostring(x)
      while true do
        local new_x = x:gsub('^[^:]+:%d+: ', '')
        if new_x == x then
          break
        end
        x = new_x
      end
    end

    t[#t + 1] = x
  end
  return table.concat(t, ' ')
end

--- Decode json
---@param body string The json string
---@return table, string?
function M.json_decode(body)
  local ok, data = pcall(vim.json.decode, body, {
    luanil = {
      object = true,
      array = true,
    },
  })

  if ok then
    return data
  end

  return {}, data
end

--- Store curl global arguments
---@param args table The arguments
---@return table
function M.curl_store_args(args)
  M.curl_args = vim.tbl_deep_extend('force', M.curl_args, args)
  return M.curl_args
end

--- Send curl get request
---@param url string The url
---@param opts table? The options
---@async
M.curl_get = async.wrap(function(url, opts, callback)
  log.debug('GET request:', url, opts)
  local args = {
    on_error = function(err)
      log.debug('GET error:', err)
      callback(nil, err and err.stderr or err)
    end,
  }

  args = vim.tbl_deep_extend('force', M.curl_args, args)
  args = vim.tbl_deep_extend('force', args, opts or {})

  args.callback = function(response)
    log.debug('GET response:', response)
    if response and not vim.startswith(tostring(response.status), '20') then
      callback(response, response.body)
      return
    end

    if not args.json_response then
      callback(response)
      return
    end

    local body, err = M.json_decode(tostring(response.body))
    if err then
      callback(response, err)
    else
      response.body = body
      callback(response)
    end
  end

  curl.get(url, args)
end, 3)

--- Send curl post request
---@param url string The url
---@param opts table? The options
---@async
M.curl_post = async.wrap(function(url, opts, callback)
  log.debug('POST request:', url, opts)
  local args = {
    on_error = function(err)
      log.debug('POST error:', err)
      callback(nil, err and err.stderr or err)
    end,
  }

  args = vim.tbl_deep_extend('force', M.curl_args, args)
  args = vim.tbl_deep_extend('force', args, opts or {})

  local temp_file_path = nil

  args.callback = function(response)
    log.debug('POST response:', url, response)
    if temp_file_path then
      local ok, err = pcall(os.remove, temp_file_path)
      if not ok then
        log.debug('Failed to remove temp file:', temp_file_path, err)
      end
    end
    if response and not vim.startswith(tostring(response.status), '20') then
      callback(response, response.body)
      return
    end

    if not args.json_response then
      callback(response)
      return
    end

    local body, err = M.json_decode(tostring(response.body))
    if err then
      callback(response, err)
    else
      response.body = body
      callback(response)
    end
  end

  if args.json_response then
    args.headers = vim.tbl_deep_extend('force', args.headers or {}, {
      Accept = 'application/json',
    })
  end

  if args.json_request then
    args.headers = vim.tbl_deep_extend('force', args.headers or {}, {
      ['Content-Type'] = 'application/json',
    })

    temp_file_path = M.temp_file(vim.json.encode(args.body))
    args.body = temp_file_path
  end

  curl.post(url, args)
end, 3)

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
    table.insert(cmd, path)

    vim.system(cmd, { text = true }, function(result)
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

    table.insert(cmd, path)
  elseif vim.fn.executable('grep') == 1 then
    table.insert(cmd, 'grep')
    table.insert(cmd, '-rli')

    if opts.pattern then
      table.insert(cmd, '-e')
      table.insert(cmd, "'" .. opts.pattern .. "'")
    end

    table.insert(cmd, path)
  end

  if M.empty(cmd) then
    error('No executable found for grep')
    return
  end

  vim.system(cmd, { text = true }, function(result)
    local files = {}
    if result and result.code == 0 and result.stdout ~= '' then
      files = filter_files(vim.split(result.stdout, '\n'), opts.max_count)
    end

    callback(files)
  end)
end, 3)

--- Get last modified time of a file
---@param path string The file path
---@return number?
---@async
function M.file_mtime(path)
  local err, stat = async.uv.fs_stat(path)
  if err or not stat then
    return nil
  end
  return stat.mtime.sec
end

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

--- Call a system command
---@param cmd table The command
---@async
M.system = async.wrap(function(cmd, callback)
  vim.system(cmd, { text = true }, callback)
end, 2)

--- Schedule a function only when needed (not on main thread)
---@param callback function The callback
---@async
M.schedule_main = async.wrap(function(callback)
  if vim.in_fast_event() then
    -- In a fast event, need to schedule
    vim.schedule(function()
      callback()
    end)
  else
    -- Already on main thread, call directly
    callback()
  end
end, 1)

--- Wait for a user input
M.input = async.wrap(function(opts, callback)
  local fn = function()
    vim.ui.input(opts, function(input)
      if input == nil or input == '' then
        callback(nil)
        return
      end

      callback(input)
    end)
  end

  if vim.in_fast_event() then
    vim.schedule(fn)
  else
    fn()
  end
end, 2)

--- Select an item from a list
M.select = async.wrap(function(choices, opts, callback)
  local fn = function()
    vim.ui.select(choices, opts, function(item)
      if item == nil or item == '' then
        callback(nil)
        return
      end

      callback(item)
    end)
  end

  if vim.in_fast_event() then
    vim.schedule(fn)
  else
    fn()
  end
end, 3)

--- Get the info for a key.
---@param name string
---@param key table
---@param surround string|nil
---@return string
function M.key_to_info(name, key, surround)
  if not key then
    return ''
  end

  if not surround then
    surround = ''
  end

  local out = ''
  if key.normal and key.normal ~= '' then
    out = out .. surround .. key.normal .. surround
  end
  if key.insert and key.insert ~= '' and key.insert ~= key.normal then
    if out ~= '' then
      out = out .. ' or '
    end
    out = out .. surround .. key.insert .. surround .. ' in insert mode'
  end

  if out == '' then
    return out
  end

  return out .. ' to ' .. name:gsub('_', ' ')
end

--- Check if a value is empty
---@param v any The value
---@return boolean
function M.empty(v)
  if not v then
    return true
  end

  if type(v) == 'table' then
    return vim.tbl_isempty(v)
  end

  if type(v) == 'string' then
    return vim.trim(v) == ''
  end

  return false
end

--- Split text into lines
---@param text string The text to split
---@return string[] A table of lines
function M.split_lines(text)
  if not text or text == '' then
    return {}
  end

  return vim.split(text, '\r?\n', { trimempty = false })
end

return M
