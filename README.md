<div align="center">

# Copilot Chat for Neovim

[![Release](https://img.shields.io/github/v/release/CopilotC-Nvim/CopilotChat.nvim?logo=github&style=for-the-badge)](https://github.com/CopilotC-Nvim/CopilotChat.nvim/releases/latest)
[![Build](https://img.shields.io/github/actions/workflow/status/CopilotC-Nvim/CopilotChat.nvim/ci.yml?logo=github&style=for-the-badge)](https://github.com/CopilotC-Nvim/CopilotChat.nvim/actions/workflows/ci.yml)
[![Documentation](https://img.shields.io/badge/documentation-up-green.svg?logo=vim&style=for-the-badge)](https://copilotc-nvim.github.io/CopilotChat.nvim/)

[![Contributors](https://img.shields.io/github/all-contributors/CopilotC-Nvim/CopilotChat.nvim?color=ee8449&logo=github&label=contributors&style=for-the-badge)](#contributors)
[![Discord](https://img.shields.io/discord/1200633211236122665?logo=discord&label=discord&style=for-the-badge)](https://discord.gg/vy6hJsTWaZ)
[![Dotfyle](https://dotfyle.com/plugins/CopilotC-Nvim/CopilotChat.nvim/shield?style=for-the-badge)](https://dotfyle.com/plugins/CopilotC-Nvim/CopilotChat.nvim)

![image](https://github.com/user-attachments/assets/9ee30811-0fb8-4500-91f6-34ea6b26adea)

https://github.com/user-attachments/assets/8cad5643-63b2-4641-a5c4-68bc313f20e6

</div>

CopilotChat.nvim brings GitHub Copilot Chat capabilities directly into Neovim with a focus on transparency and user control.

- 🤖 **Multiple AI Models** - GitHub Copilot (including GPT-4o, Gemini 2.5 Pro, Claude 4 Sonnet, Claude 3.7 Sonnet, Claude 3.5 Sonnet, o3-mini, o4-mini) + custom providers (Ollama, Mistral.ai). The exact list of available models depends on your [GitHub Copilot settings](https://github.com/settings/copilot/features) and the models provided by GitHub's API.
- 🔧 **Tool Calling** - LLM can use workspace functions (file reading, git operations, search) with your explicit approval
- 🔒 **Explicit Control** - Only shares what you specifically request - no background data collection
- 📝 **Interactive Chat** - Rich UI with completion, diffs, and quickfix integration
- 🎯 **Smart Prompts** - Composable templates and sticky prompts for consistent context
- ⚡ **Efficient** - Smart token usage with tiktoken counting and history management
- 🔌 **Extensible** - [Custom functions](https://github.com/CopilotC-Nvim/CopilotChat.nvim/discussions/categories/functions) and [providers](https://github.com/CopilotC-Nvim/CopilotChat.nvim/discussions/categories/providers), plus integrations like [mcphub.nvim](https://github.com/ravitemer/mcphub.nvim)

# Installation

## Requirements

- [Neovim 0.10.0+](https://neovim.io/)
- [curl 8.0.0+](https://curl.se/)
- [Copilot chat in the IDE](https://github.com/settings/copilot) enabled in GitHub settings
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)

> [!WARNING]
> For Neovim < 0.11.0, add `noinsert` or `noselect` to your `completeopt` otherwise chat autocompletion will not work.
> For best autocompletion experience, also add `popup` to your `completeopt` (even on Neovim 0.11.0+).

## Optional Dependencies

- [tiktoken_core](https://github.com/gptlang/lua-tiktoken) - For accurate token counting
  - Arch Linux: Install [`luajit-tiktoken-bin`](https://aur.archlinux.org/packages/luajit-tiktoken-bin) or [`lua51-tiktoken-bin`](https://aur.archlinux.org/packages/lua51-tiktoken-bin) from AUR
  - Via luarocks: `sudo luarocks install --lua-version 5.1 tiktoken_core`
  - Manual: Download from [lua-tiktoken releases](https://github.com/gptlang/lua-tiktoken/releases) and save as `tiktoken_core.so` in your Lua path
- [git](https://git-scm.com/) - For git diff context features
- [ripgrep](https://github.com/BurntSushi/ripgrep) - For improved search performance
- [lynx](https://lynx.invisible-island.net/) - For improved URL context features

## Integration with pickers

For various plugin pickers to work correctly, you need to replace `vim.ui.select` with your desired picker (as the default `vim.ui.select` is very basic). Here are some examples:

- [fzf-lua](https://github.com/ibhagwan/fzf-lua?tab=readme-ov-file#neovim-api) - call `require('fzf-lua').register_ui_select()`
- [telescope](https://github.com/nvim-telescope/telescope-ui-select.nvim?tab=readme-ov-file#telescope-setup-and-configuration) - setup `telescope-ui-select.nvim` plugin
- [snacks.picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md#%EF%B8%8F-config) - enable `ui_select` config
- [mini.pick](https://github.com/echasnovski/mini.pick/blob/main/lua/mini/pick.lua#L1229) - set `vim.ui.select = require('mini.pick').ui_select`

## [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    dependencies = {
      { "nvim-lua/plenary.nvim", branch = "master" },
    },
    build = "make tiktoken",
    opts = {
      -- See Configuration section for options
    },
  },
}
```

## [vim-plug](https://github.com/junegunn/vim-plug)

```vim
call plug#begin()
Plug 'nvim-lua/plenary.nvim'
Plug 'CopilotC-Nvim/CopilotChat.nvim'
call plug#end()

lua << EOF
require("CopilotChat").setup()
EOF
```

# Core Concepts

- **Resources** (`#<name>`) - Add specific content (files, git diffs, URLs) to your prompt
- **Tools** (`@<name>`) - Give LLM access to functions it can call with your approval
- **Sticky Prompts** (`> <text>`) - Persist context across single chat session
- **Models** (`$<model>`) - Specify which AI model to use for the chat
- **Prompts** (`/PromptName`) - Use predefined prompt templates for common tasks
- **Selection** - Automatically includes current user selection in prompts

## Examples

```markdown
# Add specific file to context

#file:src/main.lua

# Give LLM access to workspace tools

@copilot What files are in this project?

# Sticky prompt that persists

> #buffer:current
> You are a helpful coding assistant
```

When you use `@copilot`, the LLM can call functions like `glob`, `file`, `gitdiff` etc. You'll see the proposed function call and can approve/reject it before execution.

# Usage

## Commands

| Command                    | Description                   |
| -------------------------- | ----------------------------- |
| `:CopilotChat <input>?`    | Open chat with optional input |
| `:CopilotChatOpen`         | Open chat window              |
| `:CopilotChatClose`        | Close chat window             |
| `:CopilotChatToggle`       | Toggle chat window            |
| `:CopilotChatStop`         | Stop current output           |
| `:CopilotChatReset`        | Reset chat window             |
| `:CopilotChatSave <name>?` | Save chat history             |
| `:CopilotChatLoad <name>?` | Load chat history             |
| `:CopilotChatPrompts`      | View/select prompt templates  |
| `:CopilotChatModels`       | View/select available models  |
| `:CopilotChat<PromptName>` | Use specific prompt template  |

## Chat Key Mappings

| Insert  | Normal  | Action                                     |
| ------- | ------- | ------------------------------------------ |
| `<Tab>` | -       | Trigger/accept completion menu for tokens  |
| `<C-c>` | `q`     | Close the chat window                      |
| `<C-l>` | `<C-l>` | Reset and clear the chat window            |
| `<C-s>` | `<CR>`  | Submit the current prompt                  |
| -       | `grr`   | Toggle sticky prompt for line under cursor |
| -       | `grx`   | Clear all sticky prompts in prompt         |
| `<C-y>` | `<C-y>` | Accept nearest diff                        |
| -       | `gj`    | Jump to section of nearest diff            |
| -       | `gqa`   | Add all answers from chat to quickfix list |
| -       | `gqd`   | Add all diffs from chat to quickfix list   |
| -       | `gy`    | Yank nearest diff to register              |
| -       | `gd`    | Show diff between source and nearest diff  |
| -       | `gc`    | Show info about current chat               |
| -       | `gh`    | Show help message                          |

> [!WARNING]
> Some plugins (e.g. `copilot.vim`) may also map common keys like `<Tab>` in insert mode.  
> To avoid conflicts, disable Copilot's default `<Tab>` mapping with:
>
> ```lua
> vim.g.copilot_no_tab_map = true
> vim.keymap.set('i', '<S-Tab>', 'copilot#Accept("\\<S-Tab>")', { expr = true, replace_keycodes = false })
> ```
>
> You can also customize CopilotChat keymaps in your config.

## Predefined Functions

All predefined functions belong to the `copilot` group.

| Function      | Description                                      | Example Usage          |
| ------------- | ------------------------------------------------ | ---------------------- |
| `buffer`      | Retrieves content from a specific buffer         | `#buffer`              |
| `buffers`     | Fetches content from multiple buffers            | `#buffers:visible`     |
| `diagnostics` | Collects code diagnostics (errors, warnings)     | `#diagnostics:current` |
| `file`        | Reads content from a specified file path         | `#file:path/to/file`   |
| `gitdiff`     | Retrieves git diff information                   | `#gitdiff:staged`      |
| `gitstatus`   | Retrieves git status information                 | `#gitstatus`           |
| `glob`        | Lists filenames matching a pattern in workspace  | `#glob:**/*.lua`       |
| `grep`        | Searches for a pattern across files in workspace | `#grep:TODO`           |
| `quickfix`    | Includes content of files in quickfix list       | `#quickfix`            |
| `register`    | Provides access to specified Vim register        | `#register:+`          |
| `url`         | Fetches content from a specified URL             | `#url:https://...`     |

## Predefined Prompts

| Prompt     | Description                                                            |
| ---------- | ---------------------------------------------------------------------- |
| `Explain`  | Write detailed explanation of selected code as paragraphs              |
| `Review`   | Comprehensive code review with line-specific issue reporting           |
| `Fix`      | Identify problems and rewrite code with fixes and explanation          |
| `Optimize` | Improve performance and readability with optimization strategy         |
| `Docs`     | Add documentation comments to selected code                            |
| `Tests`    | Generate tests for selected code                                       |
| `Commit`   | Generate commit message with commitizen convention from staged changes |

# Configuration

For all available configuration options, see [`lua/CopilotChat/config.lua`](lua/CopilotChat/config.lua).

## Quick Setup

Most users only need to configure a few options:

```lua
{
  model = 'gpt-4.1',           -- AI model to use
  temperature = 0.1,           -- Lower = focused, higher = creative
  window = {
    layout = 'vertical',       -- 'vertical', 'horizontal', 'float'
    width = 0.5,              -- 50% of screen width
  },
  auto_insert_mode = true,     -- Enter insert mode when opening
}
```

## Window & Appearance

```lua
{
  window = {
    layout = 'float',
    width = 80, -- Fixed width in columns
    height = 20, -- Fixed height in rows
    border = 'rounded', -- 'single', 'double', 'rounded', 'solid'
    title = '🤖 AI Assistant',
    zindex = 100, -- Ensure window stays on top
  },

  headers = {
    user = '👤 You: ',
    assistant = '🤖 Copilot: ',
    tool = '🔧 Tool: ',
  },
  separator = '━━',
  show_folds = false, -- Disable folding for cleaner look
}
```

## Buffer Behavior

```lua
-- Auto-command to customize chat buffer behavior
vim.api.nvim_create_autocmd('BufEnter', {
  pattern = 'copilot-*',
  callback = function()
    vim.opt_local.relativenumber = false
    vim.opt_local.number = false
    vim.opt_local.conceallevel = 0
  end,
})
```

## Highlights

You can customize colors by setting highlight groups in your config:

```lua
-- In your colorscheme or init.lua
vim.api.nvim_set_hl(0, 'CopilotChatHeader', { fg = '#7C3AED', bold = true })
vim.api.nvim_set_hl(0, 'CopilotChatSeparator', { fg = '#374151' })
```

Types of copilot highlights:

- `CopilotChatHeader` - Header highlight in chat buffer
- `CopilotChatSeparator` - Separator highlight in chat buffer
- `CopilotChatStatus` - Status and spinner in chat buffer
- `CopilotChatHelp` - Help text in chat buffer
- `CopilotChatResource` - Resource highlight in chat buffer (e.g. `#file`, `#gitdiff`)
- `CopilotChatTool` - Tool call highlight in chat buffer (e.g. `@copilot`)
- `CopilotChatPrompt` - Prompt highlight in chat buffer (e.g. `/Explain`, `/Review`)
- `CopilotChatModel` - Model highlight in chat buffer (e.g. `$gpt-4.1`)
- `CopilotChatUri` - URI highlight in chat buffer (e.g. `##https://...`)
- `CopilotChatSelection` - Selection highlight in source buffer
- `CopilotChatAnnotation` - Annotation highlight in chat buffer (file headers, tool call headers, tool call body)

## Prompts

Define your own prompts in the configuration:

```lua
{
  prompts = {
    MyCustomPrompt = {
      prompt = 'Explain how it works.',
      system_prompt = 'You are very good at explaining stuff',
      mapping = '<leader>ccmc',
      description = 'My custom prompt description',
    },
    Yarrr = {
      system_prompt = 'You are fascinated by pirates, so please respond in pirate speak.',
    },
    NiceInstructions = {
      system_prompt = 'You are a nice coding tutor, so please respond in a friendly and helpful manner.',
    }
  }
}
```

## Functions

Define your own functions in the configuration with input handling and schema:

```lua
{
  functions = {
    birthday = {
      description = "Retrieves birthday information for a person",
      uri = "birthday://{name}",
      schema = {
        type = 'object',
        required = { 'name' },
        properties = {
          name = {
            type = 'string',
            enum = { 'Alice', 'Bob', 'Charlie' },
            description = "Person's name",
          },
        },
      },
      resolve = function(input)
        return {
          {
            uri = 'birthday://' .. input.name,
            mimetype = 'text/plain',
            data = input.name .. ' birthday info',
          }
        }
      end
    }
  }
}
```

## Selections

Control what content is automatically included:

```lua
{
  -- Use visual selection, fallback to current line
  selection = function(source)
    return require('CopilotChat.select').visual(source) or
           require('CopilotChat.select').line(source)
  end,
}
```

**Available selections:**

- `require('CopilotChat.select').visual` - Current visual selection
- `require('CopilotChat.select').buffer` - Entire buffer content
- `require('CopilotChat.select').line` - Current line content
- `require('CopilotChat.select').unnamed` - Unnamed register (last deleted/changed/yanked)

## Providers

Add custom AI providers:

```lua
{
  providers = {
    my_provider = {
      get_url = function(opts) return "https://api.example.com/chat" end,
      get_headers = function() return { ["Authorization"] = "Bearer " .. api_key } end,
      get_models = function() return { { id = "gpt-4.1", name = "GPT-4.1 model" } } end,
      prepare_input = require('CopilotChat.config.providers').copilot.prepare_input,
      prepare_output = require('CopilotChat.config.providers').copilot.prepare_output,
    }
  }
}
```

**Provider Interface:**

```lua
{
  -- Optional: Disable provider
  disabled?: boolean,

  -- Optional: Extra info about the provider displayed in info panel
  get_info?(): string[]

  -- Optional: Get extra request headers with optional expiration time
  get_headers?(): table<string,string>, number?,

  -- Optional: Get API endpoint URL
  get_url?(opts: CopilotChat.Provider.options): string,

  -- Optional: Prepare request input
  prepare_input?(inputs: table<CopilotChat.Provider.input>, opts: CopilotChat.Provider.options): table,

  -- Optional: Prepare response output
  prepare_output?(output: table, opts: CopilotChat.Provider.options): CopilotChat.Provider.output,

  -- Optional: Get available models
  get_models?(headers: table): table<CopilotChat.Provider.model>,
}
```

**Built-in providers:**

- `copilot` - GitHub Copilot (default)
- `github_models` - GitHub Marketplace models (disabled by default)

# API Reference

## Core

```lua
local chat = require("CopilotChat")

-- Basic Chat Functions
chat.ask(prompt, config)      -- Ask a question with optional config
chat.response()               -- Get the last response text
chat.resolve_prompt()         -- Resolve prompt references
chat.resolve_functions()      -- Resolve functions that are available for automatic use by LLM (WARN: async, requires plenary.async.run)
chat.resolve_model()          -- Resolve model from prompt (WARN: async, requires plenary.async.run)

-- Window Management
chat.open(config)             -- Open chat window with optional config
chat.close()                  -- Close chat window
chat.toggle(config)           -- Toggle chat window visibility with optional config
chat.reset()                  -- Reset the chat
chat.stop()                   -- Stop current output

-- Source Management
chat.get_source()             -- Get the current source buffer and window
chat.set_source(winnr)        -- Set the source window

-- Selection Management
chat.get_selection()                                   -- Get the current selection
chat.set_selection(bufnr, start_line, end_line, clear) -- Set or clear selection

-- Prompt & Model Management
chat.select_prompt(config)    -- Open prompt selector with optional config
chat.select_model()           -- Open model selector

-- History Management
chat.load(name, history_path) -- Load chat history
chat.save(name, history_path) -- Save chat history

-- Configuration
chat.setup(config)            -- Update configuration
chat.log_level(level)         -- Set log level (debug, info, etc.)
```

## Chat Window

You can also access the chat window UI methods through the `chat.chat` object:

```lua
local window = require("CopilotChat").chat

-- Chat UI State
window:visible()             -- Check if chat window is visible
window:focused()             -- Check if chat window is focused

-- Message Management
window:get_message(role, cursor)               -- Get chat message by role, either last or closest to cursor
window:add_message({ role, content }, replace) -- Add or replace a message in chat
window:remove_message(role, cursor)            -- Remove chat message by role, either last or closest to cursor
window:get_block(role, cursor)                 -- Get code block by role, either last or closest to cursor
window:add_sticky(sticky)                      -- Add sticky prompt to chat message

-- Content Management
window:append(text)          -- Append text to chat window
window:clear()               -- Clear chat window content
window:start()               -- Start writing to chat window
window:finish()              -- Finish writing to chat window

-- Navigation
window:follow()              -- Move cursor to end of chat content
window:focus()               -- Focus the chat window

-- Advanced Features
window:overlay(opts)         -- Show overlay with specified options
```

## Example Usage

```lua
-- Open chat, ask a question and handle response
require("CopilotChat").open()
require("CopilotChat").ask("#buffer Explain this code", {
  callback = function(response)
    vim.notify("Got response: " .. response:sub(1, 50) .. "...")
    return response
  end,
})

-- Save and load chat history
require("CopilotChat").save("my_debugging_session")
require("CopilotChat").load("my_debugging_session")

-- Use custom sticky and model
require("CopilotChat").ask("How can I optimize this?", {
  model = "gpt-4.1",
  sticky = {"#buffer", "#gitdiff:staged"}
})
```

For more examples, see the [examples wiki page](https://github.com/CopilotC-Nvim/CopilotChat.nvim/wiki/Examples-and-Tips).

# Development

## Setup

To set up the environment:

1. Clone the repository:

```bash
git clone https://github.com/CopilotC-Nvim/CopilotChat.nvim
cd CopilotChat.nvim
```

2. Install development dependencies:

```bash
make install-pre-commit
```

To run tests:

```bash
make test
```

## Contributing

1. Fork the repository
2. Create your feature branch
3. Make your changes
4. Run tests and lint checks
5. Submit a pull request

See [CONTRIBUTING.md](/CONTRIBUTING.md) for detailed guidelines.

# Contributors

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
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/frolvanya"><img src="https://avatars.githubusercontent.com/u/59515280?v=4?s=100" width="100px;" alt="Ivan Frolov"/><br /><sub><b>Ivan Frolov</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=frolvanya" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://www.folkelemaitre.com"><img src="https://avatars.githubusercontent.com/u/292349?v=4?s=100" width="100px;" alt="Folke Lemaitre"/><br /><sub><b>Folke Lemaitre</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=folke" title="Code">💻</a> <a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=folke" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/GitMurf"><img src="https://avatars.githubusercontent.com/u/64155612?v=4?s=100" width="100px;" alt="GitMurf"/><br /><sub><b>GitMurf</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=GitMurf" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="http://dimalip.in"><img src="https://avatars.githubusercontent.com/u/6877858?v=4?s=100" width="100px;" alt="Dmitrii Lipin"/><br /><sub><b>Dmitrii Lipin</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=festeh" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://nvimer.org"><img src="https://avatars.githubusercontent.com/u/41784264?v=4?s=100" width="100px;" alt="jinzhongjia"/><br /><sub><b>jinzhongjia</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=jinzhongjia" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/guill"><img src="https://avatars.githubusercontent.com/u/3157454?v=4?s=100" width="100px;" alt="guill"/><br /><sub><b>guill</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=guill" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/sjonpaulbrown-cc"><img src="https://avatars.githubusercontent.com/u/81941908?v=4?s=100" width="100px;" alt="Sjon-Paul Brown"/><br /><sub><b>Sjon-Paul Brown</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=sjonpaulbrown-cc" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/renxzen"><img src="https://avatars.githubusercontent.com/u/13023797?v=4?s=100" width="100px;" alt="Renzo Mondragón"/><br /><sub><b>Renzo Mondragón</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=renxzen" title="Code">💻</a> <a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=renxzen" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/fjchen7"><img src="https://avatars.githubusercontent.com/u/10106636?v=4?s=100" width="100px;" alt="fjchen7"/><br /><sub><b>fjchen7</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=fjchen7" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/radwo"><img src="https://avatars.githubusercontent.com/u/184065?v=4?s=100" width="100px;" alt="Radosław Woźniak"/><br /><sub><b>Radosław Woźniak</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=radwo" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/JakubPecenka"><img src="https://avatars.githubusercontent.com/u/87969308?v=4?s=100" width="100px;" alt="JakubPecenka"/><br /><sub><b>JakubPecenka</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=JakubPecenka" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/thomastthai"><img src="https://avatars.githubusercontent.com/u/16532581?v=4?s=100" width="100px;" alt="thomastthai"/><br /><sub><b>thomastthai</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=thomastthai" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://lisk.in/"><img src="https://avatars.githubusercontent.com/u/300342?v=4?s=100" width="100px;" alt="Tomáš Janoušek"/><br /><sub><b>Tomáš Janoušek</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=liskin" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/Moriango"><img src="https://avatars.githubusercontent.com/u/43554061?v=4?s=100" width="100px;" alt="Toddneal Stallworth"/><br /><sub><b>Toddneal Stallworth</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=Moriango" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/taketwo"><img src="https://avatars.githubusercontent.com/u/1241736?v=4?s=100" width="100px;" alt="Sergey Alexandrov"/><br /><sub><b>Sergey Alexandrov</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=taketwo" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/lemeb"><img src="https://avatars.githubusercontent.com/u/7331643?v=4?s=100" width="100px;" alt="Léopold Mebazaa"/><br /><sub><b>Léopold Mebazaa</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=lemeb" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://atko.space"><img src="https://avatars.githubusercontent.com/u/14937572?v=4?s=100" width="100px;" alt="JunKi Jin"/><br /><sub><b>JunKi Jin</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=atkodev" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/abdennourzahaf"><img src="https://avatars.githubusercontent.com/u/62243290?v=4?s=100" width="100px;" alt="abdennourzahaf"/><br /><sub><b>abdennourzahaf</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=abdennourzahaf" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/josiahdenton"><img src="https://avatars.githubusercontent.com/u/44758384?v=4?s=100" width="100px;" alt="Josiah"/><br /><sub><b>Josiah</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=josiahdenton" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/tku137"><img src="https://avatars.githubusercontent.com/u/3052212?v=4?s=100" width="100px;" alt="Tony Fischer"/><br /><sub><b>Tony Fischer</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=tku137" title="Code">💻</a> <a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=tku137" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://qiita.com/program3152019"><img src="https://avatars.githubusercontent.com/u/64008205?v=4?s=100" width="100px;" alt="Kohei Wada"/><br /><sub><b>Kohei Wada</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=Kohei-Wada" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://zags.dev"><img src="https://avatars.githubusercontent.com/u/79172513?v=4?s=100" width="100px;" alt="Sebastian Yaghoubi"/><br /><sub><b>Sebastian Yaghoubi</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=syaghoubi00" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/johncming"><img src="https://avatars.githubusercontent.com/u/11719334?v=4?s=100" width="100px;" alt="johncming"/><br /><sub><b>johncming</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=johncming" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/dzonatan"><img src="https://avatars.githubusercontent.com/u/5166666?v=4?s=100" width="100px;" alt="Rokas Brazdžionis"/><br /><sub><b>Rokas Brazdžionis</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=dzonatan" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/unlimitedsola"><img src="https://avatars.githubusercontent.com/u/3632663?v=4?s=100" width="100px;" alt="Sola"/><br /><sub><b>Sola</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=unlimitedsola" title="Documentation">📖</a> <a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=unlimitedsola" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/ThisIsMani"><img src="https://avatars.githubusercontent.com/u/84711804?v=4?s=100" width="100px;" alt="Mani Chandra"/><br /><sub><b>Mani Chandra</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=ThisIsMani" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://nischalbasuti.github.io/"><img src="https://avatars.githubusercontent.com/u/14853910?v=4?s=100" width="100px;" alt="Nischal Basuti"/><br /><sub><b>Nischal Basuti</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=nischalbasuti" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://teoljungberg.com"><img src="https://avatars.githubusercontent.com/u/810650?v=4?s=100" width="100px;" alt="Teo Ljungberg"/><br /><sub><b>Teo Ljungberg</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=teoljungberg" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/JPricey"><img src="https://avatars.githubusercontent.com/u/4826348?v=4?s=100" width="100px;" alt="Joe Price"/><br /><sub><b>Joe Price</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=JPricey" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://ouuan.moe/about"><img src="https://avatars.githubusercontent.com/u/30581822?v=4?s=100" width="100px;" alt="Yufan You"/><br /><sub><b>Yufan You</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=ouuan" title="Documentation">📖</a> <a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=ouuan" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://m4dd0c.netlify.app"><img src="https://avatars.githubusercontent.com/u/77256586?v=4?s=100" width="100px;" alt="Manish Kumar"/><br /><sub><b>Manish Kumar</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=m4dd0c" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://www.azdanov.dev"><img src="https://avatars.githubusercontent.com/u/6123841?v=4?s=100" width="100px;" alt="Anton Ždanov"/><br /><sub><b>Anton Ždanov</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=azdanov" title="Documentation">📖</a> <a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=azdanov" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://fredrikaverpil.github.io"><img src="https://avatars.githubusercontent.com/u/994357?v=4?s=100" width="100px;" alt="Fredrik Averpil"/><br /><sub><b>Fredrik Averpil</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=fredrikaverpil" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://a14n.net"><img src="https://avatars.githubusercontent.com/u/509703?v=4?s=100" width="100px;" alt="Aaron D Borden"/><br /><sub><b>Aaron D Borden</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=adborden" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/AtifChy"><img src="https://avatars.githubusercontent.com/u/42291930?v=4?s=100" width="100px;" alt="Md. Iftakhar Awal Chowdhury"/><br /><sub><b>Md. Iftakhar Awal Chowdhury</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=AtifChy" title="Code">💻</a> <a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=AtifChy" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/danilohorta"><img src="https://avatars.githubusercontent.com/u/214497460?v=4?s=100" width="100px;" alt="Danilo Horta"/><br /><sub><b>Danilo Horta</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=danilohorta" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://mihamina.rktmb.org"><img src="https://avatars.githubusercontent.com/u/488088?v=4?s=100" width="100px;" alt="Mihamina Rakotomandimby"/><br /><sub><b>Mihamina Rakotomandimby</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=rakotomandimby" title="Documentation">📖</a> <a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=rakotomandimby" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://ajmalshajahan.me"><img src="https://avatars.githubusercontent.com/u/23806715?v=4?s=100" width="100px;" alt="Ajmal S"/><br /><sub><b>Ajmal S</b></sub></a><br /><a href="https://github.com/CopilotC-Nvim/CopilotChat.nvim/commits?author=AjmalShajahan" title="Code">💻</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind are welcome!

# Stargazers

[![Stargazers over time](https://starchart.cc/CopilotC-Nvim/CopilotChat.nvim.svg?variant=adaptive)](https://starchart.cc/CopilotC-Nvim/CopilotChat.nvim)
