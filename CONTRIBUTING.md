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

### Core

- [init.lua](/lua/CopilotChat/init.lua): Main module. Plugin initialization
  (`setup()`), chat lifecycle (`ask()`, `open()`, `close()`, `toggle()`,
  `reset()`), save/load, and sticky prompt processing.

- [client.lua](/lua/CopilotChat/client.lua): Copilot API client. Handles
  authentication, model listing, streaming requests, and tool call execution.

- [config.lua](/lua/CopilotChat/config.lua): Default configuration schema.

- [config/](/lua/CopilotChat/config/): Sub-configs for
  [functions](/lua/CopilotChat/config/functions.lua),
  [mappings](/lua/CopilotChat/config/mappings.lua),
  [prompts](/lua/CopilotChat/config/prompts.lua), and
  [providers](/lua/CopilotChat/config/providers.lua).

- [constants.lua](/lua/CopilotChat/constants.lua): Shared constants (plugin
  name, roles).

### Chat and UI

- [ui/chat.lua](/lua/CopilotChat/ui/chat.lua): Chat window management.
  Creating, appending to, clearing, opening, closing, and focusing the chat
  window. Handles fold expressions and section parsing.

- [ui/overlay.lua](/lua/CopilotChat/ui/overlay.lua): Overlay buffer used for
  displaying diff previews and other transient content.

- [ui/spinner.lua](/lua/CopilotChat/ui/spinner.lua): Loading spinner indicator
  for the chat window.

### Features

- [prompts.lua](/lua/CopilotChat/prompts.lua): Prompt resolution, custom
  instruction loading, system prompt building, and sticky/resource/tool
  parsing from user input.

- [functions.lua](/lua/CopilotChat/functions.lua): Built-in functions/tools
  exposed to the LLM (e.g., file editing, searching).

- [resources.lua](/lua/CopilotChat/resources.lua): Resource handling for file
  and URL content retrieval with caching.

- [completion.lua](/lua/CopilotChat/completion.lua): Completion source for the
  chat window (`@tools`, `/prompts`, `#resources`, `$models`).

- [select.lua](/lua/CopilotChat/select.lua): Selection strategies for providing
  context (visual selection, buffer, diagnostics, git diff, etc.).

- [tiktoken.lua](/lua/CopilotChat/tiktoken.lua): Token counting via native
  tiktoken library.

- [instructions/](/lua/CopilotChat/instructions/): System prompt templates
  injected into LLM conversations (edit formats, tool use instructions, custom
  instructions wrapper).

### Utilities

- [utils.lua](/lua/CopilotChat/utils.lua): General utility functions.

- [utils/](/lua/CopilotChat/utils/): Utility modules
  [class.lua](/lua/CopilotChat/utils/class.lua) (OOP helper),
  [curl.lua](/lua/CopilotChat/utils/curl.lua) (HTTP requests),
  [diff.lua](/lua/CopilotChat/utils/diff.lua) (unified diff parsing and application),
  [files.lua](/lua/CopilotChat/utils/files.lua) (file I/O and filetype detection),
  [notify.lua](/lua/CopilotChat/utils/notify.lua) (pub/sub notification system for status and message events)
  [orderedmap.lua](/lua/CopilotChat/utils/orderedmap.lua) (insertion-ordered map),
  [stringbuffer.lua](/lua/CopilotChat/utils/stringbuffer.lua) (efficient string concatenation).

### Other

- [health.lua](/lua/CopilotChat/health.lua): `:checkhealth` integration.
  Verifies commands, libraries, and Treesitter parsers.
