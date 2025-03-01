local async = require('plenary.async')
local curl = require('plenary.curl')
local scandir = require('plenary.scandir')

local DEFAULT_REQUEST_ARGS = {
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

local M = {}
M.timers = {}
M.curl_args = {}

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
  end
  vim.cmd('stopinsert')
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
  local ft = vim.filetype.match({ filename = filename })

  -- weird TypeScript bug for vim.filetype.match
  -- see: https://github.com/neovim/neovim/issues/27265
  if not ft then
    local base_name = vim.fs.basename(filename)
    local split_name = vim.split(base_name, '%.')
    if #split_name > 1 then
      local ext = split_name[#split_name]
      if ext == 'ts' then
        ft = 'typescript'
      end
    end
  end

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

--- Generate machine id
---@return string
function M.machine_id()
  local length = 65
  local hex_chars = '0123456789abcdef'
  local hex = ''
  for _ = 1, length do
    local index = math.random(1, #hex_chars)
    hex = hex .. hex_chars:sub(index, index)
  end
  return hex
end

--- Generate a quick hash
---@param str string The string to hash
---@return string
function M.quick_hash(str)
  return #str .. str:sub(1, 32) .. str:sub(-32)
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

--- Get current working directory for target window
---@param winnr number? The buffer number
---@return string
function M.win_cwd(winnr)
  if not winnr then
    return '.'
  end

  local dir = vim.w[winnr].cchat_cwd
  if not dir or dir == '' then
    return '.'
  end

  return dir
end

--- Store curl global arguments
---@param args table The arguments
---@return table
M.curl_store_args = function(args)
  M.curl_args = vim.tbl_deep_extend('force', M.curl_args, args)
  return M.curl_args
end

--- Decode json
---@param body string The json string
---@return table, string?
M.json_decode = function(body)
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

--- Send curl get request
---@param url string The url
---@param opts table? The options
M.curl_get = async.wrap(function(url, opts, callback)
  local args = {
    on_error = function(err)
      callback(nil, err and err.stderr or err)
    end,
  }

  args = vim.tbl_deep_extend('force', DEFAULT_REQUEST_ARGS, args)
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
M.curl_post = async.wrap(function(url, opts, callback)
  local args = {
    callback = callback,
    on_error = function(err)
      callback(nil, err and err.stderr or err)
    end,
  }

  args = vim.tbl_deep_extend('force', DEFAULT_REQUEST_ARGS, args)
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

--- Scan a directory
---@param path string The directory path
---@param opts table The options
M.scan_dir = async.wrap(function(path, opts, callback)
  scandir.scan_dir_async(
    path,
    vim.tbl_deep_extend('force', opts, {
      on_exit = function(files)
        if opts.max_files then
          files = vim.list_slice(files, 1, opts.max_files)
        end
        callback(files)
      end,
    })
  )
end, 3)

--- Get last modified time of a file
---@param path string The file path
---@return number?
M.file_mtime = function(path)
  local err, stat = async.uv.fs_stat(path)
  if err or not stat then
    return nil
  end
  return stat.mtime.sec
end

--- Read a file
---@param path string The file path
M.read_file = function(path)
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
M.system = async.wrap(function(cmd, callback)
  vim.system(cmd, { text = true }, callback)
end, 2)

--- Schedule a function only when needed (not on main thread)
---@param callback function The callback
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

--- Get the info for a key.
---@param name string
---@param surround string|nil
---@return string
function M.key_to_info(name, key, surround)
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

  out = out .. ' to ' .. name:gsub('_', ' ')

  if key.detail and key.detail ~= '' then
    out = out .. '. ' .. key.detail
  end

  return out
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
---@param glob string The glob pattern
---@return string?
function M.glob_to_regex(glob)
  if not glob or glob == '' then
    return nil
  end

  -- Escape regex special chars except * and ?
  local pattern = glob:gsub('[%^%$%(%)%%%.%[%]%+%-]', '%%%1')

  -- Convert glob to regex pattern
  pattern = pattern
    :gsub('%*%*/%*', '.*') -- **/* -> .*
    :gsub('%*%*', '.*') -- ** -> .*
    :gsub('%*', '[^/]*') -- * -> [^/]*
    :gsub('%?', '.') -- ? -> .

  return pattern .. '$'
end

return M
