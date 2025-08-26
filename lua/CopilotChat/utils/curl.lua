local async = require('plenary.async')
local curl = require('plenary.curl')
local log = require('plenary.log')
local utils = require('CopilotChat.utils')

local M = {}

M.args = {
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

--- Store curl global arguments
---@param args table The arguments
---@return table
function M.store_args(args)
  M.args = vim.tbl_deep_extend('force', M.args, args)
  return M.args
end

--- Send curl get request
---@param url string The url
---@param opts table? The options
---@async
M.get = async.wrap(function(url, opts, callback)
  log.debug('GET request:', url, opts)
  local args = {
    on_error = function(err)
      log.debug('GET error:', err)
      callback(nil, err and err.stderr or err)
    end,
  }

  args = vim.tbl_deep_extend('force', M.args, args)
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

    local body, err = utils.json_decode(tostring(response.body))
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
M.post = async.wrap(function(url, opts, callback)
  log.debug('POST request:', url, opts)
  local args = {
    on_error = function(err)
      log.debug('POST error:', err)
      callback(nil, err and err.stderr or err)
    end,
  }

  args = vim.tbl_deep_extend('force', M.args, args)
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

    local body, err = utils.json_decode(tostring(response.body))
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

    temp_file_path = os.tmpname()
    local f = io.open(temp_file_path, 'w+')
    if f == nil then
      error('Could not open file: ' .. temp_file_path)
    end
    f:write(vim.json.encode(args.body))
    f:close()
    args.body = temp_file_path
  end

  curl.post(url, args)
end, 3)

return M
