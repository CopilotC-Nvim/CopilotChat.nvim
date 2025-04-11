---@class CopilotChat.tools.Symbol
---@field name string?
---@field signature string
---@field type string
---@field start_row number
---@field start_col number
---@field end_row number
---@field end_col number

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

local INPUT_SEPARATOR = ';;'

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
---@param query CopilotChat.client.EmbeddedResource
---@param data table<CopilotChat.client.EmbeddedResource>
---@return table<CopilotChat.client.EmbeddedResource>
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
---@param data table<CopilotChat.client.Resource>
---@return table<CopilotChat.client.Resource>
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
    local basename = utils.filename(entry.name):gsub('%..*$', '')

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
---@return string?, table<string, CopilotChat.tools.Symbol>?
local function get_outline(content, ft)
  if not ft or ft == '' then
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

local function sorted_propnames(schema)
  local prop_names = vim.tbl_keys(schema.properties)
  local required_set = {}
  if schema.required then
    for _, name in ipairs(schema.required) do
      required_set[name] = true
    end
  end

  -- Sort properties with priority: required without default > required with default > optional
  table.sort(prop_names, function(a, b)
    local a_required = required_set[a] or false
    local b_required = required_set[b] or false
    local a_has_default = schema.properties[a].default ~= nil
    local b_has_default = schema.properties[b].default ~= nil

    -- First priority: required properties without default
    if a_required and not a_has_default and (not b_required or b_has_default) then
      return true
    end
    if b_required and not b_has_default and (not a_required or a_has_default) then
      return false
    end

    -- Second priority: required properties with default
    if a_required and not b_required then
      return true
    end
    if b_required and not a_required then
      return false
    end

    -- Finally sort alphabetically
    return a < b
  end)

  return prop_names
end

local function filter_schema(tbl)
  if type(tbl) ~= 'table' then
    return tbl
  end

  local result = {}
  for k, v in pairs(tbl) do
    if type(v) ~= 'function' and k ~= 'examples' then
      result[k] = type(v) == 'table' and filter_schema(v) or v
    end
  end
  return result
end

---@param uri string The URI to parse
---@param pattern string The pattern to match against (e.g., 'file://{path}')
---@return table|nil inputs Extracted parameters or nil if no match
function M.match_uri(uri, pattern)
  -- Convert the pattern into a Lua pattern by escaping special characters
  -- and replacing {name} placeholders with capture groups
  local lua_pattern = pattern:gsub('([%(%)%.%%%+%-%*%?%[%]%^%$])', '%%%1')

  -- Extract parameter names from the pattern
  local param_names = {}
  for param in pattern:gmatch('{([^}:*]+)[^}]*}') do
    table.insert(param_names, param)
    -- Replace {param} with a capture group in our Lua pattern
    -- Use non-greedy capture to handle multiple params properly
    lua_pattern = lua_pattern:gsub('{' .. param .. '[^}]*}', '(.-)')
  end

  -- If no parameters, just do a direct comparison
  if #param_names == 0 then
    return uri == pattern and {} or nil
  end

  -- Match the URI against our constructed pattern
  local matches = { uri:match('^' .. lua_pattern .. '$') }

  -- If match failed, return nil
  if #matches == 0 or matches[1] == nil then
    return nil
  end

  -- Build the result table mapping parameter names to their values
  local result = {}
  for i, param_name in ipairs(param_names) do
    result[param_name] = matches[i]
  end

  return result
end

--- Prepare the schema for use
---@param tools table<string, CopilotChat.config.tools.Tool>
---@return table<CopilotChat.client.Tool>
function M.parse_tools(tools)
  local tool_names = vim.tbl_keys(tools)
  table.sort(tool_names)
  return vim.tbl_map(function(name)
    local tool = tools[name]
    local schema = tool.schema

    if schema then
      schema = filter_schema(schema)
    end

    return {
      name = name,
      description = tool.description,
      schema = schema,
    }
  end, tool_names)
end

--- Parse context input string into a table based on the schema
---@param input string|table|nil
---@param schema table?
---@return table
function M.parse_input(input, schema)
  if not schema or not schema.properties then
    return {}
  end

  if type(input) == 'table' then
    return input
  end

  local parts = vim.split(input or '', INPUT_SEPARATOR)
  local result = {}
  local prop_names = sorted_propnames(schema)

  -- Map input parts to schema properties in sorted order
  local i = 1
  for _, prop_name in ipairs(prop_names) do
    local prop_schema = schema.properties[prop_name]
    local value = not utils.empty(parts[i]) and parts[i] or nil
    if value == nil and prop_schema.default ~= nil then
      value = prop_schema.default
    end

    result[prop_name] = value
    i = i + 1
    if i > #parts then
      break
    end
  end

  return result
end

--- Get input from the user based on the schema
---@param schema table?
---@param source CopilotChat.source
---@return string?
function M.enter_input(schema, source)
  if not schema or not schema.properties then
    return nil
  end

  local prop_names = sorted_propnames(schema)
  local out = {}

  for _, prop_name in ipairs(prop_names) do
    local cfg = schema.properties[prop_name]
    if not schema.required or vim.tbl_contains(schema.required, prop_name) then
      if cfg.enum then
        local choices = type(cfg.enum) == 'table' and cfg.enum or cfg.enum(source)
        local choice = utils.select(choices, {
          prompt = string.format('Select %s> ', prop_name),
        })

        table.insert(out, choice or '')
      elseif cfg.type == 'boolean' then
        table.insert(out, utils.select({ 'true', 'false' }, {
          prompt = string.format('Select %s> ', prop_name),
        }) or '')
      else
        table.insert(out, utils.input({
          prompt = string.format('Enter %s> ', prop_name),
        }) or '')
      end
    end
  end

  local out = vim.trim(table.concat(out, INPUT_SEPARATOR))
  if out:match('%s+') then
    out = string.format('`%s`', out)
  end
  return out
end

--- Get data for a file
---@param filename string
---@param filetype string?
---@return CopilotChat.tools.ResourceContent?
function M.get_file(filename, filetype)
  if not filetype then
    return nil
  end

  local modified = utils.file_mtime(filename)
  if not modified then
    return nil
  end

  local data = file_cache[filename]
  if not data or data._modified < modified then
    local content = utils.read_file(filename)
    if not content or content == '' then
      return nil
    end
    data = {
      content = content,
      _modified = modified,
    }
    file_cache[filename] = data
  end

  return {
    type = 'resource',
    uri = vim.uri_from_fname(filename),
    data = data.content,
    mimetype = utils.filetype_to_mimetype(filetype),
  }
end

--- Get data for a buffer
---@param bufnr number
---@return CopilotChat.tools.ResourceContent?
function M.get_buffer(bufnr)
  if not utils.buf_valid(bufnr) then
    return nil
  end

  local content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if not content or #content == 0 then
    return nil
  end

  return {
    type = 'resource',
    uri = vim.uri_from_fname(utils.filepath(vim.api.nvim_buf_get_name(bufnr))),
    data = table.concat(content, '\n'),
    mimetype = utils.filetype_to_mimetype(vim.bo[bufnr].filetype),
  }
end

--- Get the content of an URL
---@param url string
---@return CopilotChat.tools.ResourceContent?
function M.get_url(url)
  if not url or url == '' then
    return nil
  end

  local ft = utils.filetype(url)
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
    type = 'resource',
    uri = url,
    data = content,
    mimetype = utils.filetype_to_mimetype(ft),
  }
end

--- Process resources based on the query
---@param prompt string
---@param model string
---@param headless boolean
---@param resources table<CopilotChat.config.functions.ResourceContent>
---@return table<CopilotChat.client.Resource>
function M.process_resources(prompt, model, headless, resources)
  local client_resources = vim.tbl_map(function(resource)
    return {
      name = utils.uri_to_filename(resource.uri),
      type = utils.mimetype_to_filetype(resource.mimetype),
      data = resource.data,
    }
  end, resources)

  -- If we dont need to embed anything, just return directly
  if #client_resources < MULTI_FILE_THRESHOLD then
    return client_resources
  end

  notify.publish(notify.STATUS, 'Preparing embedding outline')

  -- Get the outlines for each resource
  for _, input in ipairs(client_resources) do
    local hash = input.name .. utils.quick_hash(input.data)
    input._hash = hash

    local outline = outline_cache[hash]
    if not outline then
      local outline_text, symbols = get_outline(input.data, input.type)
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
  client_resources = data_ranked_by_symbols(query, client_resources)
  log.debug('Ranked data:', #client_resources)
  for i, item in ipairs(client_resources) do
    log.debug(string.format('%s: %s - %s', i, item.score, item.name))
  end

  -- Prepare embeddings for processing
  local to_process = {}
  local results = {}
  for _, input in ipairs(client_resources) do
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
    type = 'text',
    data = query,
  })

  -- Embed the data and process the results
  for _, input in ipairs(client:embed(to_process, model)) do
    if input._hash then
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
