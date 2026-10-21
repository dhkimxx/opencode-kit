# Changelog

All notable changes to this project are listed here.
This project follows [Semantic Versioning](https://semver.org).

## [0.1.0] - 2026-10-21

### Added

- `install.sh` installs opencode-lodestar v0.3.1, opencode-ask v0.3.3, and opencode-delete v0.1.0 with one command, and needs OpenCode 2.1.2 or newer.
- Before installing, it removes every other copy of these plugins: other entries in your settings, clones in OpenCode's plugins folder, and downloaded copies in OpenCode's cache.
- `--only` installs some of the plugins, `--uninstall` removes them, and `--dry-run` shows what would change.

[0.1.0]: https://github.com/dhkimxx/opencode-kit/releases/tag/v0.1.0
