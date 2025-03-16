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
---@field diagnostics table<CopilotChat.Diagnostic>?
---@field symbols table<string, CopilotChat.context.symbol>?
---@field embedding table<number>?
---@field score number?

local async = require('plenary.async')
local log = require('plenary.log')
local client = require('CopilotChat.client')
local notify = require('CopilotChat.notify')
local utils = require('CopilotChat.utils')
local file_cache = {}
local url_cache = {}
local embedding_cache = {}
local outline_cache = {}

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

local MULTI_FILE_THRESHOLD = 5

--- Compute the cosine similarity between two vectors
---@param a table<number>
---@param b table<number>
---@return number
local function spatial_distance_cosine(a, b)
  if not a or not b then
    return 0
  end

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
---@return table<CopilotChat.context.embed>
local function data_ranked_by_relatedness(query, data)
  for _, item in ipairs(data) do
    local score = spatial_distance_cosine(item.embedding, query.embedding)
    item.score = score or item.score or 0
  end

  table.sort(data, function(a, b)
    return a.score > b.score
  end)

  -- Apply dynamic filtering for embedding-based ranking
  local filtered = {}

  if #data > 0 then
    -- Calculate statistics for score distribution
    local sum = 0
    local max_score = data[1].score

    for _, item in ipairs(data) do
      sum = sum + item.score
    end

    local mean = sum / #data

    -- Calculate standard deviation
    local sum_squared_diff = 0
    for _, item in ipairs(data) do
      sum_squared_diff = sum_squared_diff + ((item.score - mean) * (item.score - mean))
    end
    local std_dev = math.sqrt(sum_squared_diff / #data)

    -- Calculate z-scores and use them to determine significance
    -- Include items with z-score > -0.5 (meaning within 0.5 std dev below mean)
    -- This is a statistical approach to find "significantly" related items
    for _, result in ipairs(data) do
      local z_score = (result.score - mean) / std_dev
      if z_score > -0.5 then
        table.insert(filtered, result)
      end
    end

    -- If we didn't get enough results or the distribution is very tight,
    -- use a percentage of max score as fallback
    if #filtered < MULTI_FILE_THRESHOLD then
      filtered = {}
      local adaptive_threshold = max_score * 0.6 -- 60% of max score

      for i, result in ipairs(data) do
        if i <= MULTI_FILE_THRESHOLD or result.score >= adaptive_threshold then
          table.insert(filtered, result)
        end
      end
    end
  end

  return filtered
end

-- Create trigrams from text (e.g., "hello" -> {"hel", "ell", "llo"})
local function get_trigrams(text)
  local trigrams = {}
  text = text:lower()
  for i = 1, #text - 2 do
    trigrams[text:sub(i, i + 2)] = true
  end
  return trigrams
end

-- Calculate Jaccard similarity between two trigram sets
local function trigram_similarity(set1, set2)
  local intersection = 0
  local union = 0

  -- Count intersection and union
  for trigram in pairs(set1) do
    if set2[trigram] then
      intersection = intersection + 1
    end
    union = union + 1
  end

  for trigram in pairs(set2) do
    if not set1[trigram] then
      union = union + 1
    end
  end

  return intersection / union
end

--- Rank data by symbols and filenames
---@param query string
---@param data table<CopilotChat.context.embed>
---@return table<CopilotChat.context.embed>
local function data_ranked_by_symbols(query, data)
  -- Get query trigrams including compound versions
  local query_trigrams = {}

  -- Add trigrams for each word
  for term in query:gmatch('%w+') do
    for trigram in pairs(get_trigrams(term)) do
      query_trigrams[trigram] = true
    end
  end

  -- Add trigrams for compound query
  local compound_query = query:gsub('[^%w]', '')
  for trigram in pairs(get_trigrams(compound_query)) do
    query_trigrams[trigram] = true
  end

  local max_score = 0

  for _, entry in ipairs(data) do
    local basename = utils.filename(entry.filename):gsub('%..*$', '')

    -- Get trigrams for basename and compound version
    local file_trigrams = get_trigrams(basename)
    local compound_trigrams = get_trigrams(basename:gsub('[^%w]', ''))

    -- Calculate similarities
    local name_sim = trigram_similarity(query_trigrams, file_trigrams)
    local compound_sim = trigram_similarity(query_trigrams, compound_trigrams)

    -- Take best match
    local score = (entry.score or 0) + math.max(name_sim, compound_sim)

    -- Add symbol matches
    if entry.symbols then
      local symbol_score = 0
      for _, symbol in ipairs(entry.symbols) do
        if symbol.name then
          local symbol_trigrams = get_trigrams(symbol.name)
          local sym_sim = trigram_similarity(query_trigrams, symbol_trigrams)
          symbol_score = math.max(symbol_score, sym_sim)
        end
      end
      score = score + (symbol_score * 0.5) -- Weight symbol matches less
    end

    max_score = math.max(max_score, score)
    entry.score = score
  end

  -- Normalize scores
  for _, entry in ipairs(data) do
    entry.score = entry.score / max_score
  end

  -- Sort by score first
  table.sort(data, function(a, b)
    return a.score > b.score
  end)

  -- Use elbow method to find natural cutoff point for symbol-based ranking
  local filtered_results = {}

  if #data > 0 then
    -- Always include at least the top result
    table.insert(filtered_results, data[1])

    -- Find the point of maximum drop-off (the "elbow")
    local max_drop = 0
    local cutoff_index = math.min(MULTI_FILE_THRESHOLD, #data)

    for i = 2, math.min(20, #data) do
      local drop = data[i - 1].score - data[i].score
      if drop > max_drop then
        max_drop = drop
        cutoff_index = i
      end
    end

    -- Include everything up to the cutoff point
    for i = 2, cutoff_index do
      table.insert(filtered_results, data[i])
    end

    -- Also include any remaining items that have scores close to the cutoff
    local cutoff_score = data[cutoff_index].score
    local threshold = cutoff_score * 0.8 -- Within 80% of the cutoff score

    for i = cutoff_index + 1, #data do
      if data[i].score >= threshold then
        table.insert(filtered_results, data[i])
      end
    end
  end

  return filtered_results
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
---@param ft string
---@return string?, table<string, CopilotChat.context.symbol>?
local function get_outline(content, ft)
  if not ft or ft == '' or ft == 'text' or ft == 'raw' then
    return nil
  end

  local lang = vim.treesitter.language.get_lang(ft)
  local ok, parser = false, nil
  if lang then
    ok, parser = pcall(vim.treesitter.get_string_parser, content, lang)
  end
  if not ok or not parser then
    ft = string.gsub(ft, 'react', '')
    ok, parser = pcall(vim.treesitter.get_string_parser, content, ft)
    if not ok or not parser then
      return nil
    end
  end

  local root = utils.ts_parse(parser)
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

  if #outline_lines == 0 then
    return nil
  end
  return table.concat(outline_lines, '\n'), symbols
end

--- Get data for a file
---@param filename string
---@param filetype string?
---@return CopilotChat.context.embed?
function M.get_file(filename, filetype)
  if not filetype then
    return nil
  end

  local modified = utils.file_mtime(filename)
  if not modified then
    return nil
  end

  local cached = file_cache[filename]
  if cached and cached._modified >= modified then
    return {
      content = cached.content,
      _modified = cached._modified,
      filename = filename,
      filetype = filetype,
    }
  end

  local content = utils.read_file(filename)
  if not content or content == '' then
    return nil
  end

  local out = {
    content = content,
    filename = filename,
    filetype = filetype,
    _modified = modified,
  }

  file_cache[filename] = out
  return out
end

--- Get data for a buffer
---@param bufnr number
---@return CopilotChat.context.embed?
function M.get_buffer(bufnr)
  if not utils.buf_valid(bufnr) then
    return nil
  end

  local content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if not content or #content == 0 then
    return nil
  end

  return {
    content = table.concat(content, '\n'),
    filename = utils.filepath(vim.api.nvim_buf_get_name(bufnr)),
    filetype = vim.bo[bufnr].filetype,
    score = 0.1,
    diagnostics = utils.diagnostics(bufnr),
  }
end

--- Get the content of an URL
---@param url string
---@return CopilotChat.context.embed?
function M.get_url(url)
  if not url or url == '' then
    return nil
  end

  local content = url_cache[url]
  if not content then
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
        :gsub('<script.-</script>', '')
        :gsub('<style.-</style>', '')
        -- Remove XML/CDATA in one go
        :gsub('<!?%[?[%w%s]*%]?>', '')
        -- Remove all HTML tags (both opening and closing) in one go
        :gsub('<%/?%w+[^>]*>', ' ')
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

--- Filter embeddings based on the query
---@param prompt string
---@param model string
---@param headless boolean
---@param embeddings table<CopilotChat.context.embed>
---@return table<CopilotChat.context.embed>
function M.filter_embeddings(prompt, model, headless, embeddings)
  -- If we dont need to embed anything, just return directly
  if #embeddings < MULTI_FILE_THRESHOLD then
    return embeddings
  end

  notify.publish(notify.STATUS, 'Preparing embedding outline')

  for _, input in ipairs(embeddings) do
    -- Precalculate hash and attributes for caching
    local hash = input.filename .. utils.quick_hash(input.content)
    input._hash = hash
    input.filename = input.filename or 'unknown'
    input.filetype = input.filetype or 'text'

    local outline = outline_cache[hash]
    if not outline then
      local outline_text, symbols = get_outline(input.content, input.filetype)
      if outline_text then
        outline = {
          outline = outline_text,
          symbols = symbols,
        }

        outline_cache[hash] = outline
      end
    end

    if outline then
      input.outline = outline.outline
      input.symbols = outline.symbols
    end
  end

  notify.publish(notify.STATUS, 'Ranking embeddings')

  -- Build query from history and prompt
  local query = prompt
  if not headless then
    query = table.concat(
      vim
        .iter(client.history)
        :filter(function(m)
          return m.role == 'user'
        end)
        :map(function(m)
          return vim.trim(m.content)
        end)
        :totable(),
      '\n'
    ) .. '\n' .. prompt
  end

  -- Rank embeddings by symbols
  embeddings = data_ranked_by_symbols(query, embeddings)
  log.debug('Ranked data:', #embeddings)
  for i, item in ipairs(embeddings) do
    log.debug(string.format('%s: %s - %s', i, item.score, item.filename))
  end

  -- Prepare embeddings for processing
  local to_process = {}
  local results = {}
  for _, input in ipairs(embeddings) do
    local hash = input._hash
    local embed = embedding_cache[hash]
    if embed then
      input.embedding = embed
      table.insert(results, input)
    else
      table.insert(to_process, input)
    end
  end
  table.insert(to_process, {
    content = query,
    filename = 'query',
    filetype = 'raw',
  })

  -- Embed the data and process the results
  for _, input in ipairs(client:embed(to_process, model)) do
    if input.filetype ~= 'raw' then
      embedding_cache[input._hash] = input.embedding
    end
    table.insert(results, input)
  end

  -- Rate embeddings by relatedness to the query
  local embedded_query = table.remove(results, #results)
  log.debug('Embedded query:', embedded_query.content)
  results = data_ranked_by_relatedness(embedded_query, results)
  log.debug('Ranked embeddings:', #results)
  for i, item in ipairs(results) do
    log.debug(string.format('%s: %s - %s', i, item.score, item.filename))
  end

  return results
end

return M
