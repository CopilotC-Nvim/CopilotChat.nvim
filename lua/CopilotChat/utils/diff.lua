local log = require('plenary.log')

local M = {}

--- Parse unified diff hunks from diff text
---@param diff_text string
---@return table hunks
local function parse_hunks(diff_text)
  local hunks = {}
  local current_hunk = nil
  for _, line in ipairs(vim.split(diff_text, '\n')) do
    if line:match('^@@') then
      if current_hunk then
        table.insert(hunks, current_hunk)
      end
      local start_old, len_old, start_new, len_new = line:match('@@%s%-(%d+),?(%d*)%s%+(%d+),?(%d*)%s@@')
      current_hunk = {
        start_old = tonumber(start_old),
        len_old = len_old == '' and 1 or tonumber(len_old),
        start_new = tonumber(start_new),
        len_new = len_new == '' and 1 or tonumber(len_new),
        old_snippet = {},
        new_snippet = {},
      }
    elseif current_hunk then
      local prefix, rest = line:sub(1, 1), tostring(line:sub(2))
      if prefix == '-' then
        table.insert(current_hunk.old_snippet, rest)
      elseif prefix == '+' then
        table.insert(current_hunk.new_snippet, rest)
      elseif prefix == ' ' then
        table.insert(current_hunk.old_snippet, rest)
        table.insert(current_hunk.new_snippet, rest)
      end
    end
  end
  if current_hunk then
    table.insert(hunks, current_hunk)
  end
  return hunks
end

--- Try to match old_snippet in lines starting at approximate start_line
---@param lines table
---@param old_snippet table
---@param approx_start number
---@param search_range number
---@return number? matched_start
local function find_best_match(lines, old_snippet, approx_start, search_range)
  local best_idx, best_score = nil, -1
  local old_len = #old_snippet

  if old_len == 0 then
    return approx_start
  end

  local min_start = math.max(1, approx_start - search_range)
  local max_start = math.min(#lines - old_len + 1, approx_start + search_range)

  for start_idx = min_start, max_start do
    local score = 0
    for i = 1, old_len do
      if vim.trim(lines[start_idx + i - 1] or '') == vim.trim(old_snippet[i] or '') then
        score = score + 1
      end
    end

    if score > best_score then
      best_score = score
      best_idx = start_idx
    end

    if score == old_len then
      return best_idx
    end
  end

  if best_score >= math.ceil(old_len * 0.8) then
    return best_idx
  end

  return nil
end

--- Apply a single hunk to content
---@param hunk table
---@param content string
---@return string patched_content, boolean applied_cleanly
local function apply_hunk(hunk, content)
  local lines = vim.split(content, '\n')
  local start_idx = hunk.start_old

  -- Handle insertions (len_old == 0)
  if hunk.len_old == 0 then
    -- For insertions, start_old indicates where to insert
    -- start_old = 0 means insert at beginning
    -- start_old = n means insert after line n
    if start_idx == 0 then
      start_idx = 1
    else
      start_idx = start_idx + 1
    end
    local new_lines = vim.list_slice(lines, 1, start_idx - 1)
    vim.list_extend(new_lines, hunk.new_snippet)
    vim.list_extend(new_lines, lines, start_idx, #lines)
    -- Insertions are always applied cleanly if we reach this point
    return table.concat(new_lines, '\n'), true
  end

  -- Handle replacements and deletions (len_old > 0)
  -- If we have a start line hint, try to find best match within +/- 2 lines
  if start_idx and start_idx > 0 and start_idx <= #lines then
    local match_idx = find_best_match(lines, hunk.old_snippet, start_idx, 2)
    if match_idx then
      start_idx = match_idx
    end
  else
    -- No valid start line, search for best match in whole content
    local match_idx = find_best_match(lines, hunk.old_snippet, 1, #lines)
    if match_idx then
      start_idx = match_idx
    else
      start_idx = 1
    end
  end

  -- Replace old lines with new lines
  local end_idx = start_idx + #hunk.old_snippet - 1
  local new_lines = vim.list_slice(lines, 1, start_idx - 1)
  vim.list_extend(new_lines, hunk.new_snippet)
  vim.list_extend(new_lines, lines, end_idx + 1, #lines)

  -- Check if we matched exactly at the hinted position
  local applied_cleanly = find_best_match(lines, hunk.old_snippet, hunk.start_old or start_idx, 0) == start_idx
  return table.concat(new_lines, '\n'), applied_cleanly
end

--- Apply unified diff to a table of lines and return new lines
---@param diff_text string
---@param original_content string
---@return table<string>, boolean, integer, integer
function M.apply_unified_diff(diff_text, original_content)
  local hunks = parse_hunks(diff_text)
  local new_content = original_content
  local applied = false
  local offset = 0 -- Track cumulative line offset from previous hunks

  for _, hunk in ipairs(hunks) do
    -- Adjust hunk start position based on accumulated offset
    local adjusted_hunk = vim.deepcopy(hunk)
    if adjusted_hunk.start_old then
      adjusted_hunk.start_old = hunk.start_old + offset
    end

    local patched, ok = apply_hunk(adjusted_hunk, new_content)
    new_content = patched
    applied = applied or ok

    -- Update offset: (new lines added) - (old lines removed)
    offset = offset + (#hunk.new_snippet - #hunk.old_snippet)
  end

  local new_lines = vim.split(new_content, '\n', { trimempty = true })
  local hunks = vim.diff(
    original_content,
    new_content,
    { algorithm = 'myers', ctxlen = 10, interhunkctxlen = 10, ignore_whitespace_change = true, result_type = 'indices' }
  )
  if not hunks or #hunks == 0 then
    return new_lines, applied, nil, nil
  end
  local first, last
  for _, hunk in ipairs(hunks) do
    local hunk_start = hunk[1]
    local hunk_end = hunk[1] + hunk[2] - 1
    if not first or hunk_start < first then
      first = hunk_start
    end
    if not last or hunk_end > last then
      last = hunk_end
    end
  end
  return new_lines, applied, first, last
end

--- Get diff from block content and buffer lines
---@param block CopilotChat.ui.chat.Block Block containing diff info
---@param lines table table of lines
---@return string diff, string content
function M.get_diff(block, lines)
  local content = table.concat(lines, '\n')
  if block.header.filetype == 'diff' then
    return block.content, content
  end

  local patched_lines = vim.split(block.content, '\n', { trimempty = true })
  local start_idx = block.header.start_line
  local end_idx = block.header.end_line
  local original_lines = lines
  if start_idx and end_idx then
    local new_lines = vim.list_slice(original_lines, 1, start_idx - 1)
    vim.list_extend(new_lines, patched_lines)
    vim.list_extend(new_lines, original_lines, end_idx + 1, #original_lines)
    patched_lines = new_lines
  end

  return tostring(
    vim.diff(
      table.concat(original_lines, '\n'),
      table.concat(patched_lines, '\n'),
      { algorithm = 'myers', ctxlen = 10, interhunkctxlen = 10, ignore_whitespace_change = true }
    )
  ),
    content
end

--- Apply a diff (unified or indices) to buffer lines
---@param block CopilotChat.ui.chat.Block Block containing diff info
---@param lines table table of lines
---@return table new_lines
function M.apply_diff(block, lines)
  local diff, content = M.get_diff(block, lines)
  local new_lines, applied, _, _ = M.apply_unified_diff(diff, content)
  if not applied then
    log.debug('Diff for ' .. block.header.filename .. ' failed to apply cleanly for:\n' .. diff)
  end

  return new_lines
end

--- Get changed region for diff (unified or indices)
---@param block CopilotChat.ui.chat.Block Block containing diff info
---@param lines table table of lines
---@return number? first, number? last
function M.get_diff_region(block, lines)
  local diff, content = M.get_diff(block, lines)
  local _, _, first, last = M.apply_unified_diff(diff, content)
  return first, last
end

return M
