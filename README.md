# Copilot Chat for Neovim

[![Documentation](https://img.shields.io/badge/documentation-yes-brightgreen.svg)](https://copilotc-nvim.github.io/CopilotChat.nvim/)
[![pre-commit.ci status](https://results.pre-commit.ci/badge/github/CopilotC-Nvim/CopilotChat.nvim/main.svg)](https://results.pre-commit.ci/latest/github/CopilotC-Nvim/CopilotChat.nvim/main)

<!-- ALL-CONTRIBUTORS-BADGE:START - Do not remove or modify this section -->

[![All Contributors](https://img.shields.io/badge/all_contributors-16-orange.svg?style=flat-square)](#contributors-)

<!-- ALL-CONTRIBUTORS-BADGE:END -->

> [!NOTE]
> Plugin was rewritten to Lua from Python. Please check the [migration guide from version 1 to version 2](/MIGRATION.md) for more information.

## Prerequisites

Ensure you have the following installed:

- **Neovim stable (0.9.5) or nightly**.

## Installation

### Lazy.nvim

```lua
return {
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    branch = "canary",
    dependencies = {
      { "zbirenbaum/copilot.lua" }, -- or github/copilot.vim
      { "nvim-lua/plenary.nvim" }, -- for curl, log wrapper
      { "nvim-telescope/telescope.nvim" }, -- for telescope help actions (optional)
    },
    opts = {
      debug = true, -- Enable debugging
      -- See Configuration section for rest
    },
    -- See Commands section for default commands if you want to lazy load on them
  },
}
```

See @jellydn for [configuration](https://github.com/jellydn/lazy-nvim-ide/blob/main/lua/plugins/extras/copilot-chat-v2.lua)

### Vim-Plug

Similar to the lazy setup, you can use the following configuration:

```vim
call plug#begin()
Plug 'zbirenbaum/copilot.lua'
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim'
Plug 'CopilotC-Nvim/CopilotChat.nvim', { 'branch': 'canary' }
call plug#end()

lua << EOF
require("CopilotChat").setup {
  debug = true, -- Enable debugging
  -- See Configuration section for rest
}
EOF
```

### Manual

1. Put the files in the right place

```
mkdir -p ~/.config/nvim/pack/copilotchat/start
cd ~/.config/nvim/pack/copilotchat/start

git clone https://github.com/zbirenbaum/copilot.lua
git clone https://github.com/nvim-lua/plenary.nvim
git clone https://github.com/nvim-telescope/telescope.nvim

git clone -b canary https://github.com/CopilotC-Nvim/CopilotChat.nvim
```

2. Add to you configuration

```lua
require("CopilotChat").setup {
  debug = true, -- Enable debugging
  -- See Configuration section for rest
}
```

See @deathbeam for [configuration](https://github.com/deathbeam/dotfiles/blob/master/nvim/.config/nvim/lua/config/copilot.lua#L14)

## Usage

### API

```lua
local chat = require("CopilotChat")

-- Open chat window
chat.open()

-- Open chat window with custom options
chat.open({
  window = {
    layout = 'float',
    title = 'My Title',
  },
})

-- Close chat window
chat.close()

-- Toggle chat window
chat.toggle()

-- Toggle chat window with custom options
chat.toggle({
  window = {
    layout = 'float',
    title = 'My Title',
  },
})

-- Reset chat window
chat.reset()

-- Ask a question
chat.ask("Explain how it works.")

-- Ask a question with custom options
chat.ask("Explain how it works.", {
  selection = require("CopilotChat.select").buffer,
})

-- Get all available prompts (can be used for integrations like fzf/telescope)
local prompts = chat.prompts()
```

### Commands

- `:CopilotChat <input>?` - Open chat window with optional input
- `:CopilotChatOpen` - Open chat window
- `:CopilotChatClose` - Close chat window
- `:CopilotChatToggle` - Toggle chat window
- `:CopilotChatReset` - Reset chat window
- `:CopilotChatDebugInfo` - Show debug information

#### Commands coming from default prompts

- `:CopilotChatExplain` - Explain how it works
- `:CopilotChatTests` - Briefly explain how selected code works then generate unit tests
- `:CopilotChatFixDiagnostic` - Please assist with the following diagnostic issue in file
- `:CopilotChatCommit` - Write commit message for the change with commitizen convention
- `:CopilotChatCommitStaged` - Write commit message for the change with commitizen convention

### Configuration

For further reference, you can view @jellydn's [configuration](https://github.com/jellydn/lazy-nvim-ide/blob/main/lua/plugins/extras/copilot-chat-v2.lua).

#### Default configuration

Also see [here](/lua/CopilotChat/config.lua):

```lua
{
  system_prompt = prompts.COPILOT_INSTRUCTIONS, -- System prompt to use
  model = 'gpt-4', -- GPT model to use
  temperature = 0.1, -- GPT temperature
  debug = false, -- Enable debug logging
  show_user_selection = true, -- Shows user selection in chat
  show_system_prompt = false, -- Shows system prompt in chat
  show_folds = true, -- Shows folds for sections in chat
  clear_chat_on_new_prompt = false, -- Clears chat on every new prompt
  auto_follow_cursor = true, -- Auto-follow cursor in chat
  name = 'CopilotChat', -- Name to use in chat
  separator = '---', -- Separator to use in chat
  -- default prompts
  prompts = {
    Explain = {
      prompt = 'Explain how it works.',
    },
    Tests = {
      prompt = 'Briefly explain how selected code works then generate unit tests.',
    },
    FixDiagnostic = {
      prompt = 'Please assist with the following diagnostic issue in file:',
      selection = select.diagnostics,
    },
    Commit = {
      prompt = 'Write commit message for the change with commitizen convention. Make sure the title has maximum 50 characters and message is wrapped at 72 characters. Wrap the whole message in code block with language gitcommit.',
      selection = select.gitdiff,
    },
    CommitStaged = {
      prompt = 'Write commit message for the change with commitizen convention. Make sure the title has maximum 50 characters and message is wrapped at 72 characters. Wrap the whole message in code block with language gitcommit.',
      selection = function(bufnr)
        return select.gitdiff(bufnr, true)
      end,
    },
  },
  -- default selection (visual or line)
  selection = function(bufnr)
    return select.visual(bufnr) or select.line(bufnr)
  end,
  -- default window options
  window = {
    layout = 'vertical', -- 'vertical', 'horizontal', 'float'
    -- Options below only apply to floating windows
    relative = 'editor', -- 'editor', 'win', 'cursor', 'mouse'
    border = 'single', -- 'none', single', 'double', 'rounded', 'solid', 'shadow'
    width = 0.8, -- fractional width of parent
    height = 0.6, -- fractional height of parent
    row = nil, -- row position of the window, default is centered
    col = nil, -- column position of the window, default is centered
    title = 'Copilot Chat', -- title of chat window
    footer = nil, -- footer of chat window
    zindex = 1, -- determines if window is on top or below other floating windows
  },
  -- default mappings
  mappings = {
    close = 'q',
    reset = '<C-l>',
    complete_after_slash = '<Tab>',
    submit_prompt = '<CR>',
    accept_diff = '<C-y>',
    show_diff = '<C-d>',
  },
}
```

#### Defining a prompt with command and keymap

This will define prompt that you can reference with `/MyCustomPrompt` in chat, call with `:CopilotChatMyCustomPrompt` or use the keymap `<leader>ccmc`.
It will use visual selection as default selection. If you are using `lazy.nvim` and are already lazy loading based on `Commands` make sure to include the prompt
commands and keymaps in `cmd` and `keys` respectively.

```lua
{
  prompts = {
    MyCustomPrompt = {
      prompt = 'Explain how it works.',
      mapping = '<leader>ccmc',
      description = 'My custom prompt description',
      selection = require('CopilotChat.select').visual,
    },
  },
}
```

#### Referencing system or user prompts

You can reference system or user prompts in your configuration or in chat with `/PROMPT_NAME` slash notation.
For collection of default `COPILOT_` (system) and `USER_` (user) prompts, see [here](/lua/CopilotChat/prompts.lua).

```lua
{
  prompts = {
    MyCustomPrompt = {
      prompt = '/COPILOT_EXPLAIN Explain how it works.',
    },
    MyCustomPrompt2 = {
      prompt = '/MyCustomPrompt Include some additional context.',
    },
  },
}
```

#### Custom system prompts

You can define custom system prompts by using `system_prompt` property when passing config around.

```lua
{
  system_prompt = 'Your name is Github Copilot and you are a AI assistant for developers.',
  prompts = {
    MyCustomPromptWithCustomSystemPrompt = {
      system_prompt = 'Your name is Johny Microsoft and you are not an AI assistant for developers.',
      prompt = 'Explain how it works.',
    },
  },
}
```

## Tips

### Quick chat with your buffer

To chat with Copilot using the entire content of the buffer, you can add the following configuration to your keymap:

```lua
-- lazy.nvim keys

  -- Quick chat with Copilot
  {
    "<leader>ccq",
    function()
      local input = vim.fn.input("Quick Chat: ")
      if input ~= "" then
        require("CopilotChat").ask(input, { selection = require("CopilotChat.select").buffer })
      end
    end,
    desc = "CopilotChat - Quick chat",
  }
```

[![Chat with buffer](https://i.gyazo.com/9b8cbf1d78a19f326282a6520bc9aab0.gif)](https://gyazo.com/9b8cbf1d78a19f326282a6520bc9aab0)

### Inline Chat

Change the window layout to `float` and position relative to cursor to make the window look like inline chat.
This will allow you to chat with Copilot without opening a new window.

```lua
-- lazy.nvim opts

  {
    window = {
      layout = 'float',
      relative = 'cursor',
      width = 1,
      height = 0.4,
      row = 1
    }
  }
```

![inline-chat](https://github.com/CopilotC-Nvim/CopilotChat.nvim/assets/5115805/608e3c9b-8569-408d-a5d1-2213325fc93c)

## Roadmap (Wishlist)

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
