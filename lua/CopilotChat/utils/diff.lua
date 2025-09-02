local M = {}

--- Parse unified diff, return file_path and hunks
---@param diff_text string The unified diff text
---@return string?, table[]
function M.parse_unified_diff(diff_text)
  local hunks = {}
  local current_hunk = nil
  local file_path = nil

  for _, line in ipairs(vim.split(diff_text, '\n')) do
    local diff_filename = line:match('^%+%+%+%s+(.*)')
    if diff_filename then
      file_path = diff_filename
    elseif line:match('^@@') then
      if current_hunk then
        table.insert(hunks, current_hunk)
      end
      current_hunk = { minus = {}, plus = {}, context = {} }
    elseif current_hunk then
      local prefix = line:sub(1, 1)
      local rest = line:sub(2)
      if prefix == '-' then
        table.insert(current_hunk.minus, rest)
      elseif prefix == '+' then
        table.insert(current_hunk.plus, rest)
      elseif #current_hunk.plus == 0 and #current_hunk.minus == 0 then
        if prefix == ' ' then
          table.insert(current_hunk.context, rest)
        elseif line ~= '' then
          table.insert(current_hunk.context, line)
        end
      end
    end
  end
  if current_hunk then
    table.insert(hunks, current_hunk)
  end
  return file_path, hunks
end

--- Apply unified diff to a table of lines and return new lines
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

--- Apply diff indices from vim.diff to original and new lines
---@param hunks table Indices from vim.diff (result_type = 'indices')
---@param original_lines table Lines before patch
---@param new_lines table Lines after patch
---@return table Patched lines
function M.apply_diff_indices(hunks, original_lines, new_lines)
  local result = {}
  local orig_idx = 1

  for _, hunk in ipairs(hunks) do
    local start_a, count_a, start_b, count_b = unpack(hunk)
    -- Add unchanged lines before hunk
    for i = orig_idx, start_a - 1 do
      table.insert(result, original_lines[i])
    end
    -- Add changed lines from new_lines
    for i = start_b, start_b + count_b - 1 do
      table.insert(result, new_lines[i])
    end
    orig_idx = start_a + count_a
  end
  -- Add remaining lines
  for i = orig_idx, #original_lines do
    table.insert(result, original_lines[i])
  end
  return result
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

--- Apply a diff (unified or indices) to buffer lines
---@param block CopilotChat.ui.chat.Block Block containing diff info
---@param bufnr integer Buffer number
---@return table new_lines, boolean applied
function M.apply_diff(block, bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if block.header.filetype == 'diff' then
    return M.apply_unified_diff(block.content, lines)
  elseif block.header.start_line and block.header.end_line then
    local start_idx = block.header.start_line
    local end_idx = block.header.end_line
    local original_lines = vim.list_slice(lines, start_idx, end_idx)
    local patched_lines = vim.split(block.content, '\n')
    local hunks = vim.diff(
      table.concat(original_lines, '\n'),
      table.concat(patched_lines, '\n'),
      { result_type = 'indices', algorithm = 'myers', ctxlen = 3 }
    )
    local region_new_lines = M.apply_diff_indices(hunks, original_lines, patched_lines)
    local new_lines = {}
    -- Add lines before region
    for i = 1, start_idx - 1 do
      table.insert(new_lines, lines[i])
    end
    -- Add patched region
    for _, line in ipairs(region_new_lines) do
      table.insert(new_lines, line)
    end
    -- Add lines after region
    for i = end_idx + 1, #lines do
      table.insert(new_lines, lines[i])
    end
    return new_lines, true
  end
  return lines, false
end

--- Get changed region for diff (unified or indices)
---@param block CopilotChat.ui.chat.Block Block containing diff info
---@param bufnr integer Buffer number
---@return number? first, number? last
function M.get_diff_region(block, bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if block.header.filetype == 'diff' then
    return M.get_unified_diff_region(block.content, lines)
  elseif block.header.start_line and block.header.end_line then
    local original_lines = vim.api.nvim_buf_get_lines(bufnr, block.header.start_line - 1, block.header.end_line, false)
    local patched_lines = vim.split(block.content, '\n')
    local hunks = vim.diff(
      table.concat(original_lines, '\n'),
      table.concat(patched_lines, '\n'),
      { result_type = 'indices', algorithm = 'myers', ctxlen = 3 }
    )
    if hunks and #hunks > 0 then
      local first = hunks[1][1]
      local last = hunks[#hunks][1] + hunks[#hunks][2] - 1
      return first, last
    end
  end
  return nil, nil
end

return M
