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
        len_old = tonumber(len_old) or 1,
        start_new = tonumber(start_new),
        len_new = tonumber(len_new) or 1,
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

--- Apply a single hunk to content, with fallback/context logic
---@param hunk table
---@param content string
---@return string patched_content, boolean applied_cleanly
local function apply_hunk(hunk, content)
  local dmp = require('CopilotChat.vendor.diff_match_patch')
  local patch = dmp.patch_make(table.concat(hunk.old_snippet, '\n'), table.concat(hunk.new_snippet, '\n'))

  -- First try: direct application
  local patched, results = dmp.patch_apply(patch, content)
  if not vim.tbl_contains(results, false) then
    return patched, true
  end

  -- Fallback: direct replacement
  local lines = vim.split(content, '\n')
  local insert_idx = hunk.start_old or 1
  if not hunk.start_old then
    -- No starting point, try to find best match
    local match_idx, best_score = nil, -1
    local context_lines = vim.tbl_filter(function(line)
      return line and line ~= ''
    end, hunk.old_snippet)
    local context_len = #context_lines
    if context_len > 0 then
      for i = 1, #lines - context_len + 1 do
        local score = 0
        for j = 1, context_len do
          if vim.trim(lines[i + j - 1] or '') == vim.trim(context_lines[j] or '') then
            score = score + 1
          end
        end
        if score > best_score then
          best_score = score
          match_idx = i
        end
      end
    end
    if best_score > 0 and match_idx then
      insert_idx = match_idx
    end
  end

  local start_idx = insert_idx
  local end_idx = insert_idx + #hunk.old_snippet
  local new_lines = vim.list_slice(lines, 1, start_idx - 1)
  vim.list_extend(new_lines, hunk.new_snippet)
  vim.list_extend(new_lines, lines, end_idx + 1, #lines)
  return table.concat(new_lines, '\n'), false
end

--- Apply unified diff to a table of lines and return new lines
---@param diff_text string
---@param original_content string
---@return table<string>, boolean, integer, integer
function M.apply_unified_diff(diff_text, original_content)
  local hunks = parse_hunks(diff_text)
  local new_content = original_content
  local applied = false
  for _, hunk in ipairs(hunks) do
    local patched, ok = apply_hunk(hunk, new_content)
    new_content = patched
    applied = applied or ok
  end
  local original_lines = vim.split(original_content, '\n', { trimempty = true })
  local new_lines = vim.split(new_content, '\n', { trimempty = true })
  local first, last
  local max_len = math.max(#original_lines, #new_lines)
  for i = 1, max_len do
    if original_lines[i] ~= new_lines[i] then
      if not first then
        first = i
      end
      last = i
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

  local patched_lines = vim.split(block.content, '\n')
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
