local async = require('plenary.async')
local curl = require('plenary.curl')
local scandir = require('plenary.scandir')
local filetype = require('plenary.filetype')

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

---@class OrderedMap
---@field set fun(self:OrderedMap, key:any, value:any)
---@field get fun(self:OrderedMap, key:any):any
---@field keys fun(self:OrderedMap):table
---@field values fun(self:OrderedMap):table

--- Create an ordered map
---@return OrderedMap
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
---@return string?
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

--- Blend a color with the neovim background
---@param color_name string The color name
---@param blend number The blend percentage
---@return string?
function M.blend_color(color_name, blend)
  local color_int = vim.api.nvim_get_hl(0, { name = color_name }).fg
  local bg_int = vim.api.nvim_get_hl(0, { name = 'Normal' }).bg

  if not color_int or not bg_int then
    return
  end

  local color = { (color_int / 65536) % 256, (color_int / 256) % 256, color_int % 256 }
  local bg = { (bg_int / 65536) % 256, (bg_int / 256) % 256, bg_int % 256 }
  local r = math.floor((color[1] * blend + bg[1] * (100 - blend)) / 100)
  local g = math.floor((color[2] * blend + bg[2] * (100 - blend)) / 100)
  local b = math.floor((color[3] * blend + bg[3] * (100 - blend)) / 100)
  return string.format('#%02x%02x%02x', r, g, b)
end

--- Return to normal mode
function M.return_to_normal_mode()
  local mode = vim.fn.mode():lower()
  if mode:find('v') then
    vim.cmd([[execute "normal! \<Esc>"]])
  elseif mode ~= 'n' then
    vim.cmd('stopinsert')
  end
end

--- Mark a function as deprecated
function M.deprecate(old, new)
  vim.deprecate(old, new, '3.0.X', 'CopilotChat.nvim', false)
end

--- Debounce a function
function M.debounce(id, fn, delay)
  if M.timers[id] then
    M.timers[id]:stop()
    M.timers[id] = nil
  end
  M.timers[id] = vim.defer_fn(fn, delay)
end

--- Create key-value list from table
---@param tbl table The table
---@return table
function M.kv_list(tbl)
  local result = {}
  for k, v in pairs(tbl) do
    table.insert(result, {
      key = k,
      value = v,
    })
  end

  return result
end

--- Check if a buffer is valid
---@param bufnr number? The buffer number
---@return boolean
function M.buf_valid(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) or false
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
  local ft = filetype.detect(filename, {
    fs_access = false,
  })

  if ft == '' then
    return nil
  end
  return ft
end

--- Get the file name
---@param filepath string The file path
---@return string
function M.filename(filepath)
  return vim.fs.basename(filepath)
end

--- Get the file path
---@param filename string The file name
---@return string
function M.filepath(filename)
  return vim.fn.fnamemodify(filename, ':p:.')
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

--- Generate a quick hash
---@param str string The string to hash
---@return string
function M.quick_hash(str)
  return #str .. str:sub(1, 64) .. str:sub(-64)
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
  local args = {
    on_error = function(err)
      callback(nil, err and err.stderr or err)
    end,
  }

  args = vim.tbl_deep_extend('force', M.curl_args, args)
  args = vim.tbl_deep_extend('force', args, opts or {})

  args.callback = function(response)
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
  local args = {
    callback = callback,
    on_error = function(err)
      callback(nil, err and err.stderr or err)
    end,
  }

  args = vim.tbl_deep_extend('force', M.curl_args, args)
  args = vim.tbl_deep_extend('force', args, opts or {})

  if args.json_response then
    args.headers = vim.tbl_deep_extend('force', args.headers or {}, {
      Accept = 'application/json',
    })
  end

  args.callback = function(response)
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

  if args.json_request then
    args.headers = vim.tbl_deep_extend('force', args.headers or {}, {
      ['Content-Type'] = 'application/json',
    })

    args.body = M.temp_file(vim.json.encode(args.body))
  end

  curl.post(url, args)
end, 3)

---@class CopilotChat.utils.scan_dir_opts
---@field max_count number? The maximum number of files to scan
---@field max_depth number? The maximum depth to scan
---@field glob? string The glob pattern to match files
---@field hidden? boolean Whether to include hidden files
---@field no_ignore? boolean Whether to respect or ignore .gitignore

--- Scan a directory
---@param path string The directory path
---@param opts CopilotChat.utils.scan_dir_opts? The options
---@async
M.scan_dir = async.wrap(function(path, opts, callback)
  opts = vim.tbl_deep_extend('force', M.scan_args, opts or {})

  local function filter_files(files)
    files = vim.tbl_filter(function(file)
      return file ~= '' and M.filetype(file) ~= nil
    end, files)
    if opts.max_count and opts.max_count > 0 then
      files = vim.list_slice(files, 1, opts.max_count)
    end

    return files
  end

  -- Use ripgrep if available
  if vim.fn.executable('rg') == 1 then
    local cmd = { 'rg' }

    if opts.glob then
      table.insert(cmd, '-g')
      table.insert(cmd, opts.glob)
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
        files = filter_files(vim.split(result.stdout, '\n'))
      end

      callback(files)
    end)

    return
  end

  -- Fall back to scandir if rg is not available or fails
  scandir.scan_dir_async(
    path,
    vim.tbl_deep_extend('force', opts, {
      depth = opts.max_depth,
      add_dirs = false,
      search_pattern = M.glob_to_pattern(opts.glob),
      respect_gitignore = not opts.no_ignore,
      on_exit = function(files)
        callback(filter_files(files))
      end,
    })
  )
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

--- Run parse on a treesitter parser asynchronously if possible
---@param parser vim.treesitter.LanguageTree The parser
M.ts_parse = async.wrap(function(parser, callback)
  ---@diagnostic disable-next-line: invisible
  if not parser._async_parse then
    local fn = function()
      local trees = parser:parse(false)
      if not trees or #trees == 0 then
        callback(nil)
        return
      end
      callback(trees[1]:root())
    end

    if vim.in_fast_event() then
      vim.schedule(fn)
    else
      fn()
    end

    return
  end

  local fn = function()
    parser:parse(false, function(err, trees)
      if err or not trees or #trees == 0 then
        callback(nil)
        return
      end
      callback(trees[1]:root())
    end)
  end

  if vim.in_fast_event() then
    vim.schedule(fn)
  else
    fn()
  end
end, 2)

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

--- Convert glob pattern to regex pattern
--- https://github.com/davidm/lua-glob-pattern/blob/master/lua/globtopattern.lua
---@param g string The glob pattern
---@return string
function M.glob_to_pattern(g)
  local p = '^' -- pattern being built
  local i = 0 -- index in g
  local c -- char at index i in g.

  -- unescape glob char
  local function unescape()
    if c == '\\' then
      i = i + 1
      c = g:sub(i, i)
      if c == '' then
        p = '[^]'
        return false
      end
    end
    return true
  end

  -- escape pattern char
  local function escape(c)
    return c:match('^%w$') and c or '%' .. c
  end

  -- Convert tokens at end of charset.
  local function charset_end()
    while 1 do
      if c == '' then
        p = '[^]'
        return false
      elseif c == ']' then
        p = p .. ']'
        break
      else
        if not unescape() then
          break
        end
        local c1 = c
        i = i + 1
        c = g:sub(i, i)
        if c == '' then
          p = '[^]'
          return false
        elseif c == '-' then
          i = i + 1
          c = g:sub(i, i)
          if c == '' then
            p = '[^]'
            return false
          elseif c == ']' then
            p = p .. escape(c1) .. '%-]'
            break
          else
            if not unescape() then
              break
            end
            p = p .. escape(c1) .. '-' .. escape(c)
          end
        elseif c == ']' then
          p = p .. escape(c1) .. ']'
          break
        else
          p = p .. escape(c1)
          i = i - 1 -- put back
        end
      end
      i = i + 1
      c = g:sub(i, i)
    end
    return true
  end

  -- Convert tokens in charset.
  local function charset()
    i = i + 1
    c = g:sub(i, i)
    if c == '' or c == ']' then
      p = '[^]'
      return false
    elseif c == '^' or c == '!' then
      i = i + 1
      c = g:sub(i, i)
      if c == ']' then
        -- ignored
      else
        p = p .. '[^'
        if not charset_end() then
          return false
        end
      end
    else
      p = p .. '['
      if not charset_end() then
        return false
      end
    end
    return true
  end

  -- Convert tokens.
  while 1 do
    i = i + 1
    c = g:sub(i, i)
    if c == '' then
      p = p .. '$'
      break
    elseif c == '?' then
      p = p .. '.'
    elseif c == '*' then
      p = p .. '.*'
    elseif c == '[' then
      if not charset() then
        break
      end
    elseif c == '\\' then
      i = i + 1
      c = g:sub(i, i)
      if c == '' then
        p = p .. '\\$'
        break
      end
      p = p .. escape(c)
    else
      p = p .. escape(c)
    end
  end
  return p
end

---@class CopilotChat.Diagnostic
---@field content string
---@field start_line number
---@field end_line number
---@field severity string

--- Get diagnostics in a given range
--- @param bufnr number
--- @param start_line number?
--- @param end_line number?
--- @return table<CopilotChat.Diagnostic>|nil
function M.diagnostics(bufnr, start_line, end_line)
  local diagnostics = vim.diagnostic.get(bufnr)
  local range_diagnostics = {}
  local severity = {
    [1] = 'ERROR',
    [2] = 'WARNING',
    [3] = 'INFORMATION',
    [4] = 'HINT',
  }

  for _, diagnostic in ipairs(diagnostics) do
    local lnum = diagnostic.lnum + 1
    if (not start_line or lnum >= start_line) and (not end_line or lnum <= end_line) then
      table.insert(range_diagnostics, {
        severity = severity[diagnostic.severity],
        content = diagnostic.message,
        start_line = lnum,
        end_line = diagnostic.end_lnum and diagnostic.end_lnum + 1 or lnum,
      })
    end
  end

  return #range_diagnostics > 0 and range_diagnostics or nil
end

return M
