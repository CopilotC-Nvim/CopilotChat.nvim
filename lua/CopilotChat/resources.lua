local async = require('plenary.async')
local utils = require('CopilotChat.utils')
local file_cache = {}
local url_cache = {}

local M = {}

--- Get data for a file
---@param filename string
---@return string?, string?
function M.get_file(filename)
  local filetype = utils.filetype(filename)
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

  return data.content, utils.filetype_to_mimetype(filetype)
end

--- Get data for a buffer
---@param bufnr number
---@return string?, string?
function M.get_buffer(bufnr)
  if not utils.buf_valid(bufnr) then
    return nil
  end

  local content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if not content or #content == 0 then
    return nil
  end

  return table.concat(content, '\n'), utils.filetype_to_mimetype(vim.bo[bufnr].filetype)
end

--- Get the content of an URL
---@param url string
---@return string?, string?
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

  return content, utils.filetype_to_mimetype(ft)
end

return M
