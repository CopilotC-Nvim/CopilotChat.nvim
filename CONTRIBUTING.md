# Contributing to CopilotChat.nvim

## Where do I go from here?

If you've noticed a bug or have a feature request, make sure to check our
[Issues](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues) page to see
if someone else in the community has already created a ticket. If not, go ahead
and make one!

## Fork & create a branch

If this is something you think you can fix, then fork CopilotChat.nvim and
create a branch with a descriptive name.

A good branch name would be (where issue #325 is the ticket you're working on):

```bash
git checkout -b 325-add-japanese-localization
```

Make sure to check [Structure](#Structure) first to understand the project structure.

## Implement your fix or feature

At this point, you're ready to make your changes! Feel free to ask for help;
everyone is a beginner at first. You can also ask in our Discord server, see [README](/README.md).

## Make a Pull Request

At this point, you should switch back to your main branch and make sure it's
up to date with CopilotChat.nvim's main branch:

```bash
git remote add upstream git@github.com:CopilotC-Nvim/CopilotChat.nvim.git
git checkout main
git pull upstream main
```

Then update your feature branch from your local copy of master and push your branch to your GitHub account:

```bash
git checkout 325-add-japanese-localization
git rebase main
git push --set-upstream origin 325-add-japanese-localization
```

Go to the CopilotChat.nvim in your GitHub account, select your branch, and click the "Pull Request" button.

## Structure

![structure.drawio](https://github.com/CopilotC-Nvim/CopilotChat.nvim/assets/5115805/e7517736-0152-47a3-8cb9-36a5dffcb6cc)

### Main components

- [init.lua](/lua/CopilotChat/init.lua): This file initializes Copilot Chat
  plugin. It includes functions for appending to the chat window, showing help,
  completing, getting selection, opening and closing the chat window, asking
  questions to the Copilot model, resetting the chat window, enabling/disabling
  debug, and setting up the plugin.

- [config.lua](/lua/CopilotChat/config.lua): This file contains default
  configuration for Copilot Chat plugin.

- [copilot.lua](/lua/CopilotChat/copilot.lua): This file contains the core
  functionality of the Copilot. It includes functions for generating unique IDs,
  finding configuration paths, authenticating, asking questions to the Copilot,
  generating embeddings, and managing the running job.

- [chat.lua](/lua/CopilotChat/chat.lua): This file manages the chat window. It
  includes functions for creating, validating, appending to, clearing, opening,
  closing, and focusing on the chat window.

- [diff.lua](/lua/CopilotChat/diff.lua): This file manages the diff window. It
  includes functions for creating, validating, showing, and restoring the diff
  window.

- [select.lua](/lua/CopilotChat/select.lua): This file contains functions for
  selecting and processing different types of data such as visual selection,
  unnamed register, whole buffer, current line, diagnostics, and git diff.

- [context.lua](/lua/CopilotChat/context.lua): This file is responsible for
  building an outline for a buffer and finding items for a query. It uses spatial
  distance and relatedness to rank data.

- [actions.lua](/lua/CopilotChat/actions.lua): This file manages the actions
  that can be performed. It includes functions for getting help actions, prompt
  actions, and picking an action from a list of actions using `vim.ui.select`.

- [tiktoken.lua](/lua/CopilotChat/tiktoken.lua): This file manages integration
  with Tiktoken library and is used for counting tokens. It includes functions
  for setting up Tiktoken, checking its availability, encoding prompts, and
  counting prompts.

- [health.lua](/lua/CopilotChat/health.lua): This file checks the health of the
  plugin by checking if commands exist, checking if Lua libraries are installed,
  and checking if a Treesitter parsers are available.

- [spinner.lua](/lua/CopilotChat/spinner.lua): This file manages a spinner that
  is used for indicating loading status in chat window.

- [utils.lua](/lua/CopilotChat/utils.lua): This file contains utility functions
  for creating classes, getting the log file path, checking if the current
  version of Neovim is stable, and joining multiple async functions.

- [debuginfo.lua](/lua/CopilotChat/debuginfo.lua): This file is used for
  creating `:CopilotChatDebugInfo` command.

### Integrations

- [telescope.lua](/lua/CopilotChat/integrations/telescope.lua): This file
  integrates the Telescope plugin with CopilotChat. It includes a function for
  picking an action from a list of actions.

- [fzflua.lua](/lua/CopilotChat/integrations/fzflua.lua): This file integrates
  the fzf-lua plugin with CopilotChat. It includes a function for picking an
  action from a list of actions.
