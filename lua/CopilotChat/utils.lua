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

return M
