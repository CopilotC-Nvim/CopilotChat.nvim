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

function M.check()
  start('CopilotChat.nvim [core]')

  local is_nightly = vim.fn.has('nvim-0.10.0') == 1
  if is_nightly then
    ok('nvim: nightly')
  else
    warn('nvim: stable, some features may not be available')
  end

  start('CopilotChat.nvim [commands]')

  local curl_version = run_command('curl', '--version')
  if curl_version == false then
    error('curl: missing, required for API requests')
  else
    ok('curl: ' .. curl_version)
  end

  local git_version = run_command('git', '--version')
  if git_version == false then
    warn('git: missing, required for git-related commands')
  else
    ok('git: ' .. git_version)
  end

  start('CopilotChat.nvim [dependencies]')

  local has_plenary = lualib_installed('plenary')
  if has_plenary then
    ok('plenary: installed')
  else
    error('plenary: missing, required for running tests. Install plenary.nvim')
  end

  local has_copilot = lualib_installed('copilot')
  local copilot_loaded = vim.g.loaded_copilot == 1
  if has_copilot or copilot_loaded then
    ok('copilot: ' .. (has_copilot and 'copilot.lua' or 'copilot.vim'))
  else
    error(
      'copilot: missing, required for 2 factor authentication. Install copilot.vim or copilot.lua'
    )
  end
  if lualib_installed('tiktoken_core') then
    ok('tiktoken_core: installed')
  else
    error('tiktoken_core: missing, optional for token counting.')
  end
end

return M
