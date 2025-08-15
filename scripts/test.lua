vim.opt.runtimepath:append(vim.fn.getcwd())

for name, url in pairs({
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/echasnovski/mini.test',
}) do
  local install_path = vim.fn.fnamemodify('.dependencies/' .. name, ':p')
  if vim.fn.isdirectory(install_path) == 0 then
    vim.fn.system({ 'git', 'clone', '--depth=1', url, install_path })
  end
  vim.opt.runtimepath:append(install_path)
end

require('mini.test').setup()
