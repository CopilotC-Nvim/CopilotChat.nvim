local curl = require('plenary.curl')
local class = require('CopilotChat.utils').class
local tiktoken_core = nil
if pcall(require, 'tiktoken_core') then
  tiktoken_core = require('tiktoken_core')
end

---Get the path of the cache directory or nil
---@return nil|string
local function get_cache_path()
  local cache_path = vim.fn.stdpath('cache') .. '/cl100k_base.tiktoken'
  if cache_path then
    return cache_path
  else
    return nil
  end
end

---Save data to cache
---@param data string[]
local function save_cached_file(data)
  local cache_path = get_cache_path()
  if not cache_path then
    return nil
  end
  -- Write data to c100k.tiktoken file in cache
  vim.fn.writefile(data, cache_path)
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

---Get tiktoken data from cache or download it
---@return boolean
local function get_tiktoken_data()
  if file_exists(get_cache_path()) then
    return true
  else
    local response =
      curl.get('https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken')
    if response.status == 200 then
      save_cached_file(vim.split(response.body, '\n'))
      -- Return the response body split by newline
      return true
    else
      return false
    end
  end
end

local Encoder = class(function()
  if not tiktoken_core then
    return
  end
  if not get_tiktoken_data() then
    error('Failed to get tiktoken data')
  end
  local special_tokens = {}
  special_tokens['<|endoftext|>'] = 100257
  special_tokens['<|fim_prefix|>'] = 100258
  special_tokens['<|fim_middle|>'] = 100259
  special_tokens['<|fim_suffix|>'] = 100260
  special_tokens['<|endofprompt|>'] = 100276
  local pat_str =
    "(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\\r\\n\\p{L}\\p{N}]?\\p{L}+|\\p{N}{1,3}| ?[^\\s\\p{L}\\p{N}]+[\\r\\n]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+"
  tiktoken_core.new(get_cache_path(), special_tokens, pat_str)
end)

function Encoder:encode(prompt)
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

function Encoder:count(prompt)
  local tokens = self:encode(prompt)
  if not tokens then
    return 0
  end
  return #tokens
end

return Encoder
