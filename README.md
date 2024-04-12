# Copilot Chat for Neovim

[![Documentation](https://img.shields.io/badge/documentation-yes-brightgreen.svg)](https://copilotc-nvim.github.io/CopilotChat.nvim/)
[![pre-commit.ci](https://results.pre-commit.ci/badge/github/CopilotC-Nvim/CopilotChat.nvim/main.svg)](https://results.pre-commit.ci/latest/github/CopilotC-Nvim/CopilotChat.nvim/main)
[![Discord](https://img.shields.io/discord/1200633211236122665.svg)](https://discord.gg/vy6hJsTWaZ)

<!-- ALL-CONTRIBUTORS-BADGE:START - Do not remove or modify this section -->

[![All Contributors](https://img.shields.io/badge/all_contributors-25-orange.svg?style=flat-square)](#contributors-)

<!-- ALL-CONTRIBUTORS-BADGE:END -->

> [!NOTE]
> Plugin was rewritten to Lua from Python. Please check the [migration guide from version 1 to version 2](/MIGRATION.md) for more information.

## Prerequisites

Ensure you have the following installed:

- **Neovim stable (0.9.5) or nightly**.

Optional:

- tiktoken_core: `sudo luarocks install --lua-version 5.1 tiktoken_core`. Alternatively, download a pre-built binary from [lua-tiktoken releases](https://github.com/gptlang/lua-tiktoken/releases)
- You can check your Lua PATH in Neovim by doing `:lua print(package.cpath)`. Save the binary as `tiktoken_core.so` in any of the given paths.

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

git clone -b canary https://github.com/CopilotC-Nvim/CopilotChat.nvim
```

2. Add to your configuration (e.g. `~/.config/nvim/init.lua`)

```lua
require("CopilotChat").setup {
  debug = true, -- Enable debugging
  -- See Configuration section for rest
}
```

See @deathbeam for [configuration](https://github.com/deathbeam/dotfiles/blob/master/nvim/.config/nvim/lua/config/copilot.lua#L14)

## Usage

### Commands

- `:CopilotChat <input>?` - Open chat window with optional input
- `:CopilotChatOpen` - Open chat window
- `:CopilotChatClose` - Close chat window
- `:CopilotChatToggle` - Toggle chat window
- `:CopilotChatReset` - Reset chat window
- `:CopilotChatSave <name>?` - Save chat history to file
- `:CopilotChatLoad <name>?` - Load chat history from file
- `:CopilotChatDebugInfo` - Show debug information

#### Commands coming from default prompts

- `:CopilotChatExplain` - Write an explanation for the active selection as paragraphs of text
- `:CopilotChatReview` - Review the selected code
- `:CopilotChatFix` - There is a problem in this code. Rewrite the code to show it with the bug fixed
- `:CopilotChatOptimize` - Optimize the selected code to improve performance and readablilty
- `:CopilotChatDocs` - Please add documentation comment for the selection
- `:CopilotChatTests` - Please generate tests for my code
- `:CopilotChatFixDiagnostic` - Please assist with the following diagnostic issue in file
- `:CopilotChatCommit` - Write commit message for the change with commitizen convention
- `:CopilotChatCommitStaged` - Write commit message for the change with commitizen convention

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

-- Ask a question and do something with the response
chat.ask("Show me something interesting", {
  callback = function(response)
    print("Response:", response)
  end,
})

-- Get all available prompts (can be used for integrations like fzf/telescope)
local prompts = chat.prompts()

-- Get last copilot response (also can be used for integrations and custom keymaps)
local response = chat.response()

-- Pick a prompt using vim.ui.select
local actions = require("CopilotChat.actions")

-- Pick help actions
actions.pick(actions.help_actions())

-- Pick prompt actions
actions.pick(actions.prompt_actions({
    selection = require("CopilotChat.select").visual,
}))
```

## Configuration

### Default configuration

Also see [here](/lua/CopilotChat/config.lua):

```lua
{
  debug = false, -- Enable debug logging
  proxy = nil, -- [protocol://]host[:port] Use this proxy
  allow_insecure = false, -- Allow insecure server connections

  system_prompt = prompts.COPILOT_INSTRUCTIONS, -- System prompt to use
  model = 'gpt-4', -- GPT model to use, 'gpt-3.5-turbo' or 'gpt-4'
  temperature = 0.1, -- GPT temperature

  question_header = '## User ', -- Header to use for user questions
  answer_header = '## Copilot ', -- Header to use for AI answers
  error_header = '## Error ', -- Header to use for errors
  separator = '---', -- Separator to use in chat

  show_folds = true, -- Shows folds for sections in chat
  show_help = true, -- Shows help message as virtual lines when waiting for user input
  auto_follow_cursor = true, -- Auto-follow cursor in chat
  auto_insert_mode = false, -- Automatically enter insert mode when opening window and if auto follow cursor is enabled on new prompt
  clear_chat_on_new_prompt = false, -- Clears chat on every new prompt

  context = nil, -- Default context to use, 'buffers', 'buffer' or none (can be specified manually in prompt via @).
  history_path = vim.fn.stdpath('data') .. '/copilotchat_history', -- Default path to stored history
  callback = nil, -- Callback to use when ask response is received

  -- default selection (visual or line)
  selection = function(source)
    return select.visual(source) or select.line(source)
  end,

  -- default prompts
  prompts = {
    Explain = {
      prompt = '/COPILOT_EXPLAIN Write an explanation for the active selection as paragraphs of text.',
    },
    Review = {
      prompt = '/COPILOT_REVIEW Review the selected code.',
      callback = function(response, source)
        -- see config.lua for implementation
      end,
    },
    Fix = {
      prompt = '/COPILOT_GENERATE There is a problem in this code. Rewrite the code to show it with the bug fixed.',
    },
    Optimize = {
      prompt = '/COPILOT_GENERATE Optimize the selected code to improve performance and readablilty.',
    },
    Docs = {
      prompt = '/COPILOT_GENERATE Please add documentation comment for the selection.',
    },
    Tests = {
      prompt = '/COPILOT_GENERATE Please generate tests for my code.',
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
      selection = function(source)
        return select.gitdiff(source, true)
      end,
    },
  },

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
    complete = {
      detail = 'Use @<Tab> or /<Tab> for options.',
      insert ='<Tab>',
    },
    close = {
      normal = 'q',
      insert = '<C-c>'
    },
    reset = {
      normal ='<C-l>',
      insert = '<C-l>'
    },
    submit_prompt = {
      normal = '<CR>',
      insert = '<C-m>'
    },
    accept_diff = {
      normal = '<C-y>',
      insert = '<C-y>'
    },
    yank_diff = {
      normal = 'gy',
    },
    show_diff = {
      normal = 'gd'
    },
    show_system_prompt = {
      normal = 'gp'
    },
    show_user_selection = {
      normal = 'gs'
    },
  },
}
```

For further reference, you can view @jellydn's [configuration](https://github.com/jellydn/lazy-nvim-ide/blob/main/lua/plugins/extras/copilot-chat-v2.lua).

### Defining a prompt with command and keymap

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

### Referencing system or user prompts

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

### Custom system prompts

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

### Customizing buffers

You can set local options for the buffers that are created by this plugin: `copilot-diff`, `copilot-system-prompt`, `copilot-user-selection`, `copilot-chat`.

```lua
vim.api.nvim_create_autocmd('BufEnter', {
    pattern = 'copilot-*',
    callback = function()
        vim.opt_local.relativenumber = true

        -- C-p to print last response
        vim.keymap.set('n', '<C-p>', function()
          print(require("CopilotChat").response())
        end, { buffer = true, remap = true })
    end
})
```

## Tips

<details>
<summary>Quick chat with your buffer</summary>

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

</details>

<details>
<summary>Inline chat</summary>

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

</details>

<details>
<summary>Telescope integration</summary>

Requires [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) plugin to be installed.

```lua
-- lazy.nvim keys

  -- Show help actions with telescope
  {
    "<leader>cch",
    function()
      local actions = require("CopilotChat.actions")
      require("CopilotChat.integrations.telescope").pick(actions.help_actions())
    end,
    desc = "CopilotChat - Help actions",
  },
  -- Show prompts actions with telescope
  {
    "<leader>ccp",
    function()
      local actions = require("CopilotChat.actions")
      require("CopilotChat.integrations.telescope").pick(actions.prompt_actions())
    end,
    desc = "CopilotChat - Prompt actions",
  },
```

![image](https://github.com/CopilotC-Nvim/CopilotChat.nvim/assets/5115805/14360883-7535-4ee3-aca1-79f6c39f626b)

</details>

<details>
<summary>fzf-lua integration</summary>

Requires [fzf-lua](https://github.com/ibhagwan/fzf-lua) plugin to be installed.

```lua
-- lazy.nvim keys

  -- Show help actions with fzf-lua
  {
    "<leader>cch",
    function()
      local actions = require("CopilotChat.actions")
      require("CopilotChat.integrations.fzflua").pick(actions.help_actions())
    end,
    desc = "CopilotChat - Help actions",
  },
  -- Show prompts actions with fzf-lua
  {
    "<leader>ccp",
    function()
      local actions = require("CopilotChat.actions")
      require("CopilotChat.integrations.fzflua").pick(actions.prompt_actions())
    end,
    desc = "CopilotChat - Prompt actions",
  },
```

![image](https://github.com/CopilotC-Nvim/CopilotChat.nvim/assets/5115805/743455bb-9517-48a8-a7a1-81215dc3b747)

</details>

## Roadmap (Wishlist)

- Use indexed vector database with current workspace for better context selection
- General QOL improvements

## Development

### Installing Pre-commit Tool

For development, you can use the provided Makefile command to install the pre-commit tool:

```bash
make install-pre-commit
```

This will install the pre-commit tool and the pre-commit hooks.

## Contributors ✨

If you want to contribute to this project, please read the [CONTRIBUTING.md](/CONTRIBUTING.md) file.

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
      <td align="center" valign="top" width="14.28%"><a href="http://www.gaardhus.dk"><img src="https://avatars.githubusercontent.com/u/46934916?v=4?s=100" width="100px;" alt="Tobias Gårdhus"/><br /><sub><b>Tobias Gårdhus</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=gaardhus" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://www.patreon.com/PetrDlouhy"><img src="https://avatars.githubusercontent.com/u/156755?v=4?s=100" width="100px;" alt="Petr Dlouhý"/><br /><sub><b>Petr Dlouhý</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=PetrDlouhy" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://www.dylanmadisetti.com"><img src="https://avatars.githubusercontent.com/u/2689338?v=4?s=100" width="100px;" alt="Dylan Madisetti"/><br /><sub><b>Dylan Madisetti</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=dmadisetti" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/aweis89"><img src="https://avatars.githubusercontent.com/u/5186956?v=4?s=100" width="100px;" alt="Aaron Weisberg"/><br /><sub><b>Aaron Weisberg</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=aweis89" title="Code">💻</a> <a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=aweis89" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/tlacuilose"><img src="https://avatars.githubusercontent.com/u/65783495?v=4?s=100" width="100px;" alt="Jose Tlacuilo"/><br /><sub><b>Jose Tlacuilo</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=tlacuilose" title="Code">💻</a> <a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=tlacuilose" title="Documentation">📖</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="http://kevintraver.com"><img src="https://avatars.githubusercontent.com/u/196406?v=4?s=100" width="100px;" alt="Kevin Traver"/><br /><sub><b>Kevin Traver</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=kevintraver" title="Code">💻</a> <a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=kevintraver" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/D7ry"><img src="https://avatars.githubusercontent.com/u/92609548?v=4?s=100" width="100px;" alt="dTry"/><br /><sub><b>dTry</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=D7ry" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://blog.ornew.io"><img src="https://avatars.githubusercontent.com/u/19766770?v=4?s=100" width="100px;" alt="Arata Furukawa"/><br /><sub><b>Arata Furukawa</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=ornew" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/lingjie00"><img src="https://avatars.githubusercontent.com/u/64540764?v=4?s=100" width="100px;" alt="Ling"/><br /><sub><b>Ling</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=lingjie00" title="Code">💻</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind are welcome!

### Stargazers over time

[![Stargazers over time](https://starchart.cc/CopilotC-Nvim/CopilotChat.nvim.svg)](https://starchart.cc/CopilotC-Nvim/CopilotChat.nvim)
