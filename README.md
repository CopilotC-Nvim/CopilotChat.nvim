# Copilot Chat for Neovim

## Authentication

It will prompt you with instructions on your first start. If you already have `Copilot.vim` or `Copilot.lua`, it will work automatically.

## Installation with [lazy.nvim: 💤 A modern plugin manager for Neovim](https://github.com/folke/lazy.nvim)

```lua
--- Send reminder to quickfix list for manual steps
---@param line string
local function send_to_quickfix(line)
  vim.fn.setqflist({ { filename = "CopilotChat.nvim", lnum = 0, text = line } }, "a")
end

return {
  {
    "gptlang/CopilotChat.nvim",
    build = function()
      local copilot_chat_dir = vim.fn.stdpath("data") .. "/lazy/CopilotChat.nvim"
      -- Copy remote plugin to config folder
      vim.fn.system({ "cp", "-r", copilot_chat_dir .. "/rplugin", vim.fn.stdpath("config") })

      -- Notify the user about manual steps
      send_to_quickfix("Please run 'pip install -r " .. copilot_chat_dir .. "/requirements.txt'.")
      send_to_quickfix("Afterwards, open Neovim and run ':UpdateRemotePlugins', then restart Neovim.")
    end,
  },
}
```

After installing, open quickfix and run `pip install -r requirements.txt` with the `CopilotChat.nvim` directory. Afterwards, run `:UpdateRemotePlugins` and restart Neovim.

## Usage

1. Yank some code into the unnamed register (`y`)
2. `:CopilotChat What does this code do?`

## Roadmap

- Translation to pure Lua
- Support `lazy.nvim` installer
- Tokenizer
- Use vector encodings to automatically select code
