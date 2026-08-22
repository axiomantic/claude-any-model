# Changelog

All notable changes to this project will be documented in this file.

## 1.12.0 (2026-08-21)

### Added

* `./setup.sh sync-sessions` command: two-way merge of session metadata and sidebar groupings between 1P (Regular) and 3P (Gateway) modes. Shows a stats preview and prompts before making changes. Runs automatically as a prompted step during `./setup.sh switch`. Merges by `sessionId` (newer `lastActivityAt` wins on conflict), unions group assignments and starred sessions. Conversation transcripts are already shared via `~/.claude/projects/` and need no sync.

## 1.11.0 (2026-08-21)

### Fixed

* Network sandbox in Gateway mode now works correctly. The Desktop 3P host reads `coworkEgressAllowedHosts` (workspace-level) to build the CLI subprocess sandbox allowlist at spawn time, not `allowedEgressHosts` (profile-level) alone. The gateway profile template and `configure_sandbox_network()` now write both keys.

### Removed

* Desktop Commander MCP install/uninstall support, including the `desktop-commander` CLI command, the post-install prompt, and all related functions. The gateway profile already enables built-in tools (Edit, Write, Read, Bash, Glob, Grep) via `builtinToolPolicy` and `disabledBuiltinTools`, making Desktop Commander unnecessary.
* Failed sandbox workarounds in `~/.claude/settings.json` (`sandbox.network.allowedHosts`, `disallowedTools` list). These were ignored by the 3P host and actively harmful (disabled built-in tools).

## 1.0.0 (2026-08-21)

### Features

* Initial release of Claude OpenRouter Models local gateway proxy.
* Automatic LiteLLM daemon and Claude Desktop 3P inference configuration.
* Live token pricing display in Claude Desktop model picker.
* In-app session migration from 1P to Gateway mode.
* Weekly automated OpenRouter model recommendation scans via GitHub Actions.
