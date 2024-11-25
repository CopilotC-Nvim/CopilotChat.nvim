---@class CopilotChat.context.symbol
---@field name string?
---@field signature string
---@field type string
---@field start_row number
---@field start_col number
---@field end_row number
---@field end_col number

---@class CopilotChat.context.outline : CopilotChat.copilot.embed
---@field symbols table<string, CopilotChat.context.symbol>

local log = require('plenary.log')
local utils = require('CopilotChat.utils')

local M = {}

local OUTLINE_TYPES = {
  'local_function',
  'function_item',
  'arrow_function',
  'function_definition',
  'function_declaration',
  'method_definition',
  'method_declaration',
  'proc_declaration',
  'template_declaration',
  'macro_declaration',
  'constructor_declaration',
  'class_definition',
  'class_declaration',
  'interface_definition',
  'interface_declaration',
  'type_alias_declaration',
  'import_statement',
  'import_from_statement',
  -- markdown
  'atx_heading',
  'list_item',
}

local NAME_TYPES = {
  'name',
  'identifier',
  'heading_content',
}

local COMMENT_TYPES = {
  'comment',
  'line_comment',
  'block_comment',
  'doc_comment',
}

local IGNORED_TYPES = {
  'export_statement',
}

local OFF_SIDE_RULE_LANGUAGES = {
  'python',
  'coffeescript',
  'nim',
  'elm',
  'curry',
  'fsharp',
}

local TOP_SYMBOLS = 64
local TOP_RELATED = 20
local MULTI_FILE_THRESHOLD = 3

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

---@param query string
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
    table.insert(result, vim.tbl_extend('force', data[srt.index], { score = srt.score }))
  end
  return result
end

---@param query string
---@param data table<CopilotChat.context.outline>
---@param top_n number
local function data_ranked_by_symbols(query, data, top_n)
  local query_terms = {}
  for term in query:lower():gmatch('%w+') do
    query_terms[term] = true
  end

  local results = {}
  for _, entry in ipairs(data) do
    local score = 0
    local filename = entry.filename and entry.filename:lower() or ''

    -- Filename matches (highest priority)
    for term in pairs(query_terms) do
      if filename:find(term, 1, true) then
        score = score + 15
        if vim.fn.fnamemodify(filename, ':t'):gsub('%..*$', '') == term then
          score = score + 10
        end
      end
    end

    -- Symbol matches
    if entry.symbols then
      for _, symbol in ipairs(entry.symbols) do
        for term in pairs(query_terms) do
          -- Check symbol name (high priority)
          if symbol.name and symbol.name:lower():find(term, 1, true) then
            score = score + 5
            if symbol.name:lower() == term then
              score = score + 3
            end
          end

          -- Check signature (medium priority)
          -- This catches parameter names, return types, etc
          if symbol.signature and symbol.signature:lower():find(term, 1, true) then
            score = score + 2
          end
        end
      end
    end

    table.insert(results, vim.tbl_extend('force', entry, { score = score }))
  end

  table.sort(results, function(a, b)
    return a.score > b.score
  end)
  return vim.list_slice(results, 1, top_n)
end

--- Build an outline and symbols from a string
--- FIXME: Handle multiline function argument definitions when building the outline
---@param content string
---@param name string
---@param ft string?
---@return CopilotChat.context.outline
function M.outline(content, name, ft)
  ft = ft or 'text'

  local output = {
    filename = name,
    filetype = ft,
    content = content,
    symbols = {},
  }

  if ft == 'raw' then
    return output
  end

  local lines = vim.split(content, '\n')
  local lang = vim.treesitter.language.get_lang(ft)
  local ok, parser = false, nil
  if lang then
    ok, parser = pcall(vim.treesitter.get_string_parser, content, lang)
  end
  if not ok or not parser then
    ft = string.gsub(ft, 'react', '')
    ok, parser = pcall(vim.treesitter.get_string_parser, content, ft)
    if not ok or not parser then
      return output
    end
  end

  local root = parser:parse()[1]:root()
  local outline_lines = {}
  local comment_lines = {}
  local depth = 0

  local function get_node_name(node)
    for _, name_type in ipairs(NAME_TYPES) do
      local name_field = node:field(name_type)
      if name_field and #name_field > 0 then
        return vim.treesitter.get_node_text(name_field[1], content)
      end
    end

    return nil
  end

  local function parse_node(node)
    local type = node:type()
    local parent = node:parent()
    local is_outline = vim.tbl_contains(OUTLINE_TYPES, type)
    local is_comment = vim.tbl_contains(COMMENT_TYPES, type)
    local is_ignored = vim.tbl_contains(IGNORED_TYPES, type)
      or parent and vim.tbl_contains(IGNORED_TYPES, parent:type())
    local start_row, start_col, end_row, end_col = node:range()
    local skip_inner = false

    if is_outline then
      depth = depth + 1

      -- Handle comments
      if #comment_lines > 0 then
        for _, line in ipairs(comment_lines) do
          table.insert(outline_lines, string.rep('  ', depth) .. line)
        end
        comment_lines = {}
      end

      local start_line = lines[start_row + 1]
      local signature_start = vim.trim(start_line:sub(start_col + 1))
      table.insert(outline_lines, string.rep('  ', depth) .. signature_start)

      -- Store symbol information
      table.insert(output.symbols, {
        name = get_node_name(node),
        signature = signature_start,
        type = type,
        start_row = start_row + 1,
        start_col = start_col + 1,
        end_row = end_row,
        end_col = end_col,
      })

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
        parse_node(child)
      end
    end

    if is_outline then
      if not skip_inner and not vim.tbl_contains(OFF_SIDE_RULE_LANGUAGES, ft) then
        local end_line = lines[end_row + 1]
        local signature_end = vim.trim(end_line:sub(1, end_col))
        table.insert(outline_lines, string.rep('  ', depth) .. signature_end)
      end
      depth = depth - 1
    end
  end

  parse_node(root)

  if #outline_lines > 0 then
    output.content = table.concat(outline_lines, '\n')
  end

  return output
end

--- Get list of all files in workspace
---@param pattern string?
---@param winnr number?
---@return table<CopilotChat.copilot.embed>
function M.files(pattern, winnr)
  local cwd = utils.win_cwd(winnr)
  local search = cwd .. '/' .. (pattern or '**/*')
  local files = vim.tbl_filter(function(file)
    return vim.fn.isdirectory(file) == 0
  end, vim.fn.glob(search, false, true))

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

    local chunk_number = math.floor(i / chunk_size)
    local chunk_name = chunk_number == 0 and 'file_map' or 'file_map' .. tostring(chunk_number)

    table.insert(out, {
      content = table.concat(chunk, '\n'),
      filename = chunk_name,
      filetype = 'text',
    })
  end

  return out
end

--- Get the content of a file
---@param filename string
---@return CopilotChat.copilot.embed?
function M.file(filename)
  if vim.fn.filereadable(filename) ~= 1 then
    return nil
  end

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
  if not utils.buf_valid(bufnr) then
    return nil
  end

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
---@param winnr number
---@return CopilotChat.copilot.embed?
function M.gitdiff(type, winnr)
  type = type or 'unstaged'
  local cwd = utils.win_cwd(winnr)
  local cmd = 'git -C ' .. cwd .. ' diff --no-color --no-ext-diff'

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

--- Return contents of specified register
---@param register string?
---@return CopilotChat.copilot.embed?
function M.register(register)
  register = register or '+'
  local lines = vim.fn.getreg(register)
  if not lines or lines == '' then
    return nil
  end

  return {
    content = lines,
    filename = 'vim_register_' .. register,
    filetype = '',
  }
end

--- Filter embeddings based on the query
---@param copilot CopilotChat.Copilot
---@param prompt string
---@param embeddings table<CopilotChat.copilot.embed>
---@return table<CopilotChat.copilot.embed>
function M.filter_embeddings(copilot, prompt, embeddings)
  -- If we dont need to embed anything, just return directly
  if #embeddings < MULTI_FILE_THRESHOLD then
    return embeddings
  end

  local original_map = utils.ordered_map()
  local embedded_map = utils.ordered_map()

  -- Map embeddings by filename
  for _, embed in ipairs(embeddings) do
    original_map:set(embed.filename, embed)
    embedded_map:set(embed.filename, M.outline(embed.content, embed.filename, embed.filetype))
  end

  -- Rank embeddings by symbols
  local ranked_data = data_ranked_by_symbols(prompt, embedded_map:values(), TOP_SYMBOLS)
  log.debug('Ranked data:', #ranked_data)
  for i, item in ipairs(ranked_data) do
    log.debug(string.format('%s: %s - %s', i, item.score, item.filename))
  end

  -- Add prompt so it can be embedded
  table.insert(ranked_data, {
    content = prompt,
    filename = 'prompt',
    filetype = 'raw',
  })

  -- Get embeddings from all items
  local embedded_data = copilot:embed(ranked_data)

  -- Rate embeddings by relatedness to the query
  local embedded_query = table.remove(embedded_data, #embedded_data)
  log.debug('Embedded query:', embedded_query.content)
  local ranked_embeddings = data_ranked_by_relatedness(embedded_query, embedded_data, TOP_RELATED)
  log.debug('Ranked embeddings:', #ranked_embeddings)
  for i, item in ipairs(ranked_embeddings) do
    log.debug(string.format('%s: %s - %s', i, item.score, item.filename))
  end

  -- Return original content in ranked order
  local result = {}
  for _, ranked_item in ipairs(ranked_embeddings) do
    local original = original_map:get(ranked_item.filename)
    if original then
      table.insert(result, original)
    end
  end

  return result
end

return M
