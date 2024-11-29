local M = {}

local start = vim.health.start or vim.health.report_start
local error = vim.health.error or vim.health.report_error
local warn = vim.health.warn or vim.health.report_warn
local ok = vim.health.ok or vim.health.report_ok
local info = vim.health.info or vim.health.report_info

--- Run a command and handle potential errors
---@param executable string
---@param command string
local function run_command(executable, command)
  local is_present = vim.fn.executable(executable)
  if is_present == 0 then
    return false
  else
    local success, result = pcall(vim.fn.system, { executable, command })
    if success then
      return vim.trim(result)
    else
      return false
    end
  end
end

--- Check if a Lua library is installed
---@param lib_name string
---@return boolean
local function lualib_installed(lib_name)
  local res, _ = pcall(require, lib_name)
  return res
end

--- Check if a treesitter parser is available
---@param ft string
---@return boolean
local function treesitter_parser_available(ft)
  local res, parser = pcall(vim.treesitter.get_parser, 0, ft)
  return res and parser ~= nil
end

function M.check()
  start('CopilotChat.nvim')
  info('If you are facing any issues, also see :CopilotChatDebugInfo for more information.')

  start('CopilotChat.nvim [core]')

  local vim_version = vim.trim(vim.api.nvim_command_output('version'))
  local dev_number = tonumber(vim_version:match('dev%-(%d+)'))

  if dev_number then
    local to_check = vim.fn.has('nvim-0.11.0') and 0 or 2500
    if dev_number >= to_check then
      ok('nvim: ' .. vim_version)
    else
      error(
        'nvim: outdated, please upgrade to a up to date nightly version. See "https://github.com/neovim/neovim".'
      )
    end
  elseif vim.fn.has('nvim-0.9.5') == 1 then
    ok('nvim: ' .. vim_version)
  else
    error('nvim: unsupported, please upgrade to 0.9.5 or later. See "https://neovim.io/".')
  end

  start('CopilotChat.nvim [commands]')

  local curl_version = run_command('curl', '--version')
  if curl_version == false then
    error('curl: missing, required for API requests. See "https://curl.se/".')
  else
    ok('curl: ' .. curl_version)
  end

  local git_version = run_command('git', '--version')
  if git_version == false then
    warn('git: missing, required for git-related commands. See "https://git-scm.com/".')
  else
    ok('git: ' .. git_version)
  end

  local lynx_version = run_command('lynx', '-version')
  if lynx_version == false then
    warn(
      'lynx: missing, optional for improved fetching of url contents. See "https://lynx.invisible-island.net/".'
    )
  else
    ok('lynx: ' .. lynx_version)
  end

  start('CopilotChat.nvim [dependencies]')

  if lualib_installed('plenary') then
    ok('plenary: installed')
  else
    error(
      'plenary: missing, required for http requests and async jobs. Install "nvim-lua/plenary.nvim" plugin.'
    )
  end

  local has_copilot = lualib_installed('copilot')
  local copilot_loaded = vim.g.loaded_copilot == 1
  if has_copilot or copilot_loaded then
    ok('copilot: ' .. (has_copilot and 'copilot.lua' or 'copilot.vim'))
  else
    error(
      'copilot: missing, required for 2 factor authentication. Install "github/copilot.vim" or "zbirenbaum/copilot.lua" plugins.'
    )
  end

  if lualib_installed('tiktoken_core') then
    ok('tiktoken_core: installed')
  else
    warn(
      'tiktoken_core: missing, optional for accurate token counting. See README for installation instructions.'
    )
  end

  if treesitter_parser_available('markdown') then
    ok('treesitter[markdown]: installed')
  else
    warn(
      'treesitter[markdown]: missing, optional for better chat highlighting. Install "nvim-treesitter/nvim-treesitter" plugin and run ":TSInstall markdown".'
    )
  end

  if treesitter_parser_available('diff') then
    ok('treesitter[diff]: installed')
  else
    warn(
      'treesitter[diff]: missing, optional for better diff highlighting. Install "nvim-treesitter/nvim-treesitter" plugin and run ":TSInstall diff".'
    )
  end
end

return M
