local M = {}

local WORD = '([^%s:]+)'
local WORD_NO_INPUT = '([^%s]+)'
local WORD_WITH_INPUT_QUOTED = WORD .. ':`([^`]+)`'
local WORD_WITH_INPUT_UNQUOTED = WORD .. ':?([^%s`]*)'

---@class CopilotChat.prompts.Reference
---@field type 'model'|'function'|'function_call'|'resource'|'sticky'|'prompt'
---@field value string
---@field input? string
---@field start_pos integer
---@field end_pos integer

--- Parse all references from a prompt string, tracking positions.
---@param prompt string
---@return CopilotChat.prompts.Reference[] refs
function M.parse(prompt)
  local refs = {}

  -- $model
  for s, value, e in prompt:gmatch('()%$' .. WORD .. '()') do
    table.insert(refs, {
      type = 'model',
      value = value,
      start_pos = s,
      end_pos = e - 1,
    })
  end

  -- @function
  for s, value, e in prompt:gmatch('()@' .. WORD .. '()') do
    table.insert(refs, {
      type = 'function_reference',
      value = value,
      start_pos = s,
      end_pos = e - 1,
    })
  end

  -- #function_call
  local function function_call_matches(str)
    local matches = {}
    -- #function_call:`input` (quoted)
    for s, value, input, e in str:gmatch('()#' .. WORD_WITH_INPUT_QUOTED .. '()') do
      table.insert(matches, { s = s, e = e - 1, value = value, input = input })
    end
    -- #function_call:input (unquoted)
    for s, value, input, e in str:gmatch('()#' .. WORD_WITH_INPUT_UNQUOTED .. '()') do
      table.insert(matches, { s = s, e = e - 1, value = value, input = input })
    end
    -- #function_call (no input)
    for s, value, e in str:gmatch('()#' .. WORD_NO_INPUT .. '()') do
      table.insert(matches, { s = s, e = e - 1, value = value, input = nil })
    end
    return matches
  end
  for _, m in ipairs(function_call_matches(prompt)) do
    table.insert(refs, {
      type = 'function_call',
      value = m.value,
      input = m.input or nil,
      start_pos = m.s,
      end_pos = m.e,
    })
  end

  -- ##resource
  for s, value, e in prompt:gmatch('()##' .. WORD_NO_INPUT .. '()') do
    table.insert(refs, {
      type = 'resource',
      value = value,
      start_pos = s,
      end_pos = e - 1,
    })
  end

  -- > sticky
  local function sticky_matches(str)
    local matches = {}
    -- > sticky (newline)
    for s, value, e in str:gmatch('()\n> ([^\n]+)()') do
      table.insert(matches, { s = s + 1, e = e - 1, value = value })
    end
    -- > sticky (start of string)
    for s, value, e in str:gmatch('()^> ([^\n]+)()') do
      table.insert(matches, { s = s, e = e - 1, value = value })
    end
    return matches
  end
  for _, m in ipairs(sticky_matches(prompt)) do
    table.insert(refs, {
      type = 'sticky',
      value = m.value,
      start_pos = m.s,
      end_pos = m.e,
    })
  end

  -- /prompt
  for s, value, e in prompt:gmatch('()/' .. WORD_NO_INPUT .. '()') do
    table.insert(refs, {
      type = 'prompt',
      value = value,
      start_pos = s,
      end_pos = e - 1,
    })
  end

  local keep = {}
  for i, ref in ipairs(refs) do
    local contained = false
    for j, other in ipairs(refs) do
      if i ~= j then
        -- Strictly contained
        if other.type ~= 'sticky' and ref.start_pos > other.start_pos and ref.end_pos < other.end_pos then
          contained = true
          break
        end
        -- Exact match, only keep the first occurrence
        if ref.start_pos == other.start_pos and ref.end_pos == other.end_pos and j < i then
          contained = true
          break
        end
      end
    end
    if not contained then
      table.insert(keep, ref)
    end
  end

  return keep
end

--- Replace references in the prompt using positions (descending order).
---@param prompt string
---@param refs CopilotChat.prompts.Reference[]
---@param resolver fun(ref: CopilotChat.prompts.Reference): string?
function M.replace(prompt, refs, resolver)
  table.sort(refs, function(a, b)
    return a.start_pos > b.start_pos
  end)
  for _, ref in ipairs(refs) do
    local output = resolver(ref)
    if output then
      prompt = prompt:sub(1, ref.start_pos - 1) .. output .. prompt:sub(ref.end_pos + 1)
    end
  end
  return prompt
end

return M
