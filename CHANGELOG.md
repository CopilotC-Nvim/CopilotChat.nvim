# Changelog

## [4.4.1](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v4.4.0...v4.4.1) (2025-08-12)


### Bug Fixes

* **chat:** schedule chat initialization after window opens ([#1308](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1308)) ([15eebed](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/15eebed57156c3ae6a6bb6f73692dbf0547ba9e4)), closes [#1307](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1307)
* **prompts:** update tool instructions for system prompt ([#1304](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1304)) ([5e091bf](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/5e091bf1bf11827bec5130edc8d4f87fdd243716))

## [4.4.0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v4.3.1...v4.4.0) (2025-08-09)


### Features

* **completion:** add support for omnifunc and move completion logic to separate module ([1b04ddc](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/1b04ddcfe2d04363a3898998a1005ab2f493dff4))
* **ui:** show assistant reasoning as virtual text ([#1299](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1299)) ([92777fb](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/92777fb98ad4de7496188f1e9de336d16871ac43))


### Bug Fixes

* **chat:** correct block selection logic by cursor ([#1301](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1301)) ([7e027df](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/7e027df6e95b622da25282285e84a9fc3806dcf1))
* **info:** show resource uri instead of name in preview ([#1296](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1296)) ([90c3241](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/90c324177b33aec6d4c2bd5043c26bfc9fbc081f))

## [4.3.1](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v4.3.0...v4.3.1) (2025-08-08)


### Bug Fixes

* **client:** store models cache per provider ([#1291](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1291)) ([ffb6659](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/ffb665919fdafecbfb8dceaf63243d614b50c497))

## [4.3.0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v4.2.0...v4.3.0) (2025-08-08)


### ⚠ BREAKING CHANGES

* **core:** Resource processing and embeddings support have been removed. Any configuration or usage relying on these features will no longer work.

### Features

* **keymap:** switch back to &lt;Tab&gt; for completion, add Copilot conflict note ([#1280](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1280)) ([59f5b43](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/59f5b43cdd3d27ab4e033882179d5cf028cf1302))
* **setup:** trigger CopilotChatLoaded user autocommand ([#1288](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1288)) ([1189e37](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/1189e376fcad629edf6ffd186aa659f114df0271))


### Bug Fixes

* **functions:** do not require tool reference in tool prompt, just tool id ([#1273](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1273)) ([4d11c49](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/4d11c49b7a1afb573a3b09be5e10a78a3d41649d)), closes [#1269](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1269)
* **ui:** prevent italics from breaking glob pattern highlights ([#1274](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1274)) ([93110a5](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/93110a5f289aaed20adbbc13ec803f94dc6c63c6))


### Miscellaneous Chores

* mark next release as 4.3.0 ([#1275](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1275)) ([7576afa](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/7576afad950d4258cc7d455d8d42f7dccac4d19b))


### Code Refactoring

* **core:** remove resource processing and embeddings ([#1203](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1203)) ([f38319f](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/f38319fd8f3a7aaa1f75b78027032f9c07abc425))

## [4.2.0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v4.1.0...v4.2.0) (2025-08-03)


### Features

* **chat:** improve error handling ([#1265](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1265)) ([5c8b457](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/5c8b457d617dd1e533b826ff9f9b76ddf988756d))

## [4.1.0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v4.0.0...v4.1.0) (2025-08-03)


### Features

* **ui:** improve keyword highlights accuracy and performance ([#1260](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1260)) ([0d64e26](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/0d64e267a5aef3bd7d580a2c488bcc8b66d374a4))


### Bug Fixes

* **functions:** do not filter schema enum when entering input ([#1264](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1264)) ([8510f30](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/8510f30ff8c338482e7c8a2a7d102519cc57315f)), closes [#1263](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1263)

## [4.0.0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v3.12.2...v4.0.0) (2025-08-02)


### ⚠ BREAKING CHANGES

* **mappings:** use C-Space as default completion trigger instead of Tab
* **providers:** github_models provider is now disabled by default, enable with `providers.github_models.disabled = false`
* **resources:** intelligent resource processing is now disabled by default, use config.resource_processing: true to reenable
* **context:** Multiple breaking changes due to big refactor:
    - The context API has changed from callback-based input handling to schema-based definitions.
    - config.contexts renamed to config.tools
    - config.context removed, use config.sticky
    - diagnostics moved to separate tool call, selection and buffer calls no longer include them by default
    - gi renamed to gc, now also includes selection
    - filenames renamed to glob
    - files removed (use glob together with tool calling instead, or buffers/quickfix)
    - copilot extension agents removed, tools + mcp servers can replace this feature and maintaining them was pain, they can still be implemented via custom providers anyway
    - actions and integrations action removed as they were deprecated for a while
    - config.questionHeader, config.answerHeader moved to config.headers.user/config.headers.assistant

### Features

* add Windows_NT support in Makefile and dynamic library loading ([#1190](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1190)) ([7559fd2](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/7559fd25928f8f3cf311ff25b95bdc5f9ec736d7))
* **context:** switch from contexts to function calling ([057b8e4](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/057b8e46d955748b1426e7b174d7af3e58f5191b)), closes [#1045](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1045) [#1090](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1090) [#1096](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1096) [#526](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/526)
* display group as kind when listing resources ([#1215](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1215)) ([450fcec](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/450fcecf2f71d0469e9c98f5967252092714ed03))
* **functions:** automatically parse schema from url templates ([#1220](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1220)) ([950fdb6](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/950fdb6ab56754929d4db91c73139b33e645deec))
* **health:** add temp dir writable check ([#1239](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1239)) ([02cf9e5](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/02cf9e52634b3e3d45beb2c4e5bbc17da28aef64))
* **mappings:** use C-Space as default completion trigger instead of Tab ([ea41684](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/ea4168476a0fdbd5bf40a4a769d6c1dc998929eb))
* **prompts:** add configurable response language ([#1246](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1246)) ([ced388c](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/ced388c97b313ea235809824ed501970b155e59f)), closes [#1086](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1086)
* **providers:** add info output to panel for copilot with stats ([#1229](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1229)) ([1713ce6](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/1713ce6c8ec700a7833236a8dadfae8a0742b14d))
* **providers:** new github models api, in-built authorization without copilot.vim dep ([#1218](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1218)) ([9c4501e](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/9c4501e7ae92020f2d9b828086016ee70e7fa52c)), closes [#1140](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1140)
* **providers:** prioritize gh clie auth if available for github models ([#1240](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1240)) ([01d38b2](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/01d38b27ea2183302c743dac09b27611d09d7591))
* **resources:** add option to enable resource processing ([#1202](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1202)) ([6ac77aa](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/6ac77aaa68a0ce7fe3c8c41622ab1986f8f6d2c7))
* **ui:** add window.blend option for controllin float transparency ([#1227](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1227)) ([a01bbd6](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/a01bbd6779f4bee23c29ebcfe0d2f5fa5664b5bf)), closes [#1126](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1126)
* **ui:** highlight copilotchat keywords ([#1225](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1225)) ([8071a69](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/8071a6979b5569ce03f7f4d7192814da4c2d4e0b))
* **ui:** improve chat responsiveness by starting spinner early ([#1205](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1205)) ([9d9b280](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/9d9b2809e1240f9525752ae145799b88d22cd7af))


### Bug Fixes

* add back sticky loading on opening window ([#1210](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1210)) ([1d6911f](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/1d6911fef13952c9b56347485f090baeff77a7e4))
* **chat:** do not allow sending empty prompt ([#1245](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1245)) ([c3d0048](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/c3d00484c42065a883db0fb859c686e277012d6c)), closes [#1189](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1189)
* **chat:** handle empty prompt and tools before ask ([#1258](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1258)) ([bad83db](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/bad83db89bb3d813be62dd1b2767406ac3c96e4c))
* **chat:** handle skipped tool calls with explicit error result ([#1259](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1259)) ([936426a](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/936426a500d2f0da25f7d3f065e07450ac851c66))
* **chat:** highlight keywords only in user messages ([#1236](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1236)) ([425ff0c](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/425ff0c48906a94ca522f6d2e98e4b39057e4fd4))
* **chat:** improve how sticky prompts are stored and parsed ([#1233](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1233)) ([82be513](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/82be513c07a27f55860d55144c54040d1c93cf2a))
* **chat:** properly replace all message data when replacing message ([#1244](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1244)) ([d1d155e](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/d1d155e50193e28a3ec00f8e21d6f11445f96ea1))
* **chat:** properly reset modifiable after modifying it ([#1234](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1234)) ([fc93d1c](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/fc93d1c535bf9538a0a036f118b1034930ee5eb9))
* **chat:** show messages in overlay ([#1237](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1237)) ([1a17534](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/1a17534c17e6ae9f5417df08b8c0eec434c47875))
* check for explicit uri input properly ([#1214](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1214)) ([b738fb4](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/b738fb40de3a4bcbb835b8ff6ab2d171acc5d2dd))
* **files:** use also plenary filetype on top of vim.filetype.match ([#1250](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1250)) ([9fd068f](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/9fd068f5d6a0ca00fc739a98f29125cb577b2dfa)), closes [#1249](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1249)
* **functions:** change neovim://buffer to just buffer:// to avoid conflicts ([#1252](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1252)) ([3509cf0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/3509cf0971c59ba79fbcd618d82910f8567a7929))
* **functions:** if enum returns only 1 choice auto accept it ([#1209](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1209)) ([e632470](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/e632470171cd82a95c2675360120833c159e7ae0))
* **functions:** if schema.properties is empty, do not send schema ([#1211](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1211)) ([8a5cda1](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/8a5cda1d90c4d4756dda39cfd748e52cbcde5a99))
* **functions:** properly allow skipping handling for tools ([#1257](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1257)) ([4d2586b](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/4d2586be38a6dbb07fec5d5f3d3335e973ea0ae1))
* **functions:** properly escape percent signs in uri inputs ([#1212](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1212)) ([d905917](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/d905917a025e4c056db28b3082dd474475bad8cd))
* **functions:** properly filter tool schema from functions ([#1243](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1243)) ([f7a3228](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/f7a3228f155d0533197ac79b0e08582e504d0399))
* **functions:** properly handle multiple tool calls at once ([#1198](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1198)) ([dd06166](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/dd0616661505a3c4892ddcdb9517b720a74e59b8))
* **functions:** properly resolve defaults for diagnostics ([#1201](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1201)) ([946069a](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/946069a03946ce35619cbacc3a6757819d096ac5)), closes [#1200](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1200)
* **functions:** properly send prompt as 3rd function resolve param ([#1221](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1221)) ([c03bd1d](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/c03bd1df78b276aa5be2f173c2a31ad273164f15))
* **functions:** use vim.filetype.match for non bulk file reads ([#1226](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1226)) ([b124b94](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/b124b94264140a5d352512b38b7a46d85ee59b24)), closes [#1181](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1181)
* **healthcheck:** chance copilot.vim dependency to optional ([#1219](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1219)) ([d9f4e29](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/d9f4e29c3b46b827443b1832209d22d05c1a69af))
* **prompt:** be more specific when definining what is resource ([#1238](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1238)) ([7c82936](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/7c82936f2126b106af1b1bf0f9ae4d42dd45fcad))
* properly validate source window when retrieving cwd ([#1231](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1231)) ([f53069c](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/f53069c595a3b12bbe8b9b711917f9ef33c22a0a)), closes [#1230](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1230)
* **providers:** do not save copilot.vim token ([#1223](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1223)) ([294bcb6](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/294bcb620ff66183e142cd8a43a7c77d5bc77a16))
* **quickfix:** use new chat messages instead of old chat sections for populating qf ([#1199](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1199)) ([e0df6d1](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/e0df6d1242af29b6262b0eb3e4248568c57c4b3e))
* **ui:** do not allow empty separator ([#1224](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1224)) ([67ed258](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/67ed258c6ccc0a9bfbb6dfcbe3d5e19e22888e73))
* **ui:** fix check for auto follow cursor ([#1222](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1222)) ([1f96d53](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/1f96d53c3f10f176ca25065a23e610d7b4a72b99))
* update sticky reference for commit messages ([#1207](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1207)) ([dab5089](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/dab50896c7e1e80142dd297e6fc75590735b3e9c))
* update to latest lua actions and update README ([#1196](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1196)) ([b4b7f9c](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/b4b7f9c2bb34d43b18dbbe0a889881630e217bc3))
* **utils:** remove temp file after curl request is done ([#1235](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1235)) ([dec3127](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/dec3127e4f373875d7fd50854e221ed8dc0e061f)), closes [#1194](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1194)

## [3.12.2](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v3.12.1...v3.12.2) (2025-07-09)


### Bug Fixes

* [#1153](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1153) use filepath on accept ([#1170](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1170)) ([6d8236f](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/6d8236f83353317de8819cbfac75f791574d6374))

## [3.12.1](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v3.12.0...v3.12.1) (2025-06-16)


### Bug Fixes

* move plenary import into function ([#1162](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1162)) ([5229bc4](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/5229bc48d655247449652d37ba525429ecfcce99))

## [3.12.0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v3.11.1...v3.12.0) (2025-05-09)


### Features

* switch to new default model gpt-4.1 ([5f105cf](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/5f105cf2453585487d3c9ccfe7fd129d3344056c))

## [3.11.1](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v3.11.0...v3.11.1) (2025-04-21)


### Bug Fixes

* **validation:** Ensure If the 	erminal buffer is excluded from #buffers and #buffer ([bc644cd](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/bc644cd97d272e6b46272cbb11147a5891fa08ff))

## [3.11.0](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v3.10.1...v3.11.0) (2025-04-09)


### Features

* add option to disable contexts in prompts ([14c78d2](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/14c78d24e1db88384dc878e870665c3a7ad61a3a))
* change default selection to visual only ([a63031f](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/a63031fc706d4e34e118c46339ae2b5681fab21e)), closes [#1103](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1103)


### Bug Fixes

* set default model to gpt-4o again ([381d5cd](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/381d5cddd25abec595c3c611e96cae2ba61d7ea5)), closes [#1105](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1105)

## [3.10.1](https://github.com/CopilotC-Nvim/CopilotChat.nvim/compare/v3.10.0...v3.10.1) (2025-04-04)


### Bug Fixes

* **client:** update response_text after parsing response ([#1093](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1093)) ([34d1b4f](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/34d1b4fc816401c9bad88b33f71ef943a7dd2396)), closes [#1064](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1064)
* **diff:** normalize filename ([#1095](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1095)) ([81754ea](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/81754ea35253c48459db5712ae60531ea2c5ef75))
* handle invalid context window size in GitHub models ([#1094](https://github.com/CopilotC-Nvim/CopilotChat.nvim/issues/1094)) ([00bf27e](https://github.com/CopilotC-Nvim/CopilotChat.nvim/commit/00bf27ed201b9509105afaac4d5bdcc46ce89f35))

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
