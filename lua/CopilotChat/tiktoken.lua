local curl = require('plenary.curl')
local tiktoken_core = nil

---Get the path of the cache directory
---@return string
local function get_cache_path()
  return vim.fn.stdpath('cache') .. '/cl100k_base.tiktoken'
end

local function file_exists(name)
  local f = io.open(name, 'r')
  if f ~= nil then
    io.close(f)
    return true
  else
    return false
  end
end

--- Load tiktoken data from cache or download it
local function load_tiktoken_data(done)
  local async
  async = vim.loop.new_async(function()
    local cache_path = get_cache_path()
    if not file_exists(cache_path) then
      curl.get('https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken', {
        output = cache_path,
      })
    end

    done(cache_path)
    async:close()
  end)
  async:send()
end

local M = {}

function M.setup()
  local ok, core = pcall(require, 'tiktoken_core')
  if not ok then
    return
  end

  load_tiktoken_data(function(path)
    local special_tokens = {}
    special_tokens['<|endoftext|>'] = 100257
    special_tokens['<|fim_prefix|>'] = 100258
    special_tokens['<|fim_middle|>'] = 100259
    special_tokens['<|fim_suffix|>'] = 100260
    special_tokens['<|endofprompt|>'] = 100276
    local pat_str =
      "(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\\r\\n\\p{L}\\p{N}]?\\p{L}+|\\p{N}{1,3}| ?[^\\s\\p{L}\\p{N}]+[\\r\\n]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+"
    core.new(path, special_tokens, pat_str)
    tiktoken_core = core
  end)
end

function M.available()
  return tiktoken_core ~= nil
end

function M.encode(prompt)
  if not tiktoken_core then
    return nil
  end
  if not prompt or prompt == '' then
    return nil
  end
  -- Check if prompt is a string
  if type(prompt) ~= 'string' then
    error('Prompt must be a string')
  end
  return tiktoken_core.encode(prompt)
end

function M.count(prompt)
  if not tiktoken_core then
    return math.ceil(#prompt * 0.5) -- Fallback to 1/2 character count
  end

  local tokens = M.encode(prompt)
  if not tokens then
    return 0
  end
  return #tokens
end

return M
