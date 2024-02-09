# Changelog

## [1.0.1](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v1.0.0...v1.0.1) (2024-02-08)

### Bug Fixes

- multi-byte languages by manually tracking last_line_col for buf_set_text ([20a4234](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/20a4234a542deef1a128aca4d0dd7e8d429a1f2a))

## 1.0.0 (2024-02-06)

### ⚠ BREAKING CHANGES

- disable extra info as default
- drop new buffer mode

### Features

- add a note for help user to continue the chat ([8a80ee7](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/8a80ee7d3f9d0dcb65b315255d629c2cd8263dac))
- add CCExplain command ([640f361](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/640f361a54be51e7c479257c374d4a26d8fcd31d))
- add CCTests command ([b34a78f](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/b34a78f05ebe65ca093e4dc4b66de9120a681f4c))
- add configuration options for wrap and filetype ([b4c6e76](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/b4c6e760232ec54d4632edef3869e1a05ec61751))
- add CopilotChatDebugInfo command ([#51](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/51)) ([89b6276](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/89b6276e995de2e05ea391a9d1045676737c93bd))
- add CopilotChatToggleLayout ([07988b9](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/07988b95a412756169016e991dabcf190a930c7e))
- add debug flag ([d0dbd4c](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/d0dbd4c6fb9be75ccaa591b050198d40c097f423))
- add health check ([974f14f](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/974f14f0d0978d858cbe0126568f30fd63262cb6))
- add new keymap to get previous user prompt ([6e7e80f](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/6e7e80f118c589a009fa1703a284ad292260e3a0))
- set filetype to markdown and text wrapping ([9b19d51](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/9b19d51deacdf5c958933e99a2e75ebe4c968a9b))
- show chat in markdown format ([9c14152](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/9c141523de12e723b1d72d95760f2daddcecd1d9))
- show date time and additional information on end separator ([#53](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/53)) ([b8d0a9d](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/b8d0a9d0e0824ff3b643a2652202be2a51b37dbc))

### Bug Fixes

- **ci:** generate doc ([6287fd4](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/6287fd452d83d43a739d4c7c7a5524537032fc5d))
- **ci:** generate vimdoc on main branch ([94fb10c](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/94fb10cb65bc32cc0c1d96c93ec2d94c4f5d40eb))
- **ci:** setup release action ([2f1e046](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/2f1e0466af30c26fdcd2b94d331ea4004d32bb07))
- **ci:** skip git hook on vimdoc ([94fb10c](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/94fb10cb65bc32cc0c1d96c93ec2d94c4f5d40eb))
- Close spinner if the buffer does not exist ([#11](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/11)) ([0ea238d](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/0ea238d7be9c7872dd9932a56d3521531b2297db))
- handle get remote plugin path on Windows ([0b917f6](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/0b917f633eaef621d293f344965e9e0545be9a80))
- remove LiteralString, use Any for fixing issue on Python 3.10 ([b68c352](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/b68c3522d03c8ac9a332169c56e725b69a43b07c)), closes [#45](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/45)
