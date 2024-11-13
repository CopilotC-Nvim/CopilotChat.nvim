local curl = require('plenary.curl')
local log = require('plenary.log')
local tiktoken_core = nil
local current_tokenizer = nil

local function get_cache_path(fname)
  vim.fn.mkdir(tostring(vim.fn.stdpath('cache')), 'p')
  return vim.fn.stdpath('cache') .. '/' .. fname
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
local function load_tiktoken_data(done, tokenizer)
  local tiktoken_url = 'https://openaipublic.blob.core.windows.net/encodings/'
    .. tokenizer
    .. '.tiktoken'
  local cache_path = get_cache_path(tiktoken_url:match('.+/(.+)'))

  if file_exists(cache_path) then
    done(cache_path)
    return
  end

  log.info('Downloading tiktoken data from ' .. tiktoken_url)
  curl.get(tiktoken_url, {
    output = cache_path,
    callback = function()
      done(cache_path)
    end,
  })
end

local M = {}

function M.load(tokenizer, on_done)
  if tokenizer == current_tokenizer then
    on_done()
    return
  end

  local ok, core = pcall(require, 'tiktoken_core')
  if not ok then
    on_done()
    return
  end

  vim.schedule(function()
    load_tiktoken_data(
      vim.schedule_wrap(function(path)
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
        on_done()
      end),
      tokenizer
    )
  end)
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
