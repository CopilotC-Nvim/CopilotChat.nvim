---@class CopilotChat.context.symbol
---@field name string?
---@field signature string
---@field type string
---@field start_row number
---@field start_col number
---@field end_row number
---@field end_col number

---@class CopilotChat.context.embed
---@field content string
---@field filename string
---@field filetype string
---@field outline string?
---@field symbols table<string, CopilotChat.context.symbol>?
---@field embedding table<number>?

local async = require('plenary.async')
local log = require('plenary.log')
local notify = require('CopilotChat.notify')
local utils = require('CopilotChat.utils')
local file_cache = {}
local url_cache = {}

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
  'field_declaration',
  'class_definition',
  'class_declaration',
  'interface_definition',
  'interface_declaration',
  'record_declaration',
  'type_alias_declaration',
  'import_statement',
  'import_from_statement',
  'atx_heading',
  'list_item',
}

local NAME_TYPES = {
  'name',
  'identifier',
  'heading_content',
}

local OFF_SIDE_RULE_LANGUAGES = {
  'python',
  'coffeescript',
  'nim',
  'elm',
  'curry',
  'fsharp',
}

local TOP_SYMBOLS = 100
local TOP_RELATED = 25
local MULTI_FILE_THRESHOLD = 5

--- Compute the cosine similarity between two vectors
---@param a table<number>
---@param b table<number>
---@return number
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

--- Rank data by relatedness to the query
---@param query CopilotChat.context.embed
---@param data table<CopilotChat.context.embed>
---@param top_n number
---@return table<CopilotChat.context.embed>
local function data_ranked_by_relatedness(query, data, top_n)
  data = vim.tbl_map(function(item)
    return vim.tbl_extend(
      'force',
      item,
      { score = spatial_distance_cosine(item.embedding, query.embedding) }
    )
  end, data)

  table.sort(data, function(a, b)
    return a.score > b.score
  end)

  return vim.list_slice(data, 1, top_n)
end

--- Rank data by symbols
---@param query string
---@param data table<CopilotChat.context.embed>
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

--- Get the full signature of a declaration
---@param start_row number
---@param start_col number
---@param lines table<number, string>
---@return string
local function get_full_signature(start_row, start_col, lines)
  local start_line = lines[start_row + 1]
  local signature = vim.trim(start_line:sub(start_col + 1))

  -- Look ahead for opening brace on next line
  if not signature:match('{') and (start_row + 2) <= #lines then
    local next_line = vim.trim(lines[start_row + 2])
    if next_line:match('^{') then
      signature = signature .. ' {'
    end
  end

  return signature
end

--- Get the name of a node
---@param node table
---@param content string
---@return string?
local function get_node_name(node, content)
  for _, name_type in ipairs(NAME_TYPES) do
    local name_field = node:field(name_type)
    if name_field and #name_field > 0 then
      return vim.treesitter.get_node_text(name_field[1], content)
    end
  end

  return nil
end

--- Build an outline and symbols from a string
---@param content string
---@param filename string
---@param ft string
---@return CopilotChat.context.embed
local function build_outline(content, filename, ft)
  ---@type CopilotChat.context.embed
  local output = {
    filename = filename,
    filetype = ft,
    content = content,
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
      return output
    end
  end

  local root = parser:parse()[1]:root()
  local lines = vim.split(content, '\n')
  local symbols = {}
  local outline_lines = {}
  local depth = 0

  local function parse_node(node)
    local type = node:type()
    local is_outline = vim.tbl_contains(OUTLINE_TYPES, type)
    local start_row, start_col, end_row, end_col = node:range()

    if is_outline then
      depth = depth + 1
      local name = get_node_name(node, content)
      local signature_start = get_full_signature(start_row, start_col, lines)
      table.insert(outline_lines, string.rep('  ', depth) .. signature_start)

      -- Store symbol information
      table.insert(symbols, {
        name = name,
        signature = signature_start,
        type = type,
        start_row = start_row + 1,
        start_col = start_col + 1,
        end_row = end_row,
        end_col = end_col,
      })
    end

    for child in node:iter_children() do
      parse_node(child)
    end

    if is_outline then
      if not vim.tbl_contains(OFF_SIDE_RULE_LANGUAGES, ft) then
        local end_line = lines[end_row + 1]
        local signature_end = vim.trim(end_line:sub(1, end_col))
        table.insert(outline_lines, string.rep('  ', depth) .. signature_end)
      end
      depth = depth - 1
    end
  end

  parse_node(root)

  if #outline_lines > 0 then
    output.outline = table.concat(outline_lines, '\n')
    output.symbols = symbols
  end

  return output
end

--- Get data for a file
---@param filename string
---@param filetype string
---@return CopilotChat.context.embed?
local function get_file(filename, filetype)
  local modified = utils.file_mtime(filename)
  if not modified then
    return nil
  end

  local cached = file_cache[filename]
  if cached and cached.modified >= modified then
    return cached.outline
  end

  local content = utils.read_file(filename)
  if content then
    local outline = build_outline(content, filename, filetype)
    file_cache[filename] = {
      outline = outline,
      modified = modified,
    }

    return outline
  end

  return nil
end

--- Get list of all files in workspace
---@param winnr number?
---@param with_content boolean
---@return table<CopilotChat.context.embed>
function M.files(winnr, with_content)
  local cwd = utils.win_cwd(winnr)

  notify.publish(notify.STATUS, 'Scanning files')

  local files = utils.scan_dir(cwd, {
    add_dirs = false,
    respect_gitignore = true,
  })

  notify.publish(notify.STATUS, 'Reading files')

  local out = {}

  -- Create file list in chunks
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

  -- Read all files if we want content as well
  if with_content then
    async.util.scheduler()

    files = vim.tbl_filter(
      function(file)
        return file.ft ~= nil
      end,
      vim.tbl_map(function(file)
        return {
          name = utils.filepath(file),
          ft = utils.filetype(file),
        }
      end, files)
    )

    for _, file in ipairs(files) do
      local file_data = get_file(file.name, file.ft)
      if file_data then
        table.insert(out, file_data)
      end
    end
  end

  return out
end

--- Get the content of a file
---@param filename? string
---@return CopilotChat.context.embed?
function M.file(filename)
  if not filename or filename == '' then
    return nil
  end

  notify.publish(notify.STATUS, 'Reading file ' .. filename)

  async.util.scheduler()
  local ft = utils.filetype(filename)
  if not ft then
    return nil
  end

  return get_file(utils.filepath(filename), ft)
end

--- Get the content of a buffer
---@param bufnr number
---@return CopilotChat.context.embed?
function M.buffer(bufnr)
  async.util.scheduler()

  if not utils.buf_valid(bufnr) then
    return nil
  end

  local content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if not content or #content == 0 then
    return nil
  end

  return build_outline(
    table.concat(content, '\n'),
    utils.filepath(vim.api.nvim_buf_get_name(bufnr)),
    vim.bo[bufnr].filetype
  )
end

--- Get content of all buffers
---@param buf_type string
---@return table<CopilotChat.context.embed>
function M.buffers(buf_type)
  async.util.scheduler()

  return vim.tbl_map(
    M.buffer,
    vim.tbl_filter(function(b)
      return utils.buf_valid(b)
        and vim.fn.buflisted(b) == 1
        and (buf_type == 'listed' or #vim.fn.win_findbuf(b) > 0)
    end, vim.api.nvim_list_bufs())
  )
end

--- Get the content of an URL
---@param url string
---@return CopilotChat.context.embed?
function M.url(url)
  if not url or url == '' then
    return nil
  end

  local content = url_cache[url]
  if not content then
    notify.publish(notify.STATUS, 'Fetching ' .. url)

    local ok, out = async.util.apcall(utils.system, { 'lynx', '-dump', url })
    if ok and out and out.code == 0 then
      -- Use lynx to fetch content
      content = out.stdout
    else
      -- Fallback to curl if lynx fails
      local response = utils.curl_get(url, { raw = { '-L' } })
      if not response or not response.body then
        return nil
      end

      content = vim.trim(response
        .body
        -- Remove script, style tags and their contents first
        :gsub(
          '<script.-</script>',
          ''
        )
        :gsub('<style.-</style>', '')
        -- Remove XML/CDATA in one go
        :gsub('<!?%[?[%w%s]*%]?>', '')
        -- Remove all HTML tags (both opening and closing) in one go
        :gsub(
          '<%/?%w+[^>]*>',
          ' '
        )
        -- Handle common HTML entities
        :gsub('&(%w+);', {
          nbsp = ' ',
          lt = '<',
          gt = '>',
          amp = '&',
          quot = '"',
        })
        -- Remove any remaining HTML entities (numeric or named)
        :gsub('&#?%w+;', ''))
    end

    url_cache[url] = content
  end

  return {
    content = content,
    filename = url,
    filetype = 'text',
  }
end

--- Get current git diff
---@param type string
---@param winnr number
---@return CopilotChat.context.embed?
function M.gitdiff(type, winnr)
  notify.publish(notify.STATUS, 'Fetching git diff')

  local cwd = utils.win_cwd(winnr)
  local cmd = {
    'git',
    '-C',
    cwd,
    'diff',
    '--no-color',
    '--no-ext-diff',
  }

  if type == 'staged' then
    table.insert(cmd, '--staged')
  end

  local out = utils.system(cmd)

  return {
    content = out.stdout,
    filename = 'git_diff_' .. type,
    filetype = 'diff',
  }
end

--- Return contents of specified register
---@param register string
---@return CopilotChat.context.embed?
function M.register(register)
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
---@param embeddings table<CopilotChat.context.embed>
---@return table<CopilotChat.context.embed>
function M.filter_embeddings(copilot, prompt, embeddings)
  -- If we dont need to embed anything, just return directly
  if #embeddings < MULTI_FILE_THRESHOLD then
    return embeddings
  end

  -- Rank embeddings by symbols
  embeddings = data_ranked_by_symbols(prompt, embeddings, TOP_SYMBOLS)
  log.debug('Ranked data:', #embeddings)
  for i, item in ipairs(embeddings) do
    log.debug(string.format('%s: %s - %s', i, item.score, item.filename))
  end

  -- Add prompt so it can be embedded
  table.insert(embeddings, {
    content = prompt,
    filename = 'prompt',
    filetype = 'raw',
  })

  -- Get embeddings from all items
  embeddings = copilot:embed(embeddings)

  -- Rate embeddings by relatedness to the query
  local embedded_query = table.remove(embeddings, #embeddings)
  log.debug('Embedded query:', embedded_query.content)
  embeddings = data_ranked_by_relatedness(embedded_query, embeddings, TOP_RELATED)
  log.debug('Ranked embeddings:', #embeddings)
  for i, item in ipairs(embeddings) do
    log.debug(string.format('%s: %s - %s', i, item.score, item.filename))
  end

  return embeddings
end

return M
