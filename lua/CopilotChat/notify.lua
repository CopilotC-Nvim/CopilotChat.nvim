local log = require('plenary.log')

local M = {}

M.STATUS = 'status'

M.listeners = {}

--- Publish an event with a message
---@param event_name string
---@param data any
function M.publish(event_name, data)
  if M.listeners[event_name] then
    if data and data ~= '' then
      log.debug(event_name .. ':', data)
    end

    for _, callback in ipairs(M.listeners[event_name]) do
      callback(data)
    end
  end
end

--- Listen for an event
---@param event_name string
---@param callback fun(data:any)
function M.listen(event_name, callback)
  if not M.listeners[event_name] then
    M.listeners[event_name] = {}
  end
  table.insert(M.listeners[event_name], callback)
end

return M
