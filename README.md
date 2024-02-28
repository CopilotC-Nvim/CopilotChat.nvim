# Copilot Chat for Neovim

![Prerequisite](https://img.shields.io/badge/python-%3E%3D3.10-blue.svg)
[![Documentation](https://img.shields.io/badge/documentation-yes-brightgreen.svg)](https://copilotc-nvim.github.io/CopilotChat.nvim/)
[![pre-commit.ci status](https://results.pre-commit.ci/badge/github/CopilotC-Nvim/CopilotChat.nvim/main.svg)](https://results.pre-commit.ci/latest/github/CopilotC-Nvim/CopilotChat.nvim/main)

<!-- ALL-CONTRIBUTORS-BADGE:START - Do not remove or modify this section -->

[![All Contributors](https://img.shields.io/badge/all_contributors-16-orange.svg?style=flat-square)](#contributors-)

<!-- ALL-CONTRIBUTORS-BADGE:END -->

> [!NOTE]
> Plugin was rewritten to Lua from Python. Please check the [migration guide](/MIGRATION.md) for more information.

## Prerequisites

Ensure you have the following installed:

- **Neovim stable (0.9.5) or nightly**.

## Authentication

It will prompt you with instructions on your first start. If you already have `Copilot.vim` or `Copilot.lua`, it will work automatically.

## Installation

### Lazy.nvim

```lua
return {
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    branch = "canary",
    opts = {
      debug = true, -- Enable or disable debug mode, the log file will be in ~/.local/state/nvim/CopilotChat.nvim.log
    },
    config = function(_, opts)
      local chat = require("CopilotChat")
      local select = require("CopilotChat.select")

      chat.setup(opts)

      -- Restore CopilotChatVisual
      vim.api.nvim_create_user_command("CopilotChatVisual", function(args)
        chat.ask(args.args, { selection = select.visual })
      end, { nargs = "*", range = true })

      -- Restore CopilotChatInPlace (sort of)
      vim.api.nvim_create_user_command("CopilotChatInPlace", function(args)
        chat.ask(args.args, { selection = select.visual, window = { layout = "float" } })
      end, { nargs = "*", range = true })

      -- Restore CopilotChatBuffer
      vim.api.nvim_create_user_command("CopilotChatBuffer", function(args)
        chat.ask(args.args, { selection = select.buffer })
      end, { nargs = "*", range = true })
    end,
    event = "VeryLazy",
    keys = {
      { "<leader>ccb", "<cmd>CopilotChatBuffer ", desc = "CopilotChat - Chat with current buffer" },
      { "<leader>cce", "<cmd>CopilotChatExplain<cr>", desc = "CopilotChat - Explain code" },
      { "<leader>cct", "<cmd>CopilotChatTests<cr>", desc = "CopilotChat - Generate tests" },
      {
        "<leader>ccv",
        ":CopilotChatVisual ",
        mode = "x",
        desc = "CopilotChat - Open in vertical split",
      },
      {
        "<leader>ccx",
        ":CopilotChatInPlace<cr>",
        mode = "x",
        desc = "CopilotChat - Run in-place code",
      },
      {
        "<leader>ccf",
        "<cmd>CopilotChatFixDiagnostic<cr>", -- Get a fix for the diagnostic message under the cursor.
        desc = "CopilotChat - Fix diagnostic",
      },
    },
  },
}
```

### Vim-Plug

Similar to the lazy setup, you can use the following configuration:

```lua
Plug 'CopilotC-Nvim/CopilotChat.nvim'
call plug#end()

local copilot_chat = require("CopilotChat")
copilot_chat.setup({
  debug = true,
  prompts = {
    Explain = "Explain how it works by Japanese language.",
    Review = "Review the following code and provide concise suggestions.",
    Tests = "Briefly explain how the selected code works, then generate unit tests.",
    Refactor = "Refactor the code to improve clarity and readability.",
  },
})

nnoremap <leader>cce <cmd>CopilotChatExplain<cr>
nnoremap <leader>cct <cmd>CopilotChatTests<cr>
```

Credit to @treyhunner and @nekowasabi for the [configuration](https://github.com/CopilotC-Nvim/CopilotChat.nvim/discussions/46).

### Manual

1. Put the files in the right place

```
$ git clone https://github.com/CopilotC-Nvim/CopilotChat.nvim
$ cd CopilotChat.nvim
$ cp -r --backup=nil rplugin ~/.config/nvim/
```

2. Add to you configuration

```lua
local chat = require('CopilotChat')
local select = require('CopilotChat.select')

chat.setup({
    prompts = {
        FixDiagnostic = {
            prompt = 'Please assist with the following diagnostic issue in file:',
            selection = select.diagnostics,
            mapping = '<leader>ar',
        },
        Explain = {
            prompt = '/COPILOT_EXPLAIN /USER_EXPLAIN',
            mapping = '<leader>ae',
        },
        Tests = {
            prompt = '/COPILOT_TESTS /USER_TESTS',
            mapping = '<leader>at',
        },
        Documentation = {
            prompt = '/USER_DOCS',
            mapping = '<leader>ad',
        },
        Fix = {
            prompt = '/COPILOT_DEVELOPER /USER_FIX',
            mapping = '<leader>af',
        },
        Optimize = {
            prompt = '/COPILOT_DEVELOPER Optimize the selected code to improve performance and readablilty.',
            mapping = '<leader>ao',
        },
        Simplify = {
            prompt = '/COPILOT_DEVELOPER Simplify the selected code and improve readablilty',
            mapping = '<leader>as',
        },
    },
})

vim.keymap.set({ 'n', 'v' }, '<leader>aa', chat.toggle, { desc = 'CopilotChat.nvim Toggle' })
vim.keymap.set({ 'n', 'v' }, '<leader>ax', chat.reset, { desc = 'CopilotChat.nvim Reset' })
```

Credit to @deathbeam for the [configuration](https://github.com/deathbeam/dotfiles/blob/master/nvim/.config/nvim/lua/config/copilot.lua#L14)

## Usage

### Configuration

You have the ability to tailor this plugin to your specific needs using the configuration options outlined below:

```lua
{
  debug = false, -- Enable or disable debug mode
  clear_chat_on_new_prompt = 'no', -- If yes then clear chat history on new prompt
  prompts = { -- Set dynamic prompts for CopilotChat commands
    Explain = 'Explain how it works.',
    Tests = 'Briefly explain how the selected code works, then generate unit tests.',
  }
}
```

You have the capability to expand the prompts to create more versatile commands:

```lua
return {
    "CopilotC-Nvim/CopilotChat.nvim",
    opts = {
      debug = true,
      prompts = {
        Explain = "Explain how it works.",
        Review = "Review the following code and provide concise suggestions.",
        Tests = "Briefly explain how the selected code works, then generate unit tests.",
        Refactor = "Refactor the code to improve clarity and readability.",
      },
    },
    event = "VeryLazy",
    keys = {
      { "<leader>cce", "<cmd>CopilotChatExplain<cr>", desc = "CopilotChat - Explain code" },
      { "<leader>cct", "<cmd>CopilotChatTests<cr>", desc = "CopilotChat - Generate tests" },
      { "<leader>ccr", "<cmd>CopilotChatReview<cr>", desc = "CopilotChat - Review code" },
      { "<leader>ccR", "<cmd>CopilotChatRefactor<cr>", desc = "CopilotChat - Refactor code" },
    }
}
```

For further reference, you can view @jellydn's [configuration](https://github.com/jellydn/lazy-nvim-ide/blob/main/lua/plugins/extras/copilot-chat.lua).

## Tips

### Quick chat with your buffer

To chat with Copilot using the entire content of the buffer, you can add the following configuration to your keymap:

```lua
  -- Quick chat with Copilot
  {
    "<leader>ccq",
    function()
      local input = vim.fn.input("Quick Chat: ")
      if input ~= "" then
        vim.cmd("CopilotChatBuffer " .. input)
      end
    end,
    desc = "CopilotChat - Quick chat",
  }
```

[![Chat with buffer](https://i.gyazo.com/9b8cbf1d78a19f326282a6520bc9aab0.gif)](https://gyazo.com/9b8cbf1d78a19f326282a6520bc9aab0)

## Inline Chat

Change the window layout to `float` to enable inline chat. This will allow you to chat with Copilot without opening a new window.

```lua
chat.setup({
    window = {
        layout = 'float',
        relative = 'cursor',
        width = 1,
        height = 0.4,
        row = 1
    }
})
```

![inline-chat](https://github.com/CopilotC-Nvim/CopilotChat.nvim/assets/5115805/608e3c9b-8569-408d-a5d1-2213325fc93c)

### Integration with `telescope.nvim`

To integrate CopilotChat with Telescope, you can add the following configuration to your keymap:

```lua
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    event = "VeryLazy",
    dependencies = {
      { "nvim-telescope/telescope.nvim" }, -- Use telescope for help actions
      { "nvim-lua/plenary.nvim" },
    },
    keys = {
     -- Show help actions with telescope
      {
        "<leader>cch",
        function()
          require("CopilotChat.code_actions").show_help_actions()
        end,
        desc = "CopilotChat - Help actions",
      },
      -- Show prompts actions with telescope
      {
        "<leader>ccp",
        function()
          require("CopilotChat.code_actions").show_prompt_actions()
        end,
        desc = "CopilotChat - Help actions",
      },
      {
        "<leader>ccp",
        ":lua require('CopilotChat.code_actions').show_prompt_actions(true)<CR>",
        mode = "x",
        desc = "CopilotChat - Prompt actions",
      },
    }
  }
```

1. Select help actions base the diagnostic message under the cursor.
   [![Help action with Copilot Chat](https://i.gyazo.com/146dc35368592ba9f5de047ddc4728ad.gif)](https://gyazo.com/146dc35368592ba9f5de047ddc4728ad)

2. Select action base on user prompts.
   [![Select action base on user prompts](https://i.gyazo.com/a9c41e6398591c2f1d1d872fd58a2c63.gif)](https://gyazo.com/a9c41e6398591c2f1d1d872fd58a2c63)

### Debugging with `:messages` and `:CopilotChatDebugInfo`

If you encounter any issues, you can run the command `:messages` to inspect the log. You can also run the command `:CopilotChatDebugInfo` to inspect the debug information.

[![Debug Info](https://i.gyazo.com/bf00e700bcee1b77bcbf7b516b552521.gif)](https://gyazo.com/bf00e700bcee1b77bcbf7b516b552521)

### Roadmap (Wishlist)

- Use vector encodings to automatically select code
- Treesitter integration for function definitions
- General QOL improvements

## Development

### Installing Pre-commit Tool

For development, you can use the provided Makefile command to install the pre-commit tool:

```bash
make install-pre-commit
```

This will install the pre-commit tool and the pre-commit hooks.

## Contributors ✨

Thanks goes to these wonderful people ([emoji key](https://allcontributors.org/docs/en/emoji-key)):

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/gptlang"><img src="https://avatars.githubusercontent.com/u/121417512?v=4?s=100" width="100px;" alt="gptlang"/><br /><sub><b>gptlang</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=gptlang" title="Code">💻</a> <a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=gptlang" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://productsway.com/"><img src="https://avatars.githubusercontent.com/u/870029?v=4?s=100" width="100px;" alt="Dung Duc Huynh (Kaka)"/><br /><sub><b>Dung Duc Huynh (Kaka)</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=jellydn" title="Code">💻</a> <a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=jellydn" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://qoobes.dev"><img src="https://avatars.githubusercontent.com/u/58834655?v=4?s=100" width="100px;" alt="Ahmed Haracic"/><br /><sub><b>Ahmed Haracic</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=qoobes" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://youtube.com/@ziontee113"><img src="https://avatars.githubusercontent.com/u/102876811?v=4?s=100" width="100px;" alt="Trí Thiện Nguyễn"/><br /><sub><b>Trí Thiện Nguyễn</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=ziontee113" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/Cassius0924"><img src="https://avatars.githubusercontent.com/u/62874592?v=4?s=100" width="100px;" alt="He Zhizhou"/><br /><sub><b>He Zhizhou</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=Cassius0924" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://www.linkedin.com/in/guruprakashrajakkannu/"><img src="https://avatars.githubusercontent.com/u/9963717?v=4?s=100" width="100px;" alt="Guruprakash Rajakkannu"/><br /><sub><b>Guruprakash Rajakkannu</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=rguruprakash" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/kristofka"><img src="https://avatars.githubusercontent.com/u/140354?v=4?s=100" width="100px;" alt="kristofka"/><br /><sub><b>kristofka</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=kristofka" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/PostCyberPunk"><img src="https://avatars.githubusercontent.com/u/134976996?v=4?s=100" width="100px;" alt="PostCyberPunk"/><br /><sub><b>PostCyberPunk</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=PostCyberPunk" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/ktns"><img src="https://avatars.githubusercontent.com/u/1302759?v=4?s=100" width="100px;" alt="Katsuhiko Nishimra"/><br /><sub><b>Katsuhiko Nishimra</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=ktns" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/errnoh"><img src="https://avatars.githubusercontent.com/u/373946?v=4?s=100" width="100px;" alt="Erno Hopearuoho"/><br /><sub><b>Erno Hopearuoho</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=errnoh" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/shaungarwood"><img src="https://avatars.githubusercontent.com/u/4156525?v=4?s=100" width="100px;" alt="Shaun Garwood"/><br /><sub><b>Shaun Garwood</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=shaungarwood" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/neutrinoA4"><img src="https://avatars.githubusercontent.com/u/122616073?v=4?s=100" width="100px;" alt="neutrinoA4"/><br /><sub><b>neutrinoA4</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=neutrinoA4" title="Code">💻</a> <a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=neutrinoA4" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/banjocat"><img src="https://avatars.githubusercontent.com/u/3247309?v=4?s=100" width="100px;" alt="Jack Muratore"/><br /><sub><b>Jack Muratore</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=banjocat" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/AdrielVelazquez"><img src="https://avatars.githubusercontent.com/u/3443378?v=4?s=100" width="100px;" alt="Adriel Velazquez"/><br /><sub><b>Adriel Velazquez</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=AdrielVelazquez" title="Code">💻</a> <a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=AdrielVelazquez" title="Documentation">📖</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/deathbeam"><img src="https://avatars.githubusercontent.com/u/5115805?v=4?s=100" width="100px;" alt="Tomas Slusny"/><br /><sub><b>Tomas Slusny</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=deathbeam" title="Code">💻</a> <a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=deathbeam" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://nisalvd.netlify.com/"><img src="https://avatars.githubusercontent.com/u/30633436?v=4?s=100" width="100px;" alt="Nisal"/><br /><sub><b>Nisal</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=nisalVD" title="Documentation">📖</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind are welcome!

### Stargazers over time

[![Stargazers over time](https://starchart.cc/CopilotC-Nvim/CopilotChat.nvim.svg)](https://starchart.cc/CopilotC-Nvim/CopilotChat.nvim)
