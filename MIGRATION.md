# Migration guide after Copilot Chat rewrite to Lua

## Prerequisites

Ensure you have the following plugins installed:

- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [copilot.vim](https://github.com/github/copilot.vim) (recommended) or [copilot.lua](https://github.com/zbirenbaum/copilot.lua)

You will also need [curl](https://curl.se/). Neovim should ship with copy of curl by default so most likely you are fine.

After getting copilot.vim or copilot.lua make sure to run `:Copilot setup` or `:Copilot auth` to retrieve your token if its not cached already.
Also make sure to run `:UpdateRemotePlugins` to cleanup the old python commands.

## Configuration changes

Removed or changed params that you pass to `setup`:

- `disable_extra_info` was removed. Now you can use keybinding to show current selection in chat on demand.
- `hide_system_prompt` was removed. Now you can use keybinding to show current system prompt in chat on demand.
- `language` was removed and is now part of `selection` as `selection.filetype`

## Command changes

- `CopilotChatBuffer` was removed (now exists as `select.buffer` selector for `selection`)
- `CopilotChatInPlace` was removed (parts of it were merged to default chat interface, and floating window now exists as `float` config for `window.layout`)
- `CopilotChat` now functions as `CopilotChatVisual`, the unnamed register selection now exists as `select.unnamed` selector
- `CopilotChatVsplitToggle` was renamed to `CopilotChatToggle`

## API changes

- `CopilotChat.code_actions.show_help_actions` was reworked. Now you can use:

```lua
local actions = require("CopilotChat.actions")
require("CopilotChat.integrations.telescope").pick(actions.help_actions())
```

- `CopilotChat.code_actions.show_prompt_actions` was reworked. Now you can use:

```lua
local actions = require("CopilotChat.actions")
local select = require("CopilotChat.select")
require("CopilotChat.integrations.telescope").pick(actions.prompt_actions({
    selection = select.visual,
}))
```

## How to restore legacy behaviour

```lua
local chat = require('CopilotChat')
local select = require('CopilotChat.select')

chat.setup {
    -- Restore the behaviour for CopilotChat to use unnamed register by default
    selection = select.unnamed,
    -- Restore the format with ## headers as prefixes,
    question_header = '## User ',
    answer_header = '## Copilot ',
    error_header = '## Error ',
}

-- Restore CopilotChatVisual
vim.api.nvim_create_user_command('CopilotChatVisual', function(args)
    chat.ask(args.args, { selection = select.visual })
end, { nargs = '*', range = true })

-- Restore CopilotChatInPlace (sort of)
vim.api.nvim_create_user_command('CopilotChatInPlace', function(args)
    chat.ask(args.args, { selection = select.visual, window = { layout = 'float' } })
end, { nargs = '*', range = true })

-- Restore CopilotChatBuffer
vim.api.nvim_create_user_command('CopilotChatBuffer', function(args)
    chat.ask(args.args, { selection = select.buffer })
end, { nargs = '*', range = true })

-- Restore CopilotChatVsplitToggle
vim.api.nvim_create_user_command('CopilotChatVsplitToggle', chat.toggle, {})
```

For further reference, you can view @jellydn's [configuration](https://github.com/jellydn/lazy-nvim-ide/blob/main/lua/plugins/extras/copilot-chat-v2.lua).

## TODO

- [x] For proxy support, this is needed: https://github.com/nvim-lua/plenary.nvim/pull/559
- [x] Delete rest of the python code? Or finish rewriting in place then delete - All InPlace features are done, per poll on discord delete the python code
- [x] Check for curl availability with health check
- [x] Add folds logic from python, maybe? Not sure if this is even needed
- [x] Finish rewriting the authentication request if needed or just keep relying on copilot.vim/lua - Relies on copilot.vim/lua
- [x] Properly get token file path, atm it only supports Linux (easy fix)
- [x] Update README and stuff
- [x] Add token count from tiktoken support to extra_info
- [x] Add test and fix failed test in CI
