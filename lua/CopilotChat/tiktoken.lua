local notify = require('CopilotChat.notify')
local utils = require('CopilotChat.utils')
local class = utils.class

--- Get the library extension based on the operating system
--- @return string
local function get_lib_extension()
  if jit.os:lower() == 'mac' or jit.os:lower() == 'osx' then
    return '.dylib'
  end
  if jit.os:lower() == 'windows' then
    return '.dll'
  end
  return '.so'
end

--- Load tiktoken data from cache or download it
---@param tokenizer string The tokenizer to load
---@async
local function load_tiktoken_data(tokenizer)
  local tiktoken_url = 'https://openaipublic.blob.core.windows.net/encodings/' .. tokenizer .. '.tiktoken'

  local cache_dir = vim.fn.stdpath('cache')
  vim.fn.mkdir(tostring(cache_dir), 'p')
  local cache_path = cache_dir .. '/' .. tiktoken_url:match('.+/(.+)')

  if vim.uv.fs_stat(cache_path) then
    return cache_path
  end

  notify.publish(notify.STATUS, 'Downloading tiktoken data from ' .. tiktoken_url)

  utils.curl_get(tiktoken_url, {
    output = cache_path,
  })

  return cache_path
end

---@class CopilotChat.tiktoken.Tiktoken : Class
---@field private tiktoken_core table?
---@field private tokenizer string?
local Tiktoken = class(function(self)
  package.cpath = package.cpath
    .. ';'
    .. debug.getinfo(1).source:match('@?(.*/)')
    .. '../../build/?'
    .. get_lib_extension()

  local tiktoken_ok, tiktoken_core = pcall(require, 'tiktoken_core')
  self.tiktoken_core = tiktoken_ok and tiktoken_core or nil
  self.tokenizer = nil
end)

--- Load the tiktoken module
---@param tokenizer string The tokenizer to load
---@async
function Tiktoken:load(tokenizer)
  if not self.tiktoken_core then
    return
  end

  if tokenizer == self.tokenizer then
    return
  end

  utils.schedule_main()
  local path = load_tiktoken_data(tokenizer)
  local special_tokens = {}
  special_tokens['<|endoftext|>'] = 100257
  special_tokens['<|fim_prefix|>'] = 100258
  special_tokens['<|fim_middle|>'] = 100259
  special_tokens['<|fim_suffix|>'] = 100260
  special_tokens['<|endofprompt|>'] = 100276
  local pat_str =
    "(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\\r\\n\\p{L}\\p{N}]?\\p{L}+|\\p{N}{1,3}| ?[^\\s\\p{L}\\p{N}]+[\\r\\n]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+"

  utils.schedule_main()
  self.tiktoken_core.new(path, special_tokens, pat_str)
  self.tokenizer = tokenizer
end

--- Encode a prompt
---@param prompt string The prompt to encode
---@return table?
function Tiktoken:encode(prompt)
  if not self.tiktoken_core then
    return nil
  end
  if not prompt or prompt == '' or type(prompt) ~= 'string' then
    return nil
  end

  local ok, result = pcall(self.tiktoken_core.encode, prompt)
  if not ok then
    return nil
  end

  return result
end

--- Count the tokens in a prompt
---@param prompt string The prompt to count
---@return number
function Tiktoken:count(prompt)
  if not self.tiktoken_core then
    return math.ceil(#prompt * 0.5) -- Fallback to 1/2 character count
  end

  local tokens = self:encode(prompt)
  if not tokens then
    return math.ceil(#prompt * 0.5) -- Fallback to 1/2 character count
  end
  return #tokens
end

return Tiktoken()
