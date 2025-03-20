# Changelog

## [4.0.0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v3.9.1...v4.0.0) (2025-03-20)


### ⚠ BREAKING CHANGES

* **context:** move cwd handling to source object
* **search:** Due to previous incorrect glob handling, .lua patterns etc need to be specified as *.lua
* chat.complete_items() is now async instead of using callback
* centralize sticky prompt and selection handling

### Features

* add additional binary file types to scan exclusions ([e71db6d](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/e71db6d734c12e7c16e198eb9b2a870fd952c955))
* add context provider command helpers to prompt ([9b57765](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/9b57765f31ca7e47a6a9fd8bb21a931821c98015))
* add conversation memory summarization ([4e23f17](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/4e23f171afd0667860537ae29d3708678114fd45))
* add description field to prompt items ([41cb9d5](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/41cb9d52ea26c4600424db6fe9b20c4e40545d5d))
* add remember_as_sticky config option ([73fb30e](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/73fb30e4f159b336221671bbd26dc20d9d17f270))
* allow diff accept to jump buffers like jump_to_diff ([19d66ff](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/19d66ff92baab099cc5617f42b46a2b0d4d1cde8))
* allow per-chat selection configurations ([a94c0ff](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/a94c0ff7e7400232d2ffb5bc2113cdd4c327d26a))
* at least open chat when :CopilotChat input is empty ([ccde7a5](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/ccde7a50e8e35588caefd9165c152952f4c8c64e))
* **chat:** add multi-diff support ([158d35e](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/158d35e78d11827cd6168dc1f36aa7c6a5470c68))
* **chat:** add streaming callback support ([a489769](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/a489769f6943f51c081126ae7f5e5bce6be4dc4e))
* **context:** add system context for shell command output ([3e1ddc7](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/3e1ddc7bc311e68590c2ffde0f06d740f4e4acce))
* **context:** improve context help and code block handling ([99bd159](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/99bd1591ae1dfd48d2c3b69247193e6f9cc0ba39))
* **context:** improve context provider help text ([1e5640b](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/1e5640b9b0624a8d1c550524074b4ef1151a4c3b))
* **context:** improve similarity ranking algorithms ([3e99278](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/3e992785cba52a0038a3861ffc7b63d7e9335572))
* **context:** improve system command usage guidelines ([beb609d](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/beb609dfcd254a2d7506973fa4ab1c89f6836cf8))
* **debug:** add history info to debug output ([91d02ad](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/91d02ad6b2a5611aef7d2c20bbe89d516eb47f0d))
* detect .h files as c filetype ([#1044](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1044)) ([b8911c6](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/b8911c6da0d69f83fac46f613344fe9bbc6f670c)), closes [#1043](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1043)
* expose source buffer API and support disabling mappings ([b0893ff](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/b0893fff5f2d3b22155f3113381a614fd4f65a8a))
* improve context provider completion display ([382c4cf](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/382c4cfc39252e7a2b75ceb00abd73a4f14e7e80))
* improve default file scanning arguments ([495c8bd](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/495c8bdd035d9aa62679b9afdb2ecd61897b2771))
* mark async functions with annotations ([7739880](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/773988055609930480df9cfafc3979b476273e79))
* **search:** use ripgrep when available for file scanning ([#953](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/953)) ([1c450db](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/1c450dbc4baa09c38b72a5bd72aa2ea2ad5e6d78))
* send diagnostics with buffer context as well ([7ba905e](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/7ba905eefb9f42ac7de20607b29f54b922750de8))
* show source information in chat info panel ([f17a7d9](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/f17a7d9541881a32a8773c9ebddd30a1109177ba))
* support noselect completeopt setting ([c546d8f](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/c546d8fef5631ed7b9ee21d5f4f75b05c4575f4d))
* **system:** improve system command context error handling ([d88b0f2](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/d88b0f2cc4006baa39de2a1af89e2275c247d8e3))
* use version map again for resolving all copilot models ([0de6faf](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/0de6faf23859636271f7ed4d87abf81c5c4e59a1))
* util method to add sticky prompt to chat ([e72cedc](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/e72cedc5687606d617ec85233061c6f750156b97)), closes [#937](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/937)
* **utils:** add binary file filtering in directory scans ([b9c2b93](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/b9c2b9370409bc8b9cfeafbbd8697a7aaf5aab0a))


### Bug Fixes

* add back uuid ([908b53d](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/908b53d0ac99e47b384f772f28a76949537676e8))
* add error handling for context resolution ([5013b09](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/5013b09970178eae3776b2d0e8ed0640272f9238))
* add null check for API response ([#1039](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1039)) ([853ace7](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/853ace7cef74bae250600218ac986e3a7f35af0e))
* allow using system prompt name as string ([4e36f4e](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/4e36f4e03108a4c4a0f849d709afb54359481888))
* clear memory when resetting the client ([418bf5f](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/418bf5f9e74d905b582121036b732a753aa8746f))
* correct history storage in client ([61c5917](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/61c5917471b37ae2dee2487ba2803f062e746e03))
* disable auto-completion without proper completeopt ([e4938f8](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/e4938f818ced9f59a6da4879b9deeaa94086d048))
* eliminate reference duplication with ordered map ([67b9165](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/67b9165ee92cea274fa8648eb1995317264e1a87))
* **error-handling:** simplify error handling conditions ([6bd7dd4](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/6bd7dd48966f3fa97e3b930771ad24390c2c1843))
* filter nil values from modified array ([14f15e6](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/14f15e64d1d0ebb2213f94405f39ef476a4df07f))
* glob_to_regex recursion matching ([b3ebb0c](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/b3ebb0ca2a0b2030eef37f603ab2b07eee2837d6))
* guard against auth and API failures ([f5202ce](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/f5202ce159087c8c0e2044b5604e6ec5c2e2c30f))
* handle cancelled jobs in CopilotChat ([6ee2936](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/6ee29363d6989de5ee688539bc46d893b1d52067))
* handle file listing limit properly ([ba59c71](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/ba59c71ba891a206a1ccaa98873d4037eb45d62f))
* handle treesitter parsing in fast events ([173a6a8](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/173a6a869bd14748209c948f4a3f2e8fbb0cccee))
* ignore SSE comments in parsing stream response ([3ba4a64](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/3ba4a641f5fbc00e0515be19a275521500f3d65f)), closes [#944](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/944)
* improve buffer handling in diff view ([4f1516b](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/4f1516bc7672ebf2b33777f3e5c76603b1601021))
* improve error logging for failed context resolution ([078ce41](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/078ce415fd4efb6ab0ae353ef04a50ea6018c0ae))
* improve handling of empty responses ([e00fc6b](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/e00fc6b8cf00c0261d0f676de31642d4f08e2c19))
* improve headless mode handling in callbacks ([#1027](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1027)) ([fb64c65](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/fb64c65734aa703f86ba76d2a578e03567c648d7)), closes [#1026](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1026)
* improve history updates safety ([e33c777](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/e33c777cd3dbf3d4fcc9ce2faae6ececd95f4e8f))
* improve source buffer selection for headless mode ([f2205ec](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/f2205ec226248049286f8c718308120325a39c5d))
* make embeddings optional ([f746257](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/f74625727cb53d1f3bc5d1ff83e9b35f445c4545))
* make second part of line matching in diffs optional ([003d2dc](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/003d2dcfc94ab64cd40899dc31852ce0749f296b))
* manually trigger BufEnter when restoring buffers ([648d936](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/648d936328e6f9babb44a560c6a56f91ca9fcce2))
* properly merge selection configuration ([b369d1d](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/b369d1d1af04db7039aa93d33a272d63977eaddd))
* properly split chat horizonatally/vertically when existing splits are open ([82708c1](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/82708c152ca8b398646dfd1bc125abab576e47d2))
* **readme:** remove Tab mapping in normal mode for chat ([aaf86a9](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/aaf86a992318ab4f4fa3bc6500a95879191ad2af))
* remove debug print statements ([5ea7845](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/5ea7845ef77164192a0d0ca2c6bd3aad85b202a1))
* remove requirement for popup in completeopt ([88e3518](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/88e35185e569716141e6431704430e8ea9e8f83c))
* remove unnecessary package-name parameter ([28cd256](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/28cd256c4210819d7413a882f19c01152dbde570))
* reset diagnostics when stopping Copilot Chat ([4759cfc](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/4759cfc2dc373ebe1adb79e3fd7132c1beb6bfd7))
* update reference handling in selection messages ([1f91783](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/1f91783fdf7dcea25c04dffc8e856ccb7a2db13f))
* use ipairs when iterating over resolved embeddings ([96f2380](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/96f23809efdcc99b5eb1c8a8ee498de5e53bc944))
* **utils:** optimize return to normal mode function ([621a1c8](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/621a1c8aecf31db00e855016ffca62bf08d86a09))
* **window:** respect &splitbelow and &splitright ([#1031](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1031)) ([4843ad0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/4843ad02614e8e61ac68815369093e3528998777))


### Performance Improvements

* **client:** optimize buffer handling for responses ([5e09dd9](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/5e09dd97dcda539e3f56f08982d63551bb4e5b73))
* **context:** add async treesitter parsing support ([417cedf](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/417cedf27ea164f92c8ab7656905d4ef631e8e91))
* lower big file threshold for better performance ([132befc](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/132befc8f533a67ddbd4b40297f864397664670f))


### Code Refactoring

* centralize sticky prompt and selection handling ([a1de0aa](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/a1de0aaa366d1e7ff4d88483732454b6a398bec3))
* **context:** move cwd handling to source object ([6482837](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/6482837ffbfd6be9a55ea78b916ef3b992816c06))

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
