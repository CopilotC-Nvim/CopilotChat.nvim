local M = {}

--- Parse unified diff, return file_path and hunks
---@param diff_text string The unified diff text
---@return string?, table[]
function M.parse_unified_diff(diff_text)
  local hunks = {}
  local current_hunk = nil
  local file_path = nil

  for _, line in ipairs(vim.split(diff_text, '\n')) do
    if line:match('^+++ ') then
      file_path = vim.trim(line:sub(5))
    elseif line:match('^@@') then
      if current_hunk then
        table.insert(hunks, current_hunk)
      end
      current_hunk = { minus = {}, plus = {}, context = {} }
    elseif current_hunk then
      if line:match('^%-') then
        table.insert(current_hunk.minus, line:sub(2))
      elseif line:match('^%+') then
        table.insert(current_hunk.plus, line:sub(2))
      elseif line ~= '' then
        table.insert(current_hunk.context, line)
      end
    end
  end
  if current_hunk then
    table.insert(hunks, current_hunk)
  end
  return file_path, hunks
end

--- Apply unified diff to a table of lines and return the new lines
---@param diff_text string
---@param original_lines table
---@return table, boolean
function M.apply_unified_diff(diff_text, original_lines)
  local _, hunks = M.parse_unified_diff(diff_text)
  local lines = vim.deepcopy(original_lines)
  local applied_any = false

  for _, hunk in ipairs(hunks) do
    -- Build the full hunk pattern: context + minus lines
    local hunk_pattern = {}
    for _, ctx in ipairs(hunk.context) do
      table.insert(hunk_pattern, ctx)
    end
    for _, minus in ipairs(hunk.minus) do
      table.insert(hunk_pattern, minus)
    end

    -- Find all possible matches for the hunk pattern
    local match_indices = {}
    for i = 1, #lines - #hunk_pattern + 1 do
      local match = true
      for j = 1, #hunk_pattern do
        if vim.trim(lines[i + j - 1]) ~= vim.trim(hunk_pattern[j]) then
          match = false
          break
        end
      end
      if match then
        table.insert(match_indices, i)
      end
    end

    if #match_indices == 1 then
      local idx = match_indices[1]
      -- Replace the matched region with context + plus lines
      local new_region = {}
      for _, ctx in ipairs(hunk.context) do
        table.insert(new_region, ctx)
      end
      for _, plus in ipairs(hunk.plus) do
        table.insert(new_region, plus)
      end

      for j = 1, #hunk_pattern do
        table.remove(lines, idx)
      end
      for j = #new_region, 1, -1 do
        table.insert(lines, idx, new_region[j])
      end
      applied_any = true
    end

    -- If no match or multiple matches, just skip to next hunk
  end

  return lines, applied_any
end

--- Get changed regions for jump/highlight
---@param diff_text string The unified diff text
---@return number?, number?
function M.get_unified_diff_region(diff_text, original_lines)
  local _, hunks = M.parse_unified_diff(diff_text)
  local first, last

  for _, hunk in ipairs(hunks) do
    for i = 1, #original_lines - #hunk.minus + 1 do
      local match = true
      for j = 1, #hunk.minus do
        if vim.trim(original_lines[i + j - 1]) ~= vim.trim(hunk.minus[j]) then
          match = false
          break
        end
      end
      if match then
        local region_start = i
        local region_end = i + #hunk.plus - 1
        if not first or region_start < first then
          first = region_start
        end
        if not last or region_end > last then
          last = region_end
        end
        break
      end
    end
  end

  if first and last then
    return first, last
  end

  return nil, nil
end

return M
