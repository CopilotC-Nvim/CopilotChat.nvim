if vim.g.loaded_copilot_chat then
  return
end

local min_version = '0.10.0'
if vim.fn.has('nvim-' .. min_version) ~= 1 then
  vim.notify_once(
    ('CopilotChat.nvim requires Neovim >= %s'):format(min_version),
    vim.log.levels.ERROR
  )
  return
end

local chat = require('CopilotChat')

-- Setup highlights
vim.api.nvim_set_hl(0, 'CopilotChatStatus', { link = 'DiagnosticHint', default = true })
vim.api.nvim_set_hl(0, 'CopilotChatHelp', { link = 'DiagnosticInfo', default = true })
vim.api.nvim_set_hl(0, 'CopilotChatKeyword', { link = 'Keyword', default = true })
vim.api.nvim_set_hl(0, 'CopilotChatInput', { link = 'Special', default = true })
vim.api.nvim_set_hl(0, 'CopilotChatSelection', { link = 'Visual', default = true })
vim.api.nvim_set_hl(0, 'CopilotChatHeader', { link = '@markup.heading.2.markdown', default = true })
vim.api.nvim_set_hl(
  0,
  'CopilotChatSeparator',
  { link = '@punctuation.special.markdown', default = true }
)

-- Setup commands
vim.api.nvim_create_user_command('CopilotChat', function(args)
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
  chat.select_prompt()
end, { force = true, range = true })
vim.api.nvim_create_user_command('CopilotChatModels', function()
  chat.select_model()
end, { force = true })
vim.api.nvim_create_user_command('CopilotChatAgents', function()
  chat.select_agent()
end, { force = true })
vim.api.nvim_create_user_command('CopilotChatOpen', function()
  chat.open()
end, { force = true })
vim.api.nvim_create_user_command('CopilotChatClose', function()
  chat.close()
end, { force = true })
vim.api.nvim_create_user_command('CopilotChatToggle', function()
  chat.toggle()
end, { force = true })
vim.api.nvim_create_user_command('CopilotChatStop', function()
  chat.stop()
end, { force = true })
vim.api.nvim_create_user_command('CopilotChatReset', function()
  chat.reset()
end, { force = true })

local function complete_load()
  local options = vim.tbl_map(function(file)
    return vim.fn.fnamemodify(file, ':t:r')
  end, vim.fn.glob(chat.config.history_path .. '/*', true, true))

  if not vim.tbl_contains(options, 'default') then
    table.insert(options, 1, 'default')
  end

  return options
end
vim.api.nvim_create_user_command('CopilotChatSave', function(args)
  chat.save(args.args)
end, { nargs = '*', force = true, complete = complete_load })
vim.api.nvim_create_user_command('CopilotChatLoad', function(args)
  chat.load(args.args)
end, { nargs = '*', force = true, complete = complete_load })

-- Store the current directory to window when directory changes
-- I dont think there is a better way to do this that functions
-- with "rooter" plugins, LSP and stuff as vim.fn.getcwd() when
-- i pass window number inside doesnt work
vim.api.nvim_create_autocmd({ 'VimEnter', 'WinEnter', 'DirChanged' }, {
  group = vim.api.nvim_create_augroup('CopilotChat', {}),
  callback = function()
    vim.w.cchat_cwd = vim.fn.getcwd()
  end,
})

-- Setup treesitter
vim.treesitter.language.register('markdown', 'copilot-chat')

vim.g.loaded_copilot_chat = true
