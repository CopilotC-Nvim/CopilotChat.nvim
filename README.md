# Copilot Chat for Neovim

## Authentication

It will prompt you with instructions on your first start. If you already have `Copilot.vim` or `Copilot.lua`, it will work automatically.

## Installation

### Lazy.nvim

1. `pip install python-dotenv requests pynvim prompt-toolkit`
2. Put it in your lazy setup

```lua
require('lazy').setup({
  {
    "jellydn/CopilotChat.nvim",
    opts = {},
    build = function()
      vim.cmd("UpdateRemotePlugins")
    end,
    event = "VeryLazy",
    keys = {
      { "<leader>cce", "<cmd>CChatExplain<cr>", desc = "CopilotChat - Explain code" },
      { "<leader>cct", "<cmd>CChatTests<cr>", desc = "CopilotChat - Generate tests" },
    },
  },
    ...
})
```

3. Run `:UpdateRemotePlugins`
4. Restart `neovim`

### Manual

1. Put the files in the right place

```
$ git clone https://github.com/jellydn/CopilotChat.nvim
$ cd CopilotChat.nvim
$ cp -r --backup=nil rplugin ~/.config/nvim/
```

2. Install dependencies

```
$ pip install -r requirements.txt
```

3. Open up Neovim and run `:UpdateRemotePlugins`
4. Restart Neovim

## Usage

1. Yank some code into the unnamed register (`y`)
2. `:CChat What does this code do?`

[![Demo](https://i.gyazo.com/10fbd1543380d15551791c1a6dcbcd46.gif)](https://gyazo.com/10fbd1543380d15551791c1a6dcbcd46)

## Roadmap

- Translation to pure Lua
- Tokenizer
- Use vector encodings to automatically select code
- Sub commands - See [issue #5](https://github.com/gptlang/CopilotChat.nvim/issues/5)
