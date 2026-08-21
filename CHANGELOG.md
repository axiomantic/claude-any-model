# Changelog

All notable changes to this project will be documented in this file.

## 1.0.0 (2026-08-21)


### Features

* add automated semver releases and changelog with release-please ([12e776d](https://github.com/axiomantic/claude-openrouter-models/commit/12e776d2882ad5f1c1633637a627849087664582))
* add last revisited metadata and weekly github action recommendation evaluator ([0ea61b0](https://github.com/axiomantic/claude-openrouter-models/commit/0ea61b05422fd8cbec22c603547c1025f6edc64e))
* convert setup.sh to a self-bootstrapping Pymera polyglot ([504d6ff](https://github.com/axiomantic/claude-openrouter-models/commit/504d6ffbc97fbb0a88e9112c5c32630a0cef8d89))
* implement comparative delta evaluation comparing live state against current setup.sh ([61e23ac](https://github.com/axiomantic/claude-openrouter-models/commit/61e23ac1449ba02483ea7e11f403cc1bb4d809d9))
* initial commit for claude-openrouter-models v1.2.0 ([f7eafa2](https://github.com/axiomantic/claude-openrouter-models/commit/f7eafa2bdf0f173c38b856547a7ce49bb87e64d1))
* upgrade recommendation script to use LLM semantic analysis with OpenRouter web search plugin ([2b395d6](https://github.com/axiomantic/claude-openrouter-models/commit/2b395d6ac18b7c4615fc8df61585aef853a464cb))
* use uv for standalone python version management and instant dependencies in polyglot bootstrap ([ec26c37](https://github.com/axiomantic/claude-openrouter-models/commit/ec26c37f87184500ea3f94bf1f9ee74c51e273e8))


### Bug Fixes

* abort cleanly on Ctrl+C (KeyboardInterrupt) without writing config ([2052963](https://github.com/axiomantic/claude-openrouter-models/commit/2052963b5017699da727e6b2c91a158c93c70456))
* dynamically select online evaluator models from live catalog with fallbacks and detailed error reporting ([7841fe3](https://github.com/axiomantic/claude-openrouter-models/commit/7841fe36bfb8c73ddd7daf51e874f81fe3d8276c))
* encapsulate commands in functions to resolve local scoping error ([4733a93](https://github.com/axiomantic/claude-openrouter-models/commit/4733a93adbbce9daec086b4c456188f4b4d80436))
* ensure 100% standalone curl one-liner compatibility and sync embedded python script ([9ab5409](https://github.com/axiomantic/claude-openrouter-models/commit/9ab540915c0c839511e255fad30f482a9992e181))
* use direct launchctl list without pipefail to prevent SIGPIPE false negative ([1001643](https://github.com/axiomantic/claude-openrouter-models/commit/10016432474b379876061ab57714bc95bc1aa239))

## 1.0.0 (2026-08-21)

### Features

* Initial release of Claude OpenRouter Models local gateway proxy.
* Automatic LiteLLM daemon and Claude Desktop 3P inference configuration.
* Live token pricing display in Claude Desktop model picker.
* In-app session migration from 1P to Gateway mode.
* Weekly automated OpenRouter model recommendation scans via GitHub Actions.
