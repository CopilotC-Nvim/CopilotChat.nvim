local M = {}

local start = vim.health.start or vim.health.report_start
local warn = vim.health.warn or vim.health.report_warn
local ok = vim.health.ok or vim.health.report_ok

--- Run a command on an executable and handle potential errors
---@param executable string
---@param command string
local function run_command_on_executable(executable, command)
  local is_present = vim.fn.executable(executable)
  if is_present == 0 then
    return false
  else
    local success, result = pcall(vim.fn.system, { executable, command })
    if success then
      return result
    else
      return false
    end
  end
end

--- Run a python command and handle potential errors
---@param command string
local function run_python_command(command)
  local python3_host_prog = vim.g['python3_host_prog']
  return run_command_on_executable(python3_host_prog or 'python3', command)
end

-- Add health check for python3 and pynvim
function M.check()
  start('CopilotChat.nvim health check')
  local python_version = run_python_command('--version')

  if python_version == false then
    warn('Python 3 is required')
    return
  end

  local major, minor = string.match(python_version, 'Python (%d+)%.(%d+)')
  if not (major and minor and tonumber(major) >= 3 and tonumber(minor) >= 10) then
    warn('Python version 3.10 or higher is required')
  else
    ok('Python version ' .. major .. '.' .. minor .. ' is supported')
  end

  -- Create a temporary Python script to check the pynvim version
  local temp_file = os.tmpname() .. '.py'
  local file = io.open(temp_file, 'w')
  if file == nil then
    warn('Failed to create temporary Python script')
    return
  end

  file:write('import pynvim; v = pynvim.VERSION; print("{0}.{1}.{2}".format(v.major, v.minor, v.patch))')
  file:close()

  -- Run the temporary Python script and capture the output
  local pynvim_version = run_python_command(temp_file)

  -- Trim the output
  if pynvim_version ~= false then
    pynvim_version = string.gsub(pynvim_version, '^%s*(.-)%s*$', '%1')
  end

  -- Delete the temporary Python script
  os.remove(temp_file)

  if vim.version.lt(pynvim_version, "0.4.3") then
    warn('pynvim version ' .. pynvim_version .. ' is not supported')
  else
    ok('pynvim version ' .. pynvim_version .. ' is supported')
  end
end

return M
