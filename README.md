# Copilot Chat for Neovim

## Authentication

It will prompt you with instructions on your first start. If you already have `Copilot.vim` or `Copilot.lua`, it will work automatically.

## Installation

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

1. Yank some code into the unnamed register (`y`)
2. `:CopilotChat What does this code do?`
