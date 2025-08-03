if vim.g.loaded_copilot_chat then
  return
end

local min_version = '0.10.0'
if vim.fn.has('nvim-' .. min_version) ~= 1 then
  vim.notify_once(('CopilotChat.nvim requires Neovim >= %s'):format(min_version), vim.log.levels.ERROR)
  return
end

local group = vim.api.nvim_create_augroup('CopilotChat', {})

-- Setup highlights
local function setup_highlights()
  vim.api.nvim_set_hl(0, 'CopilotChatHeader', { link = '@markup.heading.2.markdown', default = true })
  vim.api.nvim_set_hl(0, 'CopilotChatSeparator', { link = '@punctuation.special.markdown', default = true })
  vim.api.nvim_set_hl(0, 'CopilotChatStatus', { link = 'DiagnosticHint', default = true })
  vim.api.nvim_set_hl(0, 'CopilotChatHelp', { link = 'DiagnosticInfo', default = true })
  vim.api.nvim_set_hl(0, 'CopilotChatResource', { link = 'Constant', default = true })
  vim.api.nvim_set_hl(0, 'CopilotChatTool', { link = 'Function', default = true })
  vim.api.nvim_set_hl(0, 'CopilotChatPrompt', { link = 'Statement', default = true })
  vim.api.nvim_set_hl(0, 'CopilotChatModel', { link = 'Type', default = true })
  vim.api.nvim_set_hl(0, 'CopilotChatUri', { link = 'Underlined', default = true })
  vim.api.nvim_set_hl(0, 'CopilotChatSelection', { link = 'Visual', default = true })

  vim.api.nvim_set_hl(0, 'CopilotChatAnnotation', { link = 'ColorColumn', default = true })
  local fg = vim.api.nvim_get_hl(0, { name = 'CopilotChatStatus', link = false }).fg
  local bg = vim.api.nvim_get_hl(0, { name = 'CopilotChatAnnotation', link = false }).bg
  vim.api.nvim_set_hl(0, 'CopilotChatAnnotationHeader', { fg = fg, bg = bg })
end
vim.api.nvim_create_autocmd('ColorScheme', {
  group = group,
  callback = function()
    setup_highlights()
  end,
})
setup_highlights()

-- Setup commands
vim.api.nvim_create_user_command('CopilotChat', function(args)
  local chat = require('CopilotChat')
  local input = args.args
  if input and vim.trim(input) ~= '' then
    chat.ask(input)
  else
    chat.open()
  end
end, {
  nargs = '*',
  force = true,
  range = true,
})
vim.api.nvim_create_user_command('CopilotChatPrompts', function()
  local chat = require('CopilotChat')
  chat.select_prompt()
end, { force = true, range = true })
vim.api.nvim_create_user_command('CopilotChatModels', function()
  local chat = require('CopilotChat')
  chat.select_model()
end, { force = true })
vim.api.nvim_create_user_command('CopilotChatOpen', function()
  local chat = require('CopilotChat')
  chat.open()
end, { force = true })
vim.api.nvim_create_user_command('CopilotChatClose', function()
  local chat = require('CopilotChat')
  chat.close()
end, { force = true })
vim.api.nvim_create_user_command('CopilotChatToggle', function()
  local chat = require('CopilotChat')
  chat.toggle()
end, { force = true })
vim.api.nvim_create_user_command('CopilotChatStop', function()
  local chat = require('CopilotChat')
  chat.stop()
end, { force = true })
vim.api.nvim_create_user_command('CopilotChatReset', function()
  local chat = require('CopilotChat')
  chat.reset()
end, { force = true })

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'copilot-chat',
  group = group,
  callback = vim.schedule_wrap(function()
    vim.cmd.syntax('match CopilotChatResource "#\\S\\+"')
    vim.cmd.syntax('match CopilotChatTool "@\\S\\+"')
    vim.cmd.syntax('match CopilotChatPrompt "/\\S\\+"')
    vim.cmd.syntax('match CopilotChatModel "\\$\\S\\+"')
    vim.cmd.syntax('match CopilotChatUri "##\\S\\+"')
  end),
})

local function complete_load()
  local chat = require('CopilotChat')
  local options = vim.tbl_map(function(file)
    return vim.fn.fnamemodify(file, ':t:r')
  end, vim.fn.glob(chat.config.history_path .. '/*', true, true))

  if not vim.tbl_contains(options, 'default') then
    table.insert(options, 1, 'default')
  end

  return options
end
vim.api.nvim_create_user_command('CopilotChatSave', function(args)
  local chat = require('CopilotChat')
  chat.save(args.args)
end, { nargs = '*', force = true, complete = complete_load })
vim.api.nvim_create_user_command('CopilotChatLoad', function(args)
  local chat = require('CopilotChat')
  chat.load(args.args)
end, { nargs = '*', force = true, complete = complete_load })

-- Store the current directory to window when directory changes
-- I dont think there is a better way to do this that functions
-- with "rooter" plugins, LSP and stuff as vim.fn.getcwd() when
-- i pass window number inside doesnt work
vim.api.nvim_create_autocmd({ 'VimEnter', 'WinEnter', 'DirChanged' }, {
  group = group,
  callback = function()
    vim.w.cchat_cwd = vim.fn.getcwd()
  end,
})

-- Setup treesitter
vim.treesitter.language.register('markdown', 'copilot-chat')

vim.g.loaded_copilot_chat = true
