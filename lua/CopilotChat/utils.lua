local async = require('plenary.async')
local log = require('plenary.log')

local M = {}
M.timers = {}

--- Use CopilotChat.utils.curl.get instead
---@deprecated
function M.curl_get(url, opts)
  log.warn('M.curl_get is deprecated, use CopilotChat.utils.curl.get instead')
  return require('CopilotChat.utils.curl').get(url, opts)
end

--- Use CopilotChat.utils.curl.post instead
---@deprecated
function M.curl_post(url, opts)
  log.warn('M.curl_post is deprecated, use CopilotChat.utils.curl.post instead')
  return require('CopilotChat.utils.curl').post(url, opts)
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

--- Call a system command
---@param cmd table The command
---@async
M.system = async.wrap(function(cmd, cwd, callback)
  vim.system(cmd, { cwd = cwd, text = true }, callback)
end, 3)

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
