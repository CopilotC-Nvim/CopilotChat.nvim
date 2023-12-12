# Copilot Chat for Neovim

## Authentication
```
export COPILOT_TOKEN="gho_..."
```
The process to obtain a COPILOT_TOKEN is still being investigated.


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
