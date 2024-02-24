# Changelog

## [1.9.0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v1.8.0...v1.9.0) (2024-02-24)


### Features

* Add support for clear_chat_on_new_prompt config option ([7dc8771](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/7dc877196296d1f2515ea1c24d0e7d3d4cb8d3b4))


### Bug Fixes

* enable vim diagnostics after finish the conversation ([a0a5a2a](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/a0a5a2a9ae0edf79cdf05620fcead7d59575d306)), closes [#72](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/72)


### Reverts

* add CopilotPlugin back ([713ca00](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/713ca00ef29a56c4c132809f07ea49a63ca8d492))

## [1.8.0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v1.7.1...v1.8.0) (2024-02-23)


### Features

* New Command so that CopilotChat reads from current in-focus buffer when answering questions ([#67](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/67)) ([57226f2](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/57226f29ddd7912cd2bdaa3e4b019c920b2f72b6))

## [1.7.1](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v1.7.0...v1.7.1) (2024-02-20)


### Bug Fixes

* set default temperature and validate temperature value ([8ff6db6](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/8ff6db68eb00f739546db9954e8910f9c6c683e7))

## [1.7.0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v1.6.2...v1.7.0) (2024-02-20)


### Features

* add temperature option ([b5db053](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/b5db053ca74ea36d38212d5a67ffae3cfc4e8b7a))


### Bug Fixes

* add check for temperature if empty string ([#60](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/60)) ([b38a4e9](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/b38a4e9af74afb13f54cd346c7fd147018c38f02))

## [1.6.2](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v1.6.1...v1.6.2) (2024-02-20)

### Bug Fixes

- set filetype to markdown for toggle vsplit buffer ([1e250ff](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/1e250ff1d751fc187e220ac596eb745f09e805aa))

## [1.6.1](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v1.6.0...v1.6.1) (2024-02-18)

### Bug Fixes

- **code_actions:** Add check for 'No diagnostics available' in diagnostic prompts ([e46fa23](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/e46fa23fe7c43a29c849fb9b6a1d565d2e0b83f1))

## [1.6.0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v1.5.0...v1.6.0) (2024-02-18)

### Features

- add language settings for copilot answers ([8e40e41](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/8e40e41c5bdabe675b2e54c80347dd85f1a9d550))
- add support for visual mode in show_prompt_actions function ([13dfbba](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/13dfbba39e2202ad6bae5b4806ce7e42f75c94a0))
- disable vim diagnostics on chat buffer for vsplit handler ([fe1808e](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/fe1808e51760c2fa71ca4176551161c73b2f2f73))

### Bug Fixes

- add validation before call FixDiagnostic command ([81c5060](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/81c506027e6a638973e3187dd98fc70cae024719))
- reorder system prompt and language prompt ([0d474a1](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/0d474a14b3bf67469946aa639e3de1a42b016373))

## [1.5.0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v1.4.0...v1.5.0) (2024-02-17)

### Features

- add options to hide system prompts ([98a6191](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/98a61913f4cd798fb042f4b21f6a3e1a457c3959))
- add prompt actions support in Telescope integration ([f124645](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/f124645d4b48df59790c9763687b94cf7dd3f5bf))
- integrate CopilotChat with telescope.nvim for code actions ([0cabac6](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/0cabac6af8c838d4984b766f5d985a04259d3a4d))

## [1.4.0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v1.3.0...v1.4.0) (2024-02-16)

### Features

- add diagnostic troubleshooting command ([0e5eced](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/0e5ecedda4d7a9cc6eeef1424889d8d9550bf4f3))
- add toggle command for vertical split in CopilotChat ([48209d6](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/48209d6b98cb50c9dae59da70ebda351282cf8f7))
- **integration:** set filetype to 'copilot-chat' for support edgy.nvim ([60718ed](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/60718ed6e806fa86fd78cb3bf55a05f1a74b257e))

## [1.3.0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v1.2.0...v1.3.0) (2024-02-14)

### Features

- add reset buffer for CopilotChatReset command ([bf6d29f](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/bf6d29f3bde05c8a2b0f127737af13cc6df73b9a))
- CopilotChatReset command ([528e6b4](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/528e6b4b33737e4863fccdb7ed2c6d7aec4f2029))

### Bug Fixes

- Include more info about refusal reason ([46bdf01](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/46bdf018069072a8a43c468ee1cede45536909a3))

## [1.2.0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v1.1.0...v1.2.0) (2024-02-13)

### Features

- restructure for pynvim 0.4.3 backwards compatibility ([#45](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/45)) ([52350c7](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/52350c78dbcfcb3acabf3478276ad9a87ebbfd26))

## [1.1.0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v1.0.1...v1.1.0) (2024-02-10)

### Features

- **chat_handler:** show extra info only once ([589a453](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/589a4538d648c8723d839ca963a47a6176be3c78))
- Environment variables for proxy (HTTPS_PROXY and ALL_PROXY) ([043e731](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/043e731005278649dbdf1d5866c6e3c7719f1202))
- Proxy support ([19a8088](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/19a8088c171cb956fd553200b77c8dbbe76707b6))

### Bug Fixes

- Wacky indentation in readme ([c5bf963](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/c5bf963f4702a8a94aa97de2e6205796cb381ae5))

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
