# Copilot Chat for Neovim

<!-- ALL-CONTRIBUTORS-BADGE:START - Do not remove or modify this section -->

[![All Contributors](https://img.shields.io/badge/all_contributors-13-orange.svg?style=flat-square)](#contributors-)

<!-- ALL-CONTRIBUTORS-BADGE:END -->

> [!NOTE]
> A new command, `CopilotChatInPlace` has been introduced. It functions like the ChatGPT plugin. Please run ":UpdateRemotePlugins" command and restart Neovim before starting a chat with Copilot. To stay updated on our roadmap, please join our [Discord](https://discord.gg/vy6hJsTWaZ) community.

## Prerequisites

Ensure you have the following installed:

- Python 3.10 or later
- Enable `python3 provider` in Neovim. Testing by run `:echo has('python3')` in Neovim. If it returns `1`, then `python3 provider` is enabled.

## Authentication

It will prompt you with instructions on your first start. If you already have `Copilot.vim` or `Copilot.lua`, it will work automatically.

## Installation

### Lazy.nvim

1. `pip install python-dotenv requests pynvim==0.5.0 prompt-toolkit`
2. `pip install tiktoken` (optional for displaying prompt token counts)
3. Put it in your lazy setup

```lua
return {
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    opts = {
      show_help = "yes", -- Show help text for CopilotChatInPlace, default: yes
      debug = false, -- Enable or disable debug mode, the log file will be in ~/.local/state/nvim/CopilotChat.nvim.log
      disable_extra_info = 'no', -- Disable extra information (e.g: system prompt) in the response.
      language = "English" -- Copilot answer language settings when using default prompts. Default language is English.
      -- proxy = "socks5://127.0.0.1:3000", -- Proxies requests via https or socks.
      -- temperature = 0.1,
    },
    build = function()
      vim.notify("Please update the remote plugins by running ':UpdateRemotePlugins', then restart Neovim.")
    end,
    event = "VeryLazy",
    keys = {
      { "<leader>cce", "<cmd>CopilotChatExplain<cr>", desc = "CopilotChat - Explain code" },
      { "<leader>cct", "<cmd>CopilotChatTests<cr>", desc = "CopilotChat - Generate tests" },
      {
        "<leader>ccT",
        "<cmd>CopilotChatVsplitToggle<cr>",
        desc = "CopilotChat - Toggle Vsplit", -- Toggle vertical split
      },
      {
        "<leader>ccv",
        ":CopilotChatVisual",
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
      {
        "<leader>ccr",
        "<cmd>CopilotChatReset<cr>", -- Reset chat history and clear buffer.
        desc = "CopilotChat - Reset chat history and clear buffer",
      }
    },
  },
}
```

4. Run command `:UpdateRemotePlugins`, then inspect the file `~/.local/share/nvim/rplugin.vim` for additional details. You will notice that the commands have been registered.

For example:

```vim
" python3 plugins
call remote#host#RegisterPlugin('python3', '/Users/huynhdung/.local/share/nvim/lazy/CopilotChat.nvim/rplugin/python3/CopilotChat', [
      \ {'sync': v:false, 'name': 'CopilotChat', 'type': 'command', 'opts': {'nargs': '1'}},
      \ {'sync': v:false, 'name': 'CopilotChatReset', 'type': 'command', 'opts': {}},
      \ {'sync': v:false, 'name': 'CopilotChatVisual', 'type': 'command', 'opts': {'nargs': '1', 'range': ''}},
      \ {'sync': v:false, 'name': 'CopilotChatVsplitToggle', 'type': 'command', 'opts': {}},
      \ {'sync': v:false, 'name': 'CopilotChatInPlace', 'type': 'command', 'opts': {'nargs': '*', 'range': ''}},
      \ {'sync': v:false, 'name': 'CopilotChatAutocmd', 'type': 'command', 'opts': {'nargs': '*'}},
      \ {'sync': v:false, 'name': 'CopilotChatMapping', 'type': 'command', 'opts': {'nargs': '*'}},
     \ ])
```

5. Restart `neovim`

### Vim-Plug

Similar to the lazy setup, you can use the following configuration:

```lua
Plug 'CopilotC-Nvim/CopilotChat.nvim'
call plug#end()

local copilot_chat = require("CopilotChat")
copilot_chat.setup({
  debug = true,
  show_help = "yes",
  prompts = {
    Explain = "Explain how it works by Japanese language.",
    Review = "Review the following code and provide concise suggestions.",
    Tests = "Briefly explain how the selected code works, then generate unit tests.",
    Refactor = "Refactor the code to improve clarity and readability.",
  },
  build = function()
    vim.notify("Please update the remote plugins by running ':UpdateRemotePlugins', then restart Neovim.")
  end,
  event = "VeryLazy",
})

nnoremap <leader>cce <cmd>CopilotChatExplain<cr>
nnoremap <leader>cct <cmd>CopilotChatTests<cr>
xnoremap <leader>ccv :CopilotChatVisual<cr>
xnoremap <leader>ccx :CopilotChatInPlace<cr>
```

Credit to @treyhunner and @nekowasabi for the [configuration](https://github.com/CopilotC-Nvim/CopilotChat.nvim/discussions/46).

### Manual

1. Put the files in the right place

```
$ git clone https://github.com/CopilotC-Nvim/CopilotChat.nvim
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
  show_help = 'yes', -- Show help text for CopilotChatInPlace
  disable_extra_info = 'no', -- Disable extra information in the response
  hide_system_prompt = 'yes', -- Hide system prompts in the response
  proxy = '', -- Proxies requests via https or socks
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
      show_help = "yes",
      prompts = {
        Explain = "Explain how it works.",
        Review = "Review the following code and provide concise suggestions.",
        Tests = "Briefly explain how the selected code works, then generate unit tests.",
        Refactor = "Refactor the code to improve clarity and readability.",
      },
    },
    build = function()
      vim.notify("Please update the remote plugins by running ':UpdateRemotePlugins', then restart Neovim.")
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

For further reference, you can view @jellydn's [configuration](https://github.com/jellydn/lazy-nvim-ide/blob/main/lua/plugins/extras/copilot-chat.lua).

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

### Troubleshoot and Fix Diagnostic

1. Place your cursor on the line with the diagnostic message.
2. Run the command `:CopilotChatFixDiagnostic`.

[![Fix diagnostic](https://i.gyazo.com/4aff3fdbc5c3eee59cb68939546fa2be.gif)](https://gyazo.com/4aff3fdbc5c3eee59cb68939546fa2be)

### Token count & Fold with visual mode

1. Select some code using visual mode.
2. Run the command `:CopilotChatVisual` with your question.

[![Fold Demo](https://i.gyazo.com/766fb3b6ffeb697e650fc839882822a8.gif)](https://gyazo.com/766fb3b6ffeb697e650fc839882822a8)

### In-place Chat Popup

1. Select some code using visual mode.
2. Run the command `:CopilotChatInPlace` and type your prompt. For example, `What does this code do?`
3. Press `Enter` to send your question to Github Copilot.
4. Press `q` to quit. There is help text at the bottom of the screen. You can also press `?` to toggle the help text.

[![In-place Demo](https://i.gyazo.com/4a5badaa109cd483c1fc23d296325cb0.gif)](https://gyazo.com/4a5badaa109cd483c1fc23d296325cb0)

### Toggle Vertical Split with `:CopilotChatVsplitToggle`

[![Toggle](https://i.gyazo.com/db5af9e5d88cd2fd09f58968914fa521.gif)](https://gyazo.com/db5af9e5d88cd2fd09f58968914fa521)

## Tips

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

### Integration with `edgy.nvim`

Consider integrating this plugin with [`edgy.nvim`](https://github.com/folke/edgy.nvim). This will allow you to create a chat window on the right side of your screen, occupying 40% of the width, as illustrated below.

```lua
{
  "folke/edgy.nvim",
  event = "VeryLazy",
  opts = {
    -- Refer to my configuration here https://github.com/jellydn/lazy-nvim-ide/blob/main/lua/plugins/extras/edgy.lua
    right = {
      {
        title = "CopilotChat.nvim", -- Title of the window
        ft = "copilot-chat", -- This is custom file type from CopilotChat.nvim
        size = { width = 0.4 }, -- Width of the window
      },
    },
  },
}
```

[![Layout](https://i.gyazo.com/550daf6cbb729027ca9bd703c21af53e.png)](https://gyazo.com/550daf6cbb729027ca9bd703c21af53e)

### Debugging with `:messages` and `:CopilotChatDebugInfo`

If you encounter any issues, you can run the command `:messages` to inspect the log. You can also run the command `:CopilotChatDebugInfo` to inspect the debug information.

[![Debug Info](https://i.gyazo.com/bf00e700bcee1b77bcbf7b516b552521.gif)](https://gyazo.com/bf00e700bcee1b77bcbf7b516b552521)

### How to setup with `which-key.nvim`

A special thanks to @ecosse3 for the configuration of [which-key](https://github.com/jellydn/CopilotChat.nvim/issues/30).

```lua
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    event = "VeryLazy",
    opts = {
      prompts = {
        Explain = "Explain how it works.",
        Review = "Review the following code and provide concise suggestions.",
        Tests = "Briefly explain how the selected code works, then generate unit tests.",
        Refactor = "Refactor the code to improve clarity and readability.",
      },
    },
    build = function()
      vim.notify("Please update the remote plugins by running ':UpdateRemotePlugins', then restart Neovim.")
    end,
    config = function()
      local present, wk = pcall(require, "which-key")
      if not present then
        return
      end

      wk.register({
        c = {
          c = {
            name = "Copilot Chat",
          }
        }
      }, {
        mode = "n",
        prefix = "<leader>",
        silent = true,
        noremap = true,
        nowait = false,
      })
    end,
    keys = {
      { "<leader>ccc", ":CopilotChat ",                desc = "CopilotChat - Prompt" },
      { "<leader>cce", ":CopilotChatExplain ",         desc = "CopilotChat - Explain code" },
      { "<leader>cct", "<cmd>CopilotChatTests<cr>",    desc = "CopilotChat - Generate tests" },
      { "<leader>ccr", "<cmd>CopilotChatReview<cr>",   desc = "CopilotChat - Review code" },
      { "<leader>ccR", "<cmd>CopilotChatRefactor<cr>", desc = "CopilotChat - Refactor code" },
    }
  },
```

### Create a simple input for CopilotChat

Follow the example below to create a simple input for CopilotChat.

```lua
-- Create input for CopilotChat
  {
    "<leader>cci",
    function()
      local input = vim.fn.input("Ask Copilot: ")
      if input ~= "" then
        vim.cmd("CopilotChat " .. input)
      end
    end,
    desc = "CopilotChat - Ask input",
  },
```

### Add same keybinds in both visual and normal mode

```lua
    {
      "CopilotC-Nvim/CopilotChat.nvim",
      keys =
	function()
		local keybinds={
			--add your custom keybinds here
		}
		-- change prompt and keybinds as per your need
		local my_prompts = {
			{prompt = "In Neovim.",desc = "Neovim",key = "n"},
			{prompt = "Help with this",desc = "Help",key = "h"},
			{prompt = "Simplify and improve readablilty",desc = "Simplify",key = "s"},
			{prompt = "Optimize the code to improve performance and readablilty.",desc = "Optimize",key = "o"},
			{prompt = "Find possible errors and fix them for me",desc = "Fix",key = "f"},
			{prompt = "Explain in detail",desc = "Explain",key = "e"},
			{prompt = "Write a shell script",desc = "Shell",key = "S"},
		}
		-- you can change <leader>cc to your desired keybind prefix
		for _,v in pairs(my_prompts) do
			table.insert(keybinds,{ "<leader>cc"..v.key, ":CopilotChatVisual "..v.prompt.."<cr>", mode = "x", desc = "CopilotChat - "..v.desc })
			table.insert(keybinds,{ "<leader>cc"..v.key, "<cmd>CopilotChat "..v.prompt.."<cr>", desc = "CopilotChat - "..v.desc })
		end
		return keybinds
	end,
    },
```

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
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

This project follows the [all-contributors](https://github.com/all-contributors/all-contributors) specification. Contributions of any kind are welcome!

### Stargazers over time

[![Stargazers over time](https://starchart.cc/CopilotC-Nvim/CopilotChat.nvim.svg)](https://starchart.cc/CopilotC-Nvim/CopilotChat.nvim)
