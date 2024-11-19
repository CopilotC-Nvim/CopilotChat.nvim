local log = require('plenary.log')

local M = {}

local outline_types = {
  'local_function',
  'function_item',
  'arrow_function',
  'function_definition',
  'function_declaration',
  'method_definition',
  'method_declaration',
  'constructor_declaration',
  'class_definition',
  'class_declaration',
  'interface_definition',
  'interface_declaration',
  'type_alias_declaration',
  'import_statement',
  'import_from_statement',
}

local comment_types = {
  'comment',
  'line_comment',
  'block_comment',
  'doc_comment',
}

local ignored_types = {
  'export_statement',
}

local off_side_rule_languages = {
  'python',
  'coffeescript',
  'nim',
  'elm',
  'curry',
  'fsharp',
}

local multi_file_threshold = 2

local function spatial_distance_cosine(a, b)
  local dot_product = 0
  local magnitude_a = 0
  local magnitude_b = 0
  for i = 1, #a do
    dot_product = dot_product + a[i] * b[i]
    magnitude_a = magnitude_a + a[i] * a[i]
    magnitude_b = magnitude_b + b[i] * b[i]
  end
  magnitude_a = math.sqrt(magnitude_a)
  magnitude_b = math.sqrt(magnitude_b)
  return dot_product / (magnitude_a * magnitude_b)
end

local function data_ranked_by_relatedness(query, data, top_n)
  local scores = {}
  for i, item in pairs(data) do
    scores[i] = { index = i, score = spatial_distance_cosine(item.embedding, query.embedding) }
  end
  table.sort(scores, function(a, b)
    return a.score > b.score
  end)
  local result = {}
  for i = 1, math.min(top_n, #scores) do
    local srt = scores[i]
    table.insert(result, vim.tbl_extend('keep', data[srt.index], { score = srt.score }))
  end
  return result
end

--- Build an outline from a string
--- FIXME: Handle multiline function argument definitions when building the outline
---@param content string
---@param name string
---@param ft string?
---@return CopilotChat.copilot.embed
function M.outline(content, name, ft)
  ft = ft or 'text'
  local lines = vim.split(content, '\n')

  local base_output = {
    content = content,
    filename = name,
    filetype = ft,
  }

  local lang = vim.treesitter.language.get_lang(ft)
  local ok, parser = false, nil
  if lang then
    ok, parser = pcall(vim.treesitter.get_string_parser, content, lang)
  end
  if not ok or not parser then
    ft = string.gsub(ft, 'react', '')
    ok, parser = pcall(vim.treesitter.get_string_parser, content, ft)
    if not ok or not parser then
      return base_output
    end
  end

  local root = parser:parse()[1]:root()
  local outline_lines = {}
  local comment_lines = {}
  local depth = 0

  local function get_outline_lines(node)
    local type = node:type()
    local parent = node:parent()
    local is_outline = vim.tbl_contains(outline_types, type)
    local is_comment = vim.tbl_contains(comment_types, type)
    local is_ignored = vim.tbl_contains(ignored_types, type)
      or parent and vim.tbl_contains(ignored_types, parent:type())
    local start_row, start_col, end_row, end_col = node:range()
    local skip_inner = false

    if is_outline then
      depth = depth + 1

      if #comment_lines > 0 then
        for _, line in ipairs(comment_lines) do
          table.insert(outline_lines, string.rep('  ', depth) .. line)
        end
        comment_lines = {}
      end

      local start_line = lines[start_row + 1]
      local signature_start = start_line:sub(start_col + 1)
      table.insert(outline_lines, string.rep('  ', depth) .. vim.trim(signature_start))

      -- If the function definition spans multiple lines, add an ellipsis
      if start_row ~= end_row then
        table.insert(outline_lines, string.rep('  ', depth + 1) .. '...')
      else
        skip_inner = true
      end
    elseif is_comment then
      skip_inner = true
      local comment = vim.split(vim.treesitter.get_node_text(node, content), '\n')
      for _, line in ipairs(comment) do
        table.insert(comment_lines, vim.trim(line))
      end
    elseif not is_ignored then
      comment_lines = {}
    end

    if not skip_inner then
      for child in node:iter_children() do
        get_outline_lines(child)
      end
    end

    if is_outline then
      if not skip_inner and not vim.tbl_contains(off_side_rule_languages, ft) then
        local end_line = lines[end_row + 1]
        local signature_end = vim.trim(end_line:sub(1, end_col))
        table.insert(outline_lines, string.rep('  ', depth) .. signature_end)
      end
      depth = depth - 1
    end
  end

  get_outline_lines(root)
  local result_content = table.concat(outline_lines, '\n')
  if result_content == '' then
    return base_output
  end

  return {
    content = result_content,
    filename = name,
    filetype = ft,
  }
end

--- Get list of all files in workspace
---@param pattern string?
---@return table<CopilotChat.copilot.embed>
function M.files(pattern)
  local files = vim.tbl_filter(function(file)
    return vim.fn.isdirectory(file) == 0
  end, vim.fn.glob(pattern or '**/*', false, true))

  if #files == 0 then
    return {}
  end

  local out = {}

  -- Create embeddings in chunks
  local chunk_size = 100
  for i = 1, #files, chunk_size do
    local chunk = {}
    for j = i, math.min(i + chunk_size - 1, #files) do
      table.insert(chunk, files[j])
    end

    table.insert(out, {
      content = table.concat(chunk, '\n'),
      filename = 'file_map_' .. tostring(i),
      filetype = 'text',
    })
  end

  return out
end

--- Get the content of a file
---@param filename string
---@return CopilotChat.copilot.embed?
function M.file(filename)
  local content = vim.fn.readfile(filename)
  if not content or #content == 0 then
    return nil
  end

  return {
    content = table.concat(content, '\n'),
    filename = vim.fn.fnamemodify(filename, ':p:.'),
    filetype = vim.filetype.match({ filename = filename }),
  }
end

--- Get the content of a buffer
---@param bufnr number
---@return CopilotChat.copilot.embed?
function M.buffer(bufnr)
  local content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if not content or #content == 0 then
    return nil
  end

  return {
    content = table.concat(content, '\n'),
    filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':p:.'),
    filetype = vim.bo[bufnr].filetype,
  }
end

--- Get current git diff
---@param type string?
---@param bufnr number
---@return CopilotChat.copilot.embed?
function M.gitdiff(type, bufnr)
  type = type or 'unstaged'
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local file_path = bufname:gsub('^%w+://', '')
  local dir = vim.fn.fnamemodify(file_path, ':h')
  if not dir or dir == '' then
    return nil
  end
  dir = dir:gsub('.git$', '')

  local cmd = 'git -C ' .. dir .. ' diff --no-color --no-ext-diff'

  if type == 'staged' then
    cmd = cmd .. ' --staged'
  end

  local handle = io.popen(cmd)
  if not handle then
    return nil
  end

  local result = handle:read('*a')
  handle:close()
  if not result or result == '' then
    return nil
  end

  return {
    content = result,
    filename = 'git_diff_' .. type,
    filetype = 'diff',
  }
end

--- Filter embeddings based on the query
---@param copilot CopilotChat.Copilot
---@param prompt string
---@param embeddings table<CopilotChat.copilot.embed>
---@return table<CopilotChat.copilot.embed>
function M.filter_embeddings(copilot, prompt, embeddings)
  -- If we dont need to embed anything, just return directly
  if #embeddings <= multi_file_threshold then
    return embeddings
  end

  table.insert(embeddings, 1, {
    content = prompt,
    filename = 'prompt',
    filetype = 'raw',
  })

  -- Get embeddings from outlines
  local embedded_data = copilot:embed(vim.tbl_map(function(embed)
    if embed.filetype ~= 'raw' then
      return M.outline(embed.content, embed.filename, embed.filetype)
    end

    return embed
  end, embeddings))

  -- Rate embeddings by relatedness to the query
  local ranked_data = data_ranked_by_relatedness(table.remove(embedded_data, 1), embedded_data, 20)
  log.debug('Ranked data:', #ranked_data)
  for i, item in ipairs(ranked_data) do
    log.debug(string.format('%s: %s - %s', i, item.score, item.filename))
  end

  -- Return original content but keep the ranking order and scores
  local result = {}
  for _, ranked_item in ipairs(ranked_data) do
    for _, original in ipairs(embeddings) do
      if original.filename == ranked_item.filename then
        table.insert(result, original)
        break
      end
    end
  end

  return result
end

return M
