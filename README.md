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

## [Lazy.nvim](https://github.com/folke/lazy.nvim)

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

## [Vim-Plug](https://github.com/junegunn/vim-plug)

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

# Usage

## Commands

- `:CopilotChat <input>?` - Open chat window with optional input
- `:CopilotChatOpen` - Open chat window
- `:CopilotChatClose` - Close chat window
- `:CopilotChatToggle` - Toggle chat window
- `:CopilotChatStop` - Stop current copilot output
- `:CopilotChatReset` - Reset chat window
- `:CopilotChatSave <name>?` - Save chat history to file
- `:CopilotChatLoad <name>?` - Load chat history from file
- `:CopilotChatDebugInfo` - Show debug information
- `:CopilotChatModels` - View and select available models. This is reset when a new instance is made. Please set your model in `init.lua` for persistence.
- `:CopilotChatAgents` - View and select available agents. This is reset when a new instance is made. Please set your agent in `init.lua` for persistence.
- `:CopilotChat<PromptName>` - Ask a question with a specific prompt. For example, `:CopilotChatExplain` will ask a question with the `Explain` prompt. See [Prompts](#prompts) for more information.

## Chat Mappings

- `<Tab>` - Trigger completion menu for special tokens or accept current completion (see help)
- `q`/`<C-c>` - Close the chat window
- `<C-l>` - Reset and clear the chat window
- `<CR>`/`<C-s>` - Submit the current prompt
- `gr` - Toggle sticky prompt for the line under cursor
- `<C-y>` - Accept nearest diff (works best with `COPILOT_GENERATE` prompt)
- `gj` - Jump to section of nearest diff. If in different buffer, jumps there; creates buffer if needed (works best with `COPILOT_GENERATE` prompt)
- `gqa` - Add all answers from chat to quickfix list
- `gqd` - Add all diffs from chat to quickfix list
- `gy` - Yank nearest diff to register (defaults to `"`). Use `mappings.yank_diff.register` config option to set register
- `gd` - Show diff between source and nearest diff. Use `mappings.show_diff.full_diff` boolean config option to show full diff instead of unified diff
- `gi` - Show info about current chat (model, agent, system prompt)
- `gc` - Show current chat context
- `gh` - Show help message

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

You can ask Copilot to do various tasks with prompts. You can reference prompts with `/PromptName` in chat or call with command `:CopilotChat<PromptName>`.  
Default prompts are:

- `Explain` - Write an explanation for the selected code as paragraphs of text
- `Review` - Review the selected code
- `Fix` - There is a problem in this code. Rewrite the code to show it with the bug fixed
- `Optimize` - Optimize the selected code to improve performance and readability
- `Docs` - Please add documentation comments to the selected code
- `Tests` - Please generate tests for my code
- `Commit` - Write commit message for the change with commitizen convention

You can define custom prompts like this (only `prompt` is required):

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

## System Prompts

System prompts specify the behavior of the AI model. You can reference system prompts with `/PROMPT_NAME` in chat.
Default system prompts are:

- `COPILOT_INSTRUCTIONS` - Base GitHub Copilot instructions
- `COPILOT_EXPLAIN` - On top of the base instructions adds coding tutor behavior
- `COPILOT_REVIEW` - On top of the base instructions adds code review behavior with instructions on how to generate diagnostics
- `COPILOT_GENERATE` - On top of the base instructions adds code generation behavior, with predefined formatting and generation rules

You can define custom system prompts like this (works same as `prompts` so you can combine prompt and system prompt definitions):

```lua
{
  prompts = {
    Yarrr = {
      system_prompt = 'You are fascinated by pirates, so please respond in pirate speak.',
    }
  }
}
```

## Sticky Prompts

You can set sticky prompt in chat by prefixing the text with `> ` using markdown blockquote syntax.  
The sticky prompt will be copied at start of every new prompt in chat window. You can freely edit the sticky prompt, only rule is `> ` prefix at beginning of line.  
This is useful for preserving stuff like context and agent selection (see below).  
Example usage:

```markdown
> #files

List all files in the workspace
```

```markdown
> @models Using Mistral-small

What is 1 + 11
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

## Models

You can list available models with `:CopilotChatModels` command. Model determines the AI model used for the chat.  
You can set the model in the prompt by using `$` followed by the model name or default model via config using `model` key.  
For list of models supported by Copilot Chat see [here](https://docs.github.com/en/copilot/using-github-copilot/ai-models/changing-the-ai-model-for-copilot-chat#ai-models-for-copilot-chat).  
This plugin also supports Github Marketplace Models. These have fairly low limits but are useful for experimentation. For more information see [here](https://github.com/marketplace/models).

## Agents

Agents are used to determine the AI agent used for the chat. You can list available agents with `:CopilotChatAgents` command.  
You can set the agent in the prompt by using `@` followed by the agent name or default agent via config using `agent` key.  
Default "noop" agent is `copilot`.

For more information about extension agents, see [here](https://docs.github.com/en/copilot/using-github-copilot/using-extensions-to-integrate-external-tools-with-copilot-chat)  
You can install more agents from [here](https://github.com/marketplace?type=apps&copilot_app=true)

## Contexts

Contexts are used to determine the context of the chat.  
You can add context to the prompt by using `#` followed by the context name or default context via config using `context` (can be single or array) key.  
Any amount of context can be added to the prompt.  
If context supports input, you can set the input in the prompt by using `:` followed by the input (or pressing `complete` key after `:`).  
Default contexts are:

- `buffer` - Includes specified buffer in chat context. Supports input (default current).
  - `buffer:<number>` - Includes buffer with specified number in chat context.
- `buffers` - Includes all buffers in chat context. Supports input (default listed).
  - `buffers:listed` - Includes only listed buffers in chat context.
  - `buffers:all` - Includes all buffers in chat context.
- `file` - Includes content of provided file in chat context. Supports input.
  - `file:<path>` - Includes content of specified file in chat context.
- `files` - Includes all non-hidden files in the current workspace in chat context. Supports input (default list).
  - `files:list` - Only lists file names.
  - `files:full` - Includes file content for each file found. Can be slow on large workspaces, use with care.
- `git` - Requires `git`. Includes current git diff in chat context. Supports input (default unstaged, also accepts commit number).
  - `git:unstaged` - Includes unstaged changes in chat context.
  - `git:staged` - Includes staged changes in chat context.
  - `git:<commit>` - Includes changes from specified commit in chat context.
- `url` - Includes content of provided URL in chat context. Supports input.
  - `url:<url>` - Includes content of specified URL in chat context.
- `register` - Includes contents of register in chat context. Supports input (default +, e.g clipboard).
  - `register:<register>` - Includes contents of specified register in chat context.
- `quickfix` - Includes quickfix list file contents in chat context.

You can define custom contexts like this:

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
        input = input or 'user'
        local birthday = input
        if input == 'user' then
          birthday = birthday .. ' birthday is April 1, 1990'
        elseif input == 'napoleon' then
          birthday = birthday .. ' birthday is August 15, 1769'
        end

        return {
          {
            content = birthday,
            filename = input .. '_birthday',
            filetype = 'text',
          }
        }
      end
    }
  }
}
```

```markdown
> #birthday:user

What is my birthday
```

## Selections

Selections are used to determine the source of the chat (so basically what to chat about).  
Selections are configurable either by default or by prompt.  
Default selection is `visual` or `buffer` (if no visual selection).  
Selection includes content, start and end position, buffer info and diagnostic info (if available).
Supported selections that live in `local select = require("CopilotChat.select")` are:

- `select.visual` - Current visual selection.
- `select.buffer` - Current buffer content.
- `select.line` - Current line content.
- `select.unnamed` - Unnamed register content. This register contains last deleted, changed or yanked content.

You can chain multiple selections like this:

```lua
{
  selection = function(source)
    return select.visual(source) or select.buffer(source)
  end
}
```

## Providers

Providers are modules that implement integration with different AI providers. Built-in providers are:

- `copilot` - Default GitHub Copilot provider used for chat and embeddings
- `github_models` - Provider for GitHub Marketplace models

You can define custom providers by adding them to `providers` config. Provider has following fields:

- `disabled?: boolean` - Optional boolean to disable provider
- `embeddings?: string` - Optional string pointing to provider to use for embeddings
- `get_token(): string, number?` - Function that returns authentication token and optional expiry timestamp
- `get_headers(token: string, sessionid: string, machineid: string): table` - Function that returns headers for API requests
- `get_url(opts: table): string` - Function that returns API endpoint URL for given operation
- `prepare_input(inputs: table, opts: table, model: table): table` - Function that prepares request body
- `get_models?(headers: table): table` - Optional function that returns list of available models
- `get_agents?(headers: table): table` - Optional function that returns list of available agents

Example custom provider:

```lua
{
  providers = {
    my_provider = {
      -- Required fields
      get_token = function()
        return "my-token", os.time() + 3600 -- Token valid for 1 hour
      end,
      get_headers = function(token, sessionid, machineid)
        return {
          ["authorization"] = "Bearer " .. token,
          ["content-type"] = "application/json",
        }
      end,
      get_url = function(opts)
        if opts.agent then
          return "https://api.custom.com/agents/" .. opts.agent
        end
        return "https://api.custom.com/chat"
      end,
      prepare_input = function(inputs, opts, model)
        return {
          messages = inputs,
          temperature = opts.temperature,
          model = opts.model,
          stream = true
        }
      end,

      -- Optional fields
      disabled = false,
      embeddings = "copilot_embeddings", -- Use copilot for embeddings
      get_models = function(headers)
        -- Return list of available models
        return {
          {
            id = "gpt-4",
            name = "GPT-4",
            version = "1.0",
            tokenizer = "gpt2",
            max_prompt_tokens = 8000,
            max_output_tokens = 2000,
          }
        }
      end,
      get_agents = function(headers)
        -- Return list of available agents
        return {
          {
            id = "agent1",
            name = "My Agent",
            description = "Custom agent"
          }
        }
      end
    }
  }
}
```

## API

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

-- Ask a question and provide custom contexts
chat.ask("Explain how it works.", {
  context = { 'buffers', 'files', 'register:+' },
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

-- Retrieve current chat config
local config = chat.config
print(config.model)

-- Pick a prompt using vim.ui.select
local actions = require("CopilotChat.actions")

-- Pick prompt actions
actions.pick(actions.prompt_actions({
    selection = require("CopilotChat.select").visual,
}))

-- Programmatically set log level
chat.log_level("debug")
```

# Configuration

## Default configuration

Also see [here](/lua/CopilotChat/config.lua):

```lua
{

  -- Shared config starts here (can be passed to functions at runtime and configured via setup function)

  system_prompt = prompts.COPILOT_INSTRUCTIONS, -- System prompt to use (can be specified manually in prompt via /).

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
  history_path = vim.fn.stdpath('data') .. '/copilotchat_history', -- Default path to stored history

  question_header = '# User ', -- Header to use for user questions
  answer_header = '# Copilot ', -- Header to use for AI answers
  error_header = '# Error ', -- Header to use for errors
  separator = '───', -- Separator to use in chat

  -- default providers
  providers = {
    copilot = {
      -- see config.lua for implementation
    },
    github_models = {
      -- see config.lua for implementation
    },
    copilot_embeddings = {
      -- see config.lua for implementation
    },
  }

  -- default contexts
  contexts = {
    buffer = {
      -- see config.lua for implementation
    },
    buffers = {
      -- see config.lua for implementation
    },
    file = {
      -- see config.lua for implementation
    },
    files = {
      -- see config.lua for implementation
    },
    git = {
      -- see config.lua for implementation
    },
    url = {
      -- see config.lua for implementation
    },
    register = {
      -- see config.lua for implementation
    },
    quickfix = {
      -- see config.lua for implementation
    },
  },

  -- default prompts
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

## Customizing buffers

You can set local options for the buffers that are created by this plugin, `copilot-chat`, `copilot-diff`, `copilot-overlay`:

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

# Tips

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

[![chat-with-buffer](https://i.gyazo.com/9b8cbf1d78a19f326282a6520bc9aab0.gif)](https://gyazo.com/9b8cbf1d78a19f326282a6520bc9aab0)

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

![telescope-integration](https://github.com/CopilotC-Nvim/CopilotChat.nvim/assets/5115805/14360883-7535-4ee3-aca1-79f6c39f626b)

</details>

<details>
<summary>fzf-lua integration</summary>

Requires [fzf-lua](https://github.com/ibhagwan/fzf-lua) plugin to be installed.

```lua
-- lazy.nvim keys

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

![fzf-lua-integration](https://github.com/CopilotC-Nvim/CopilotChat.nvim/assets/5115805/743455bb-9517-48a8-a7a1-81215dc3b747)

</details>

<details>
<summary>snacks.nvim integration</summary>

Requires [snacks.nvim](https://github.com/folke/snacks.nvim) plugin to be installed and the [picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md) to be configured.

```lua
-- lazy.nvim keys

  -- Show prompts actions with snacks.nvim picker
  {
    "<leader>ccp",
    function()
      local actions = require("CopilotChat.actions")
      require("CopilotChat.integrations.snacks").pick(actions.prompt_actions())
    end,
    desc = "CopilotChat - Prompt actions",
  },
```

</details>

<details>
<summary>render-markdown integration</summary>

Requires [render-markdown](https://github.com/MeanderingProgrammer/render-markdown.nvim) plugin to be installed.

```lua
-- Registers copilot-chat filetype for markdown rendering
require('render-markdown').setup({
  file_types = { 'markdown', 'copilot-chat' },
})

-- You might also want to disable default header highlighting for copilot chat when doing this and set error header style and separator
require('CopilotChat').setup({
  highlight_headers = false,
  separator = '---',
  error_header = '> [!ERROR] Error',
  -- rest of your config
})
```

![render-markdown-integration](https://github.com/user-attachments/assets/d8dc16f8-3f61-43fa-bfb9-83f240ae30e8)

</details>

<details>
<summary>Ask a quick question with Perplexity</summary>

Requires [PerplexityAI Agent](https://github.com/marketplace/perplexityai) to be added to [GitHub](https://github.com/) account.

This sets the `selection = false` to be able to ask generic questions unrelated to current code.

```lua
-- lazy.nvim keys

  -- Ask the Perplexity agent a quick question
  {
    "<leader>ccs",
    function()
      local input = vim.fn.input("Perplexity: ")
      if input ~= "" then
        require("CopilotChat").ask(input, {
          agent = "perplexityai",
          selection = false,
        })
      end
    end,
    desc = "CopilotChat - Perplexity Search",
    mode = { "n", "v" },
  },
```

</details>

# Development

## Installing Pre-commit Tool

For development, you can use the provided Makefile command to install the pre-commit tool:

```bash
make install-pre-commit
```

This will install the pre-commit tool and the pre-commit hooks.

# Contributors

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
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind are welcome!

## Stargazers over time

[![Stargazers over time](https://starchart.cc/CopilotC-Nvim/CopilotChat.nvim.svg)](https://starchart.cc/CopilotC-Nvim/CopilotChat.nvim)
