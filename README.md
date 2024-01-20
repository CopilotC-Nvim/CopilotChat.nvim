# Copilot Chat for Neovim

## Authentication

It will prompt you with instructions on your first start. If you already have `Copilot.vim` or `Copilot.lua`, it will work automatically.

## Installation

### Lazy.nvim

1. `pip install python-dotenv requests pynvim==0.5.0 prompt-toolkit`
2. Put it in your lazy setup

```lua
return {
  {
    "jellydn/CopilotChat.nvim",
    opts = {
      mode = "split", -- newbuffer or split  , default: newbuffer
    },
    build = function()
      vim.defer_fn(function()
        vim.cmd("UpdateRemotePlugins")
        vim.notify("CopilotChat - Updated remote plugins. Please restart Neovim.")
      end, 3000)
    end,
    event = "VeryLazy",
    keys = {
      { "<leader>cce", "<cmd>CopilotChatExplain<cr>", desc = "CopilotChat - Explain code" },
      { "<leader>cct", "<cmd>CopilotChatTests<cr>", desc = "CopilotChat - Generate tests" },
    },
  },
}
```

3. Run `:UpdateRemotePlugins`
4. Restart `neovim`

### Manual

1. Put the files in the right place

```
$ git clone https://github.com/gptlang/CopilotChat.nvim
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

### Chat

To chat with Copilot, follow these steps:

1. Copy some code into the unnamed register using the `y` command.
2. Run the command `:CopilotChat` followed by your question. For example, `:CopilotChat What does this code do?`

![Chat Demo](https://i.gyazo.com/10fbd1543380d15551791c1a6dcbcd46.gif)

### Code Explanation

To get an explanation of your code, follow these steps:

1. Copy some code into the unnamed register using the `y` command.
2. Run the command `:CopilotChatExplain`.

![Explain Code Demo](https://i.gyazo.com/e5031f402536a1a9d6c82b2c38d469e3.gif)

### Generate Tests

To generate tests for your code, follow these steps:

1. Copy some code into the unnamed register using the `y` command.
2. Run the command `:CopilotChatTests`.

[![Generate tests](https://i.gyazo.com/f285467d4b8d8f8fd36aa777305312ae.gif)](https://gyazo.com/f285467d4b8d8f8fd36aa777305312ae)

## Roadmap

- Translation to pure Lua
- Tokenizer
- Use vector encodings to automatically select code
- Sub commands - See [issue #5](https://github.com/gptlang/CopilotChat.nvim/issues/5)
