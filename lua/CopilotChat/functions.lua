local utils = require('CopilotChat.utils')

local M = {}

local INPUT_SEPARATOR = ';;'
local URI_PARAM_PATTERN = '{([^}:*]+)[^}]*}'

local function sorted_propnames(schema)
  local prop_names = vim.tbl_keys(schema.properties)
  local required_set = {}
  if schema.required then
    for _, name in ipairs(schema.required) do
      required_set[name] = true
    end
  end

  -- Sort properties with priority: required without default > required with default > optional
  table.sort(prop_names, function(a, b)
    local a_required = required_set[a] or false
    local b_required = required_set[b] or false
    local a_has_default = schema.properties[a].default ~= nil
    local b_has_default = schema.properties[b].default ~= nil

    -- First priority: required properties without default
    if a_required and not a_has_default and (not b_required or b_has_default) then
      return true
    end
    if b_required and not b_has_default and (not a_required or a_has_default) then
      return false
    end

    -- Second priority: required properties with default
    if a_required and not b_required then
      return true
    end
    if b_required and not a_required then
      return false
    end

    -- Finally sort alphabetically
    return a < b
  end)

  return prop_names
end

local function filter_schema(tbl, root)
  if type(tbl) ~= 'table' then
    return tbl
  end

  if root and utils.empty(tbl.properties) then
    return nil
  end

  local result = {}
  for k, v in pairs(tbl) do
    if not utils.empty(v) then
      if type(v) ~= 'function' and k ~= 'examples' then
        result[k] = type(v) == 'table' and filter_schema(v) or v
      end
    end
  end
  return result
end

--- Convert a URI template to a URL by replacing parameters with values from input
---@param uri_template string The URI template containing parameters in the form {param}
---@param input table A table containing parameter values, e.g., { path = '/my/file.txt' }
---@return string The resulting URL with parameters replaced
function M.uri_to_url(uri_template, input)
  -- Replace {param} in the template with input[param] or empty string
  return (uri_template:gsub(URI_PARAM_PATTERN, function(param)
    return input[param] or ''
  end))
end

---@param uri string The URI to parse
---@param pattern string The pattern to match against (e.g., 'file://{path}')
---@return table|nil inputs Extracted parameters or nil if no match
function M.match_uri(uri, pattern)
  -- Convert the pattern into a Lua pattern by escaping special characters
  -- and replacing {name} placeholders with capture groups
  local lua_pattern = pattern:gsub('([%(%)%.%%%+%-%*%?%[%]%^%$])', '%%%1')

  -- Extract parameter names from the pattern
  local param_names = {}
  for param in pattern:gmatch(URI_PARAM_PATTERN) do
    table.insert(param_names, param)
    -- Replace {param} with a capture group in our Lua pattern
    -- Use non-greedy capture to handle multiple params properly
    lua_pattern = lua_pattern:gsub('{' .. param .. '[^}]*}', '(.-)')
  end

  -- If no parameters, just do a direct comparison
  if #param_names == 0 then
    return uri == pattern and {} or nil
  end

  -- Match the URI against our constructed pattern
  local matches = { uri:match('^' .. lua_pattern .. '$') }

  -- If match failed, return nil
  if #matches == 0 or matches[1] == nil then
    return nil
  end

  -- Build the result table mapping parameter names to their values
  local result = {}
  for i, param_name in ipairs(param_names) do
    result[param_name] = matches[i]
  end

  return result
end

--- Parse function schema and return a JSON schema object
---@param fn CopilotChat.config.functions.Function
function M.parse_schema(fn)
  local schema = fn.schema

  -- If schema is missing but uri is present, generate a default schema from uri
  if not schema and fn.uri then
    -- Extract parameter names from the uri pattern, e.g. file://{path}
    local param_names = {}
    for param in fn.uri:gmatch(URI_PARAM_PATTERN) do
      table.insert(param_names, param)
    end
    if #param_names > 0 then
      schema = {
        type = 'object',
        properties = {},
        required = {},
      }
      for _, param in ipairs(param_names) do
        schema.properties[param] = { type = 'string' }
        table.insert(schema.required, param)
      end
    end
  end

  return schema
end

--- Prepare functions for tool use
---@param functions table<string, CopilotChat.config.functions.Function>
---@return table<CopilotChat.client.Tool>
function M.parse_tools(functions)
  local tool_names = vim.tbl_keys(functions)
  table.sort(tool_names)
  return vim.tbl_map(function(name)
    local tool = functions[name]

    return {
      name = name,
      description = tool.description,
      schema = filter_schema(M.parse_schema(tool), true),
    }
  end, tool_names)
end

--- Parse context input string into a table based on the schema
---@param input string|table|nil
---@param schema table?
---@return table
function M.parse_input(input, schema)
  if type(input) == 'table' then
    return input
  end

  if not schema or not schema.properties then
    return {}
  end

  local parts = vim.split(input or '', INPUT_SEPARATOR)
  local result = {}
  local prop_names = sorted_propnames(schema)

  -- Map input parts to schema properties in sorted order
  for i, prop_name in ipairs(prop_names) do
    local prop_schema = schema.properties[prop_name]
    local value = not utils.empty(parts[i]) and parts[i] or nil
    if value == nil and prop_schema.default ~= nil then
      value = prop_schema.default
    end

    result[prop_name] = value
  end

  return result
end

--- Get input from the user based on the schema
---@param schema table?
---@param source CopilotChat.source
---@return string?
function M.enter_input(schema, source)
  if not schema or not schema.properties then
    return nil
  end

  local prop_names = sorted_propnames(schema)
  local out = {}

  for _, prop_name in ipairs(prop_names) do
    local cfg = schema.properties[prop_name]
    if not schema.required or vim.tbl_contains(schema.required, prop_name) then
      if cfg.enum then
        local choices = type(cfg.enum) == 'table' and cfg.enum or cfg.enum(source)
        local choice
        if #choices == 0 then
          choice = nil
        elseif #choices == 1 then
          choice = choices[1]
        else
          choice = utils.select(choices, {
            prompt = string.format('Select %s> ', prop_name),
          })
        end

        table.insert(out, choice or '')
      elseif cfg.type == 'boolean' then
        table.insert(out, utils.select({ 'true', 'false' }, {
          prompt = string.format('Select %s> ', prop_name),
        }) or '')
      else
        table.insert(out, utils.input({
          prompt = string.format('Enter %s> ', prop_name),
        }) or '')
      end
    end
  end

  local out = vim.trim(table.concat(out, INPUT_SEPARATOR))
  if out:match('%s+') then
    out = string.format('`%s`', out)
  end
  return out
end

return M
