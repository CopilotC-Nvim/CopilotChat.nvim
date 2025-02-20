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

# Requirements

- [Neovim 0.10.0+](https://neovim.io/) - Older versions are not officially supported
- [curl](https://curl.se/) - 8.0.0+ is recommended for best compatibility. Should be installed by default on most systems and also shipped with Neovim
- [Copilot chat in the IDE](https://github.com/settings/copilot) setting enabled in GitHub settings
- _Optional_ [tiktoken_core](https://github.com/gptlang/lua-tiktoken) - Used for more accurate token counting
  - For Arch Linux users, you can install [`luajit-tiktoken-bin`](https://aur.archlinux.org/packages/luajit-tiktoken-bin) or [`lua51-tiktoken-bin`](https://aur.archlinux.org/packages/lua51-tiktoken-bin) from aur
  - Alternatively, install via luarocks: `sudo luarocks install --lua-version 5.1 tiktoken_core`
  - Alternatively, download a pre-built binary from [lua-tiktoken releases](https://github.com/gptlang/lua-tiktoken/releases). You can check your Lua PATH in Neovim by doing `:lua print(package.cpath)`. Save the binary as `tiktoken_core.so` in any of the given paths.
- _Optional_ [git](https://git-scm.com/) - Used for fetching git diffs for `git` context
  - For Arch Linux users, you can install [`git`](https://archlinux.org/packages/extra/x86_64/git) from the official repositories
  - For other systems, use your package manager to install `git`. For windows use the installer provided from git site
- _Optional_ [lynx](https://lynx.invisible-island.net/) - Used for improved fetching of URLs for `url` context
  - For Arch Linux users, you can install [`lynx`](https://archlinux.org/packages/extra/x86_64/lynx) from the official repositories
  - For other systems, use your package manager to install `lynx`. For windows use the installer provided from lynx site

> [!WARNING]
> If you are on neovim < 0.11.0, you also might want to add `noinsert` and `popup` to your `completeopt` to make the chat completion behave well.

# Installation

## [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    dependencies = {
      { "github/copilot.vim" }, -- or zbirenbaum/copilot.lua
      { "nvim-lua/plenary.nvim", branch = "master" }, -- for curl, log and async functions
    },
    build = "make tiktoken", -- Only on MacOS or Linux
    opts = {
      -- See Configuration section for options
    },
    -- See Commands section for default commands if you want to lazy load on them
  },
}
```

See [@jellydn](https://github.com/jellydn) for [configuration](https://github.com/jellydn/lazy-nvim-ide/blob/main/lua/plugins/extras/copilot-chat-v2.lua)

## [vim-plug](https://github.com/junegunn/vim-plug)

Similar to the lazy setup, you can use the following configuration:

```vim
call plug#begin()
Plug 'github/copilot.vim'
Plug 'nvim-lua/plenary.nvim'
Plug 'CopilotC-Nvim/CopilotChat.nvim'
call plug#end()

lua << EOF
require("CopilotChat").setup {
  -- See Configuration section for options
}
EOF
```

## Manual

1. Put the files in the right place

```
mkdir -p ~/.config/nvim/pack/copilotchat/start
cd ~/.config/nvim/pack/copilotchat/start

git clone https://github.com/github/copilot.vim
git clone https://github.com/nvim-lua/plenary.nvim

git clone https://github.com/CopilotC-Nvim/CopilotChat.nvim
```

2. Add to your configuration (e.g. `~/.config/nvim/init.lua`)

```lua
require("CopilotChat").setup {
  -- See Configuration section for options
}
```

See [@deathbeam](https://github.com/deathbeam) for [configuration](https://github.com/deathbeam/dotfiles/blob/master/nvim/.config/nvim/lua/config/copilot.lua)

# Features

## Commands

Commands are used to control the chat interface:

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
| `:CopilotChatModels`       | View/select available models  |
| `:CopilotChatAgents`       | View/select available agents  |
| `:CopilotChat<PromptName>` | Use specific prompt template  |

## Key Mappings

Default mappings in the chat interface:

| Insert  | Normal  | Action                                             |
| ------- | ------- | -------------------------------------------------- |
| `<Tab>` | `<Tab>` | Trigger/accept completion menu for tokens          |
| `<C-c>` | `q`     | Close the chat window                              |
| `<C-l>` | `<C-l>` | Reset and clear the chat window                    |
| `<C-s>` | `<CR>`  | Submit the current prompt                          |
| -       | `gr`    | Toggle sticky prompt for line under cursor         |
| `<C-y>` | `<C-y>` | Accept nearest diff (best with `COPILOT_GENERATE`) |
| -       | `gj`    | Jump to section of nearest diff                    |
| -       | `gqa`   | Add all answers from chat to quickfix list         |
| -       | `gqd`   | Add all diffs from chat to quickfix list           |
| -       | `gy`    | Yank nearest diff to register                      |
| -       | `gd`    | Show diff between source and nearest diff          |
| -       | `gi`    | Show info about current chat                       |
| -       | `gc`    | Show current chat context                          |
| -       | `gh`    | Show help message                                  |

The mappings can be customized by setting the `mappings` table in your configuration. Each mapping can have:

- `normal`: Key for normal mode
- `insert`: Key for insert mode
- `detail`: Description of what the mapping does

For example, to change the submit prompt mapping or show_diff full diff option:

```lua
{
    mappings = {
      submit_prompt = {
        normal = '<Leader>s',
        insert = '<C-s>'
      }
      show_diff = {
        full_diff = true
      }
    }
}
```

## Prompts

### Predefined Prompts

Predefined prompt templates for common tasks. Reference them with `/PromptName` in chat or use `:CopilotChat<PromptName>`:

| Prompt     | Description                                      |
| ---------- | ------------------------------------------------ |
| `Explain`  | Write an explanation for the selected code       |
| `Review`   | Review the selected code                         |
| `Fix`      | Rewrite the code with bug fixes                  |
| `Optimize` | Optimize code for performance and readability    |
| `Docs`     | Add documentation comments to the code           |
| `Tests`    | Generate tests for the code                      |
| `Commit`   | Write commit message using commitizen convention |

Define your own prompts in the configuration:

```lua
{
  prompts = {
    MyCustomPrompt = {
      prompt = 'Explain how it works.',
      system_prompt = 'You are very good at explaining stuff',
      mapping = '<leader>ccmc',
      description = 'My custom prompt description',
    }
  }
}
```

### System Prompts

System prompts define the AI model's behavior. Reference them with `/PROMPT_NAME` in chat:

| Prompt                 | Description                                |
| ---------------------- | ------------------------------------------ |
| `COPILOT_INSTRUCTIONS` | Base GitHub Copilot instructions           |
| `COPILOT_EXPLAIN`      | Adds coding tutor behavior                 |
| `COPILOT_REVIEW`       | Adds code review behavior with diagnostics |
| `COPILOT_GENERATE`     | Adds code generation behavior and rules    |

Define your own system prompts in the configuration (similar to `prompts`):

```lua
{
  prompts = {
    Yarrr = {
      system_prompt = 'You are fascinated by pirates, so please respond in pirate speak.',
    }
  }
}
```

### Sticky Prompts

Sticky prompts persist across chat sessions. They're useful for maintaining context or agent selection. They work as follows:

1. Prefix text with `> ` using markdown blockquote syntax
2. The prompt will be copied at the start of every new chat prompt
3. Edit sticky prompts freely while maintaining the `> ` prefix

Examples:

```markdown
> #files
> List all files in the workspace

> @models Using Mistral-small
> What is 1 + 11
```

You can also set default sticky prompts in the configuration:

```lua
{
  sticky = {
    '@models Using Mistral-small',
    '#files:full',
  }
}
```

## Models and Agents

### Models

You can control which AI model to use in three ways:

1. List available models with `:CopilotChatModels`
2. Set model in prompt with `$model_name`
3. Configure default model via `model` config key

For supported models, see:

- [Copilot Chat Models](https://docs.github.com/en/copilot/using-github-copilot/ai-models/changing-the-ai-model-for-copilot-chat#ai-models-for-copilot-chat)
- [GitHub Marketplace Models](https://github.com/marketplace/models) (experimental, limited usage)

### Agents

Agents determine the AI assistant's capabilities. Control agents in three ways:

1. List available agents with `:CopilotChatAgents`
2. Set agent in prompt with `@agent_name`
3. Configure default agent via `agent` config key

The default "noop" agent is `none`. For more information:

- [Extension Agents Documentation](https://docs.github.com/en/copilot/using-github-copilot/using-extensions-to-integrate-external-tools-with-copilot-chat)
- [Available Agents](https://github.com/marketplace?type=apps&copilot_app=true)

## Contexts

Contexts provide additional information to the chat. Add context using `#context_name[:input]` syntax:

| Context    | Input Support | Description                         |
| ---------- | ------------- | ----------------------------------- |
| `buffer`   | ✓ (number)    | Current or specified buffer content |
| `buffers`  | ✓ (type)      | All buffers content (listed/all)    |
| `file`     | ✓ (path)      | Content of specified file           |
| `files`    | ✓ (mode)      | Workspace files (list/full content) |
| `git`      | ✓ (ref)       | Git diff (unstaged/staged/commit)   |
| `url`      | ✓ (url)       | Content from URL                    |
| `register` | ✓ (name)      | Content of vim register             |
| `quickfix` | -             | Quickfix list file contents         |

Examples:

```markdown
> #buffer
> #buffer:2
> #files:list
> #git:staged
> #url:https://example.com
```

Define your own contexts in the configuration with input handling and resolution:

```lua
{
  contexts = {
    birthday = {
      input = function(callback)
        vim.ui.select({ 'user', 'napoleon' }, {
          prompt = 'Select birthday> ',
        }, callback)
      end,
      resolve = function(input)
        return {
          {
            content = input .. ' birthday info',
            filename = input .. '_birthday',
            filetype = 'text',
          }
        }
      end
    }
  }
}
```

## Selections

Selections determine the source content for chat interactions. Configure them globally or per-prompt.

Available selections are located in `local select = require("CopilotChat.select")`:

| Selection | Description                                            |
| --------- | ------------------------------------------------------ |
| `visual`  | Current visual selection                               |
| `buffer`  | Current buffer content                                 |
| `line`    | Current line content                                   |
| `unnamed` | Unnamed register (last deleted/changed/yanked content) |

You can set a default selection in the configuration:

```lua
{
  -- Default uses visual selection or falls back to buffer
  selection = function(source)
    return select.visual(source) or select.buffer(source)
  end
}
```

## Providers

Providers are modules that implement integration with different AI providers.

### Built-in Providers

- `copilot` - Default GitHub Copilot provider used for chat and embeddings
- `github_models` - Provider for GitHub Marketplace models

### Provider Interface

Custom providers can implement these methods:

```lua
{
  -- Optional: Disable provider
  disabled?: boolean,

  -- Optional: Provider to use for embeddings
  embeddings?: string,

  -- Optional: Get authentication token
  get_token(): string, number?,

  -- Required: Get request headers
  get_headers(token: string): table,

  -- Required: Get API endpoint URL
  get_url(opts: table): string,

  -- Required: Prepare request body
  prepare_input(inputs: table, opts: table, model: table): table,

  -- Optional: Get available models
  get_models?(headers: table): table,

  -- Optional: Get available agents
  get_agents?(headers: table): table,
}
```

### Ollama Example

Here's how to implement an [ollama](https://ollama.com/) provider:

```lua
{
  providers = {
    ollama = {
      embed = 'copilot_embeddings', -- Use Copilot as embedding provider

      -- Copy copilot input and output processing
      prepare_input = require('CopilotChat.config.providers').copilot.prepare_input,
      prepare_output = require('CopilotChat.config.providers').copilot.prepare_output,

      get_headers = function()
        return {
          ['Content-Type'] = 'application/json',
        }
      end,

      get_models = function(headers)
        local utils = require('CopilotChat.utils')
        local response = utils.curl_get('http://localhost:11434/api/tags', { headers = headers })
        if not response or response.status ~= 200 then
          error('Failed to fetch models: ' .. tostring(response and response.status))
        end

        local models = {}
        for _, model in ipairs(vim.json.decode(response.body)['models']) do
          table.insert(models, {
            id = model.name,
            name = model.name
          })
        end
        return models
      end,

      get_url = function()
        return 'http://localhost:11434/api/chat'
      end,
    }
  }
}
```

# Configuration

## Default Configuration

Below are all available configuration options with their default values:

```lua
{

  -- Shared config starts here (can be passed to functions at runtime and configured via setup function)

  system_prompt = prompts.COPILOT_INSTRUCTIONS.system_prompt, -- System prompt to use (can be specified manually in prompt via /).

  model = 'gpt-4o', -- Default model to use, see ':CopilotChatModels' for available models (can be specified manually in prompt via $).
  agent = 'copilot', -- Default agent to use, see ':CopilotChatAgents' for available agents (can be specified manually in prompt via @).
  context = nil, -- Default context or array of contexts to use (can be specified manually in prompt via #).
  sticky = nil, -- Default sticky prompt or array of sticky prompts to use at start of every new chat.

  temperature = 0.1, -- GPT result temperature
  headless = false, -- Do not write to chat buffer and use history(useful for using callback for custom processing)
  callback = nil, -- Callback to use when ask response is received

  -- default selection
  selection = function(source)
    return select.visual(source) or select.buffer(source)
  end,

  -- default window options
  window = {
    layout = 'vertical', -- 'vertical', 'horizontal', 'float', 'replace'
    width = 0.5, -- fractional width of parent, or absolute width in columns when > 1
    height = 0.5, -- fractional height of parent, or absolute height in rows when > 1
    -- Options below only apply to floating windows
    relative = 'editor', -- 'editor', 'win', 'cursor', 'mouse'
    border = 'single', -- 'none', single', 'double', 'rounded', 'solid', 'shadow'
    row = nil, -- row position of the window, default is centered
    col = nil, -- column position of the window, default is centered
    title = 'Copilot Chat', -- title of chat window
    footer = nil, -- footer of chat window
    zindex = 1, -- determines if window is on top or below other floating windows
  },

  show_help = true, -- Shows help message as virtual lines when waiting for user input
  show_folds = true, -- Shows folds for sections in chat
  highlight_selection = true, -- Highlight selection
  highlight_headers = true, -- Highlight headers in chat, disable if using markdown renderers (like render-markdown.nvim)
  auto_follow_cursor = true, -- Auto-follow cursor in chat
  auto_insert_mode = false, -- Automatically enter insert mode when opening window and on new prompt
  insert_at_end = false, -- Move cursor to end of buffer when inserting text
  clear_chat_on_new_prompt = false, -- Clears chat on every new prompt

  -- Static config starts here (can be configured only via setup function)

  debug = false, -- Enable debug logging (same as 'log_level = 'debug')
  log_level = 'info', -- Log level to use, 'trace', 'debug', 'info', 'warn', 'error', 'fatal'
  proxy = nil, -- [protocol://]host[:port] Use this proxy
  allow_insecure = false, -- Allow insecure server connections

  chat_autocomplete = true, -- Enable chat autocompletion (when disabled, requires manual `mappings.complete` trigger)

  log_path = vim.fn.stdpath('state') .. '/CopilotChat.log', -- Default path to log file
  history_path = vim.fn.stdpath('data') .. '/copilotchat_history', -- Default path to stored history

  question_header = '# User ', -- Header to use for user questions
  answer_header = '# Copilot ', -- Header to use for AI answers
  error_header = '# Error ', -- Header to use for errors
  separator = '───', -- Separator to use in chat

  -- default providers
  -- see config/providers.lua for implementation
  providers = {
    copilot = {
    },
    github_models = {
    },
    copilot_embeddings = {
    },
  }

  -- default contexts
  -- see config/contexts.lua for implementation
  contexts = {
    buffer = {
    },
    buffers = {
    },
    file = {
    },
    files = {
    },
    git = {
    },
    url = {
    },
    register = {
    },
    quickfix = {
    },
  },

  -- default prompts
  -- see config/prompts.lua for implementation
  prompts = {
    Explain = {
      prompt = '> /COPILOT_EXPLAIN\n\nWrite an explanation for the selected code as paragraphs of text.',
    },
    Review = {
      prompt = '> /COPILOT_REVIEW\n\nReview the selected code.',
    },
    Fix = {
      prompt = '> /COPILOT_GENERATE\n\nThere is a problem in this code. Rewrite the code to show it with the bug fixed.',
    },
    Optimize = {
      prompt = '> /COPILOT_GENERATE\n\nOptimize the selected code to improve performance and readability.',
    },
    Docs = {
      prompt = '> /COPILOT_GENERATE\n\nPlease add documentation comments to the selected code.',
    },
    Tests = {
      prompt = '> /COPILOT_GENERATE\n\nPlease generate tests for my code.',
    },
    Commit = {
      prompt = '> #git:staged\n\nWrite commit message for the change with commitizen convention. Make sure the title has maximum 50 characters and message is wrapped at 72 characters. Wrap the whole message in code block with language gitcommit.',
    },
  },

  -- default mappings
  -- see config/mappings.lua for implementation
  mappings = {
    complete = {
      insert = '<Tab>',
    },
    close = {
      normal = 'q',
      insert = '<C-c>',
    },
    reset = {
      normal = '<C-l>',
      insert = '<C-l>',
    },
    submit_prompt = {
      normal = '<CR>',
      insert = '<C-s>',
    },
    toggle_sticky = {
      detail = 'Makes line under cursor sticky or deletes sticky line.',
      normal = 'gr',
    },
    accept_diff = {
      normal = '<C-y>',
      insert = '<C-y>',
    },
    jump_to_diff = {
      normal = 'gj',
    },
    quickfix_answers = {
      normal = 'gqa',
    },
    quickfix_diffs = {
      normal = 'gqd',
    },
    yank_diff = {
      normal = 'gy',
      register = '"', -- Default register to use for yanking
    },
    show_diff = {
      normal = 'gd',
      full_diff = false, -- Show full diff instead of unified diff when showing diff window
    },
    show_info = {
      normal = 'gi',
    },
    show_context = {
      normal = 'gc',
    },
    show_help = {
      normal = 'gh',
    },
  },
}
```

## Customizing Buffers

You can set local options for plugin buffers (`copilot-chat`, `copilot-diff`, `copilot-overlay`):

```lua
vim.api.nvim_create_autocmd('BufEnter', {
    pattern = 'copilot-*',
    callback = function()
        -- Set buffer-local options
        vim.opt_local.relativenumber = true

        -- Add buffer-local mappings
        vim.keymap.set('n', '<C-p>', function()
          print(require("CopilotChat").response())
        end, { buffer = true })
    end
})
```

# API Reference

```lua
local chat = require("CopilotChat")

-- Window Management
chat.open()     -- Open chat window
chat.open({     -- Open with custom options
  window = {
    layout = 'float',
    title = 'Custom Chat',
  },
})
chat.close()    -- Close chat window
chat.toggle()   -- Toggle chat window
chat.reset()    -- Reset chat window

-- Chat Interaction
chat.ask("Explain this code.")  -- Basic question
chat.ask("Explain this code.", {
  selection = require("CopilotChat.select").buffer,
  context = { 'buffers', 'files' },
  callback = function(response)
    print("Response:", response)
  end,
})

-- Utilities
chat.prompts()   -- Get all available prompts
chat.response()  -- Get last response
chat.log_level("debug")  -- Set log level


-- Actions
local actions = require("CopilotChat.actions")
actions.pick(actions.prompt_actions({
    selection = require("CopilotChat.select").visual,
}))

-- Update config
chat.setup({
    model = 'gpt-4',
    window = {
        layout = 'float'
    }
})
```

# Tips and Examples

## Quick Chat with Buffer

Set up a quick chat command that uses the entire buffer content:

```lua
-- Quick chat keybinding
vim.keymap.set('n', '<leader>ccq', function()
  local input = vim.fn.input("Quick Chat: ")
  if input ~= "" then
    require("CopilotChat").ask(input, {
      selection = require("CopilotChat.select").buffer
    })
  end
end, { desc = "CopilotChat - Quick chat" })
```

## Inline Chat Window

Configure the chat window to appear inline near the cursor:

```lua
require("CopilotChat").setup({
  window = {
    layout = 'float',
    relative = 'cursor',
    width = 1,
    height = 0.4,
    row = 1
  }
})
```

## Telescope Integration

Requires [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim):

```lua
vim.keymap.set('n', '<leader>ccp', function()
  local actions = require("CopilotChat.actions")
  require("CopilotChat.integrations.telescope").pick(actions.prompt_actions())
end, { desc = "CopilotChat - Prompt actions" })
```

## Quick Search with Perplexity

Requires [PerplexityAI Agent](https://github.com/marketplace/perplexityai):

```lua
vim.keymap.set({ 'n', 'v' }, '<leader>ccs', function()
  local input = vim.fn.input("Perplexity: ")
  if input ~= "" then
    require("CopilotChat").ask(input, {
      agent = "perplexityai",
      selection = false,
    })
  end
end, { desc = "CopilotChat - Perplexity Search" })
```

## Markdown Rendering

Use [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) for better chat display:

```lua
-- Register copilot-chat filetype
require('render-markdown').setup({
  file_types = { 'markdown', 'copilot-chat' },
})

-- Adjust chat display settings
require('CopilotChat').setup({
  highlight_headers = false,
  separator = '---',
  error_header = '> [!ERROR] Error',
})
```

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
# Install pre-commit hooks
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
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind are welcome!

# Stargazers

[![Stargazers over time](https://starchart.cc/CopilotC-Nvim/CopilotChat.nvim.svg)](https://starchart.cc/CopilotC-Nvim/CopilotChat.nvim)
