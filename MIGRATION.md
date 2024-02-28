# Migration guide after Copilot Chat rewrite to Lua

## Prerequisities

Ensure you have the following plugins installed:

- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [copilot.vim](https://github.com/github/copilot.vim) (recommended) or [copilot.lua](https://github.com/zbirenbaum/copilot.lua)

You will also need [curl](https://curl.se/). Neovim should ship with copy of curl by default so most likely you are fine.

After getting copilot.vim or copilot.lua make sure to run `:Copilot setup` or `:Copilot auth` to retrieve your token if its not cached already.
Also make sure to run `:UpdateRemotePlugins` to cleanup the old python commands.

## Configuration changes

Removed or changed params that you pass to `setup`:

- `show_help` was removed (the help is now always shown as virtual text, and not intrusive)
- `hide_system_prompt` was removed (it is part of `disable_extra_info`)
- `proxy` does not work at the moment (waiting for change in plenary.nvim), if you are behind corporate proxy you can look at something like [vpn-slice](https://github.com/dlenski/vpn-slice)
- `language` was removed and is now part of `selection` as `selection.filetype`

## Command changes

- `CopilotChatBuffer` was removed (now exists as `select.buffer` selector for `selection`)
- `CopilotChatInPlace` was removed (parts of it were merged to default chat interface, and floating window now exists as `float` config for `window.layout`)
- `CopilotChat` now functions as `CopilotChatVisual`, the unnamed register selection now exists as `select.unnamed` selector

## How to restore legacy behaviour

```lua
local chat = require('CopilotChat')
local select = require('CopilotChat.select')

chat.setup {
    selection = select.unnamed, -- Restore the behaviour for CopilotChat to use unnamed register by default
}

-- Restore CopilotChatVisual
vim.api.nvim_create_user_command('CopilotChatVisual', function(args)
    M.ask(args.args, { selection = select.visual })
end, { nargs = '*', range = true })

-- Restore CopilotChatInPlace (sort of)
vim.api.nvim_create_user_command('CopilotChatInPlace', function(args)
    M.ask(args.args, { selection = select.visual, window = { layout = 'float' } })
end, { nargs = '*', range = true })

-- Restore CopilotChatBuffer
vim.api.nvim_create_user_command('CopilotChatBuffer', function(args)
    M.ask(args.args, { selection = select.buffer })
end, { nargs = '*', range = true })
```
