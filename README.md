# Copilot Chat for Neovim
<!-- ALL-CONTRIBUTORS-BADGE:START - Do not remove or modify this section -->
[![All Contributors](https://img.shields.io/badge/all_contributors-1-orange.svg?style=flat-square)](#contributors-)
<!-- ALL-CONTRIBUTORS-BADGE:END -->

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

### Configuration

You have the ability to tailor this plugin to your specific needs using the configuration options outlined below:

```lua
{
  debug = false, -- Enable or disable debug mode
  prompts = { -- Set dynamic prompts for CopilotChat commands
    Explain = 'Explain how it works.',
    Tests = 'Briefly explain how the selected code works, then generate unit tests.',
  }
}
```

You have the capability to expand the prompts to create more versatile commands:

```lua
return {
    "jellydn/CopilotChat.nvim",
    opts = {
      mode = "split",
      prompts = {
        Explain = "Explain how it works.",
        Review = "Review the following code and provide concise suggestions.",
        Tests = "Briefly explain how the selected code works, then generate unit tests.",
        Refactor = "Refactor the code to improve clarity and readability.",
      },
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
      { "<leader>ccr", "<cmd>CopilotChatReview<cr>", desc = "CopilotChat - Review code" },
      { "<leader>ccR", "<cmd>CopilotChatRefactor<cr>", desc = "CopilotChat - Refactor code" },
    }
}
```

For further reference, you can view my [configuration](https://github.com/jellydn/lazy-nvim-ide/blob/main/lua/plugins/extras/copilot-chat.lua).

### Chat with Github Copilot

1. Copy some code into the unnamed register using the `y` command.
2. Run the command `:CopilotChat` followed by your question. For example, `:CopilotChat What does this code do?`

![Chat Demo](https://i.gyazo.com/10fbd1543380d15551791c1a6dcbcd46.gif)

### Code Explanation

1. Copy some code into the unnamed register using the `y` command.
2. Run the command `:CopilotChatExplain`.

![Explain Code Demo](https://i.gyazo.com/e5031f402536a1a9d6c82b2c38d469e3.gif)

### Generate Tests

1. Copy some code into the unnamed register using the `y` command.
2. Run the command `:CopilotChatTests`.

[![Generate tests](https://i.gyazo.com/f285467d4b8d8f8fd36aa777305312ae.gif)](https://gyazo.com/f285467d4b8d8f8fd36aa777305312ae)

## Roadmap

- Translation to pure Lua
- Tokenizer
- Use vector encodings to automatically select code
- Sub commands - See [issue #5](https://github.com/gptlang/CopilotChat.nvim/issues/5)

## Contributors ✨

Thanks goes to these wonderful people ([emoji key](https://allcontributors.org/docs/en/emoji-key)):

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/gptlang"><img src="https://avatars.githubusercontent.com/u/121417512?v=4?s=100" width="100px;" alt="gptlang"/><br /><sub><b>gptlang</b></sub></a><br /><a href="https://github.com/jellydn/CopilotChat.nvim/commits?author=gptlang" title="Code">💻</a> <a href="https://github.com/jellydn/CopilotChat.nvim/commits?author=gptlang" title="Documentation">📖</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind welcome!