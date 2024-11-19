local M = {}

--- Create class
---@param fn function The class constructor
---@param parent table? The parent class
---@return table
function M.class(fn, parent)
  local out = {}
  out.__index = out

  local mt = {
    __call = function(cls, ...)
      return cls.new(...)
    end,
  }

  if parent then
    mt.__index = parent
  end

  setmetatable(out, mt)

  function out.new(...)
    local self = setmetatable({}, out)
    fn(self, ...)
    return self
  end

  return out
end

--- Check if the current version of neovim is stable
---@return boolean
function M.is_stable()
  return vim.fn.has('nvim-0.10.0') == 0
end

--- Writes text to a temporary file and returns path
---@param text string The text to write
---@return string?
function M.temp_file(text)
  local temp_file = os.tmpname()
  local f = io.open(temp_file, 'w+')
  if f == nil then
    error('Could not open file: ' .. temp_file)
  end
  f:write(text)
  f:close()
  return temp_file
end

--- Finds the path to the user's config directory
---@return string?
function M.config_path()
  local config = vim.fn.expand('$XDG_CONFIG_HOME')
  if config and vim.fn.isdirectory(config) > 0 then
    return config
  end
  if vim.fn.has('win32') > 0 then
    config = vim.fn.expand('$LOCALAPPDATA')
    if not config or vim.fn.isdirectory(config) == 0 then
      config = vim.fn.expand('$HOME/AppData/Local')
    end
  else
    config = vim.fn.expand('$HOME/.config')
  end
  if config and vim.fn.isdirectory(config) > 0 then
    return config
  end
end

--- Check if a table is equal to another table
---@param a table The first table
---@param b table The second table
---@return boolean
function M.table_equals(a, b)
  if type(a) ~= type(b) then
    return false
  end
  if type(a) ~= 'table' then
    return a == b
  end
  for k, v in pairs(a) do
    if not M.table_equals(v, b[k]) then
      return false
    end
  end
  for k, v in pairs(b) do
    if not M.table_equals(v, a[k]) then
      return false
    end
  end
  return true
end

--- Blend a color with the neovim background
function M.blend_color_with_neovim_bg(color_name, blend)
  local color_int = vim.api.nvim_get_hl(0, { name = color_name }).fg
  local bg_int = vim.api.nvim_get_hl(0, { name = 'Normal' }).bg

  if not color_int or not bg_int then
    return
  end

  local color = { (color_int / 65536) % 256, (color_int / 256) % 256, color_int % 256 }
  local bg = { (bg_int / 65536) % 256, (bg_int / 256) % 256, bg_int % 256 }
  local r = math.floor((color[1] * blend + bg[1] * (100 - blend)) / 100)
  local g = math.floor((color[2] * blend + bg[2] * (100 - blend)) / 100)
  local b = math.floor((color[3] * blend + bg[3] * (100 - blend)) / 100)
  return string.format('#%02x%02x%02x', r, g, b)
end

--- Find lines between two patterns
---@param lines table<string> The lines to search
---@param current_line number The current line
---@param start_pattern string The start pattern
---@param end_pattern string? The end pattern
---@param allow_end_of_file boolean? Allow end of file as end pattern
function M.find_lines(lines, current_line, start_pattern, end_pattern, allow_end_of_file)
  if not end_pattern then
    end_pattern = start_pattern
  end

  local line_count = #lines
  local separator_line_start = 1
  local separator_line_finish = line_count
  local found_one = false

  -- Find starting separator line
  for i = current_line, 1, -1 do
    local line = lines[i]

    if line and string.match(line, start_pattern) then
      separator_line_start = i + 1

      for x = separator_line_start, line_count do
        local next_line = lines[x]
        if next_line and string.match(next_line, end_pattern) then
          separator_line_finish = x - 1
          found_one = true
          break
        end
        if allow_end_of_file and x == line_count then
          separator_line_finish = x
          found_one = true
          break
        end
      end

      if found_one then
        break
      end
    end
  end

  if not found_one then
    return {}, 1, 1
  end

  -- Extract everything between the last and next separator or end of file
  local result = {}
  for i = separator_line_start, separator_line_finish do
    table.insert(result, lines[i])
  end

  return result, separator_line_start, separator_line_finish
end

--- Return to normal mode
function M.return_to_normal_mode()
  local mode = vim.fn.mode():lower()
  if mode:find('v') then
    vim.cmd([[execute "normal! \<Esc>"]])
  elseif mode:find('i') then
    vim.cmd('stopinsert')
  end
end

--- Mark a function as deprecated
function M.deprecate(old, new)
  vim.deprecate(old, new, '3.0.X', 'CopilotChat.nvim', false)
end

--- Debounce a function
function M.debounce(fn, delay)
  if M.timer then
    M.timer:stop()
  end
  M.timer = vim.defer_fn(fn, delay)
end

--- Check if a buffer is valid
---@param bufnr number? The buffer number
---@return boolean
function M.buf_valid(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) or false
end

return M
