# Changelog

All notable changes to this project are listed here.
This project follows [Semantic Versioning](https://semver.org).

## [0.3.0] - 2026-10-29

### Added

- An OpenCode older than 2.2.0 is upgraded to it with `opencode upgrade`, before the plugins are installed. A newer OpenCode is left alone, and so is one that was uninstalled with `--uninstall`.
- `--keep-opencode` installs the plugins without upgrading OpenCode.

### Changed

- All three plugins were checked with OpenCode 2.2.0: opencode-ask and opencode-delete open in its TUI, and opencode-lodestar loads in its server. An OpenCode that is too old and can't be upgraded is still refused.

## [0.2.0] - 2026-10-24

### Changed

- `install.sh` installs opencode-lodestar v0.4.0, which adds `/lodestar on` and `/lodestar off`. opencode-ask stays at v0.3.3 and opencode-delete at v0.1.0. All three were checked with OpenCode 2.1.4, and 2.1.2 is still the oldest version it accepts.

## [0.1.0] - 2026-10-21

### Added

- `install.sh` installs opencode-lodestar v0.3.1, opencode-ask v0.3.3, and opencode-delete v0.1.0 with one command, and needs OpenCode 2.1.2 or newer.
- Before installing, it removes every other copy of these plugins: other entries in your settings, clones in OpenCode's plugins folder, and downloaded copies in OpenCode's cache.
- `--only` installs some of the plugins, `--uninstall` removes them, and `--dry-run` shows what would change.

[0.3.0]: https://github.com/dhkimxx/opencode-kit/releases/tag/v0.3.0
[0.2.0]: https://github.com/dhkimxx/opencode-kit/releases/tag/v0.2.0
[0.1.0]: https://github.com/dhkimxx/opencode-kit/releases/tag/v0.1.0
