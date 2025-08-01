local M = {}

local start = vim.health.start or vim.health.report_start
local error = vim.health.error or vim.health.report_error
local warn = vim.health.warn or vim.health.report_warn
local ok = vim.health.ok or vim.health.report_ok

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
  start('CopilotChat.nvim [core]')

  local vim_version = vim.trim(vim.api.nvim_exec2('version', { output = true }).output)
  if vim.fn.has('nvim-0.10.0') == 1 then
    ok('nvim: ' .. vim_version)
  else
    error('nvim: unsupported, please upgrade to 0.10.0 or later. See "https://neovim.io/".')
  end

  local setup_called = require('CopilotChat').config ~= nil
  if setup_called then
    ok('setup: called')
  else
    error('setup: not called, required for plugin to work. See `:h CopilotChat-installation`.')
  end

  local testfile = os.tmpname()
  local f = io.open(testfile, 'w')
  local writable = false
  if f then
    f:write('test')
    f:close()
    writable = true
  end
  if writable then
    ok('temp dir: writable (' .. testfile .. ')')
    os.remove(testfile)
  else
    local stat = vim.loop.fs_stat(vim.fn.fnamemodify(testfile, ':h'))
    local perms = stat and string.format('%o', stat.mode % 512) or 'unknown'
    error('temp dir: not writable. Permissions: ' .. perms .. ' (dir: ' .. vim.fn.fnamemodify(testfile, ':h') .. ')')
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

  local rg_version = run_command('rg', '--version')
  if rg_version == false then
    warn('rg: missing, optional for improved search performance. See "https://github.com/BurntSushi/ripgrep".')
  else
    ok('rg: ' .. rg_version)
  end

  local lynx_version = run_command('lynx', '-version')
  if lynx_version == false then
    warn('lynx: missing, optional for improved fetching of url contents. See "https://lynx.invisible-island.net/".')
  else
    ok('lynx: ' .. lynx_version)
  end

  local gh_version = run_command('gh', '--version')
  if gh_version == false then
    warn('gh: missing, optional for improved GitHub authorization. See "https://cli.github.com/".')
  else
    ok('gh: ' .. gh_version)
  end

  start('CopilotChat.nvim [dependencies]')

  if lualib_installed('plenary') then
    ok('plenary: installed')
  else
    error('plenary: missing, required for http requests and async jobs. Install "nvim-lua/plenary.nvim" plugin.')
  end

  local has_copilot = lualib_installed('copilot')
  local copilot_loaded = vim.g.loaded_copilot == 1
  if has_copilot or copilot_loaded then
    ok('copilot: ' .. (has_copilot and 'copilot.lua' or 'copilot.vim'))
  else
    warn(
      'copilot: missing, optional for improved Copilot authorization. Install "github/copilot.vim" or "zbirenbaum/copilot.lua" plugins.'
    )
  end

  local select_source = debug.getinfo(vim.ui.select).source
  if select_source:match('vim/ui%.lua$') then
    warn(
      'vim.ui.select: using default implementation, which may not provide the best user experience. See `:h CopilotChat-integration-with-pickers`.'
    )
  else
    ok('vim.ui.select: overridden by `' .. select_source .. '`')
  end

  if lualib_installed('tiktoken_core') then
    ok('tiktoken_core: installed')
  else
    warn('tiktoken_core: missing, optional for accurate token counting. See README for installation instructions.')
  end

  if treesitter_parser_available('markdown') then
    ok('treesitter[markdown]: installed')
  else
    warn(
      'treesitter[markdown]: missing, optional for better chat highlighting. Install `nvim-treesitter/nvim-treesitter` plugin and run `:TSInstall markdown`.'
    )
  end

  if treesitter_parser_available('diff') then
    ok('treesitter[diff]: installed')
  else
    warn(
      'treesitter[diff]: missing, optional for better diff highlighting. Install `nvim-treesitter/nvim-treesitter` plugin and run `:TSInstall diff`.'
    )
  end
end

return M
