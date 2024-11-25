local async = require('plenary.async')
local curl = require('plenary.curl')
local log = require('plenary.log')
local utils = require('CopilotChat.utils')
local tiktoken_core = nil
local current_tokenizer = nil
local cache_dir = vim.fn.stdpath('cache')
vim.fn.mkdir(tostring(cache_dir), 'p')

--- Load tiktoken data from cache or download it
---@param tokenizer string The tokenizer to load
---@param on_done fun(path: string) The callback to call when the data is loaded
local function load_tiktoken_data(tokenizer, on_done)
  local tiktoken_url = 'https://openaipublic.blob.core.windows.net/encodings/'
    .. tokenizer
    .. '.tiktoken'
  local cache_path = cache_dir .. '/' .. tiktoken_url:match('.+/(.+)')

  if utils.file_exists(cache_path) then
    on_done(cache_path)
    return
  end

  log.info('Downloading tiktoken data from ' .. tiktoken_url)
  curl.get(tiktoken_url, {
    output = cache_path,
    callback = function()
      on_done(cache_path)
    end,
  })
end

local M = {}

--- Load the tiktoken module
---@param tokenizer string The tokenizer to load
M.load = async.wrap(function(tokenizer, callback)
  if tokenizer == current_tokenizer then
    callback()
    return
  end

  local ok, core = pcall(require, 'tiktoken_core')
  if not ok then
    callback()
    return
  end

  load_tiktoken_data(tokenizer, function(path)
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
    current_tokenizer = tokenizer
    callback()
  end)
end, 2)

--- Encode a prompt
---@param prompt string The prompt to encode
---@return table?
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

--- Count the tokens in a prompt
---@param prompt string The prompt to count
---@return number
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
