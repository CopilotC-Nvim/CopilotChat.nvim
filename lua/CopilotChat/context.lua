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

local big_file_threshold = 500

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

--- Build an outline for a buffer
--- FIXME: Handle multiline function argument definitions when building the outline
---@param bufnr number
---@return CopilotChat.copilot.embed?
function M.build_outline(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  local ft = vim.bo[bufnr].filetype

  -- If buffer is not too big, just return the content
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines < big_file_threshold then
    return {
      content = table.concat(lines, '\n'),
      filename = name,
      filetype = ft,
    }
  end

  local lang = vim.treesitter.language.get_lang(ft)
  local ok, parser = false, nil
  if lang then
    ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  end
  if not ok or not parser then
    ft = string.gsub(ft, 'react', '')
    ok, parser = pcall(vim.treesitter.get_parser, bufnr, ft)
    if not ok or not parser then
      return
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

      local start_line = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, false)[1]
      local signature_start =
        vim.api.nvim_buf_get_text(bufnr, start_row, start_col, start_row, #start_line, {})[1]
      table.insert(outline_lines, string.rep('  ', depth) .. vim.trim(signature_start))

      -- If the function definition spans multiple lines, add an ellipsis
      if start_row ~= end_row then
        table.insert(outline_lines, string.rep('  ', depth + 1) .. '...')
      else
        skip_inner = true
      end
    elseif is_comment then
      skip_inner = true
      local comment = vim.split(vim.treesitter.get_node_text(node, bufnr, {}), '\n')
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
        local signature_end =
          vim.trim(vim.api.nvim_buf_get_text(bufnr, end_row, 0, end_row, end_col, {})[1])
        table.insert(outline_lines, string.rep('  ', depth) .. signature_end)
      end
      depth = depth - 1
    end
  end

  get_outline_lines(root)
  local content = table.concat(outline_lines, '\n')
  if content == '' then
    return
  end

  return {
    content = table.concat(outline_lines, '\n'),
    filename = name,
    filetype = ft,
  }
end

---@class CopilotChat.context.find_for_query.opts
---@field context string?
---@field prompt string
---@field selection string?
---@field filename string
---@field filetype string
---@field bufnr number
---@field on_done function
---@field on_error function?

--- Find items for a query
---@param copilot CopilotChat.Copilot
---@param opts CopilotChat.context.find_for_query.opts
function M.find_for_query(copilot, opts)
  local context = opts.context
  local prompt = opts.prompt
  local selection = opts.selection
  local filename = opts.filename
  local filetype = opts.filetype
  local bufnr = opts.bufnr
  local on_done = opts.on_done
  local on_error = opts.on_error

  local outline = {}
  if context == 'buffers' then
    -- For multiple buffers, only make outlines
    outline = vim.tbl_map(
      function(b)
        return M.build_outline(b)
      end,
      vim.tbl_filter(function(b)
        return vim.api.nvim_buf_is_loaded(b) and vim.fn.buflisted(b) == 1
      end, vim.api.nvim_list_bufs())
    )
  elseif context == 'buffer' then
    table.insert(outline, M.build_outline(bufnr))
  end

  outline = vim.tbl_filter(function(item)
    return item ~= nil
  end, outline)

  if #outline == 0 then
    on_done({})
    return
  end

  copilot:embed(outline, {
    on_error = on_error,
    on_done = function(out)
      out = vim.tbl_filter(function(item)
        return item ~= nil
      end, out)
      if #out == 0 then
        on_done({})
        return
      end

      log.debug(string.format('Got %s embeddings', #out))
      copilot:embed({
        {
          prompt = prompt,
          content = selection,
          filename = filename,
          filetype = filetype,
        },
      }, {
        on_error = on_error,
        on_done = function(query_out)
          local query = query_out[1]
          log.debug('Prompt:', query.prompt)
          log.debug('Content:', query.content)
          local data = data_ranked_by_relatedness(query, out, 20)
          log.debug('Ranked data:', #data)
          for i, item in ipairs(data) do
            log.debug(string.format('%s: %s - %s', i, item.score, item.filename))
          end
          on_done(data)
        end,
      })
    end,
  })
end

return M
