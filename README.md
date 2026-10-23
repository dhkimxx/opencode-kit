# opencode-kit

One command that installs, updates, or removes my [OpenCode](https://opencode.ai) plugins.

```sh
curl -fsSL https://raw.githubusercontent.com/dhkimxx/opencode-kit/main/install.sh | bash
```

| Plugin | What it does | Release |
| --- | --- | --- |
| [opencode-lodestar](https://github.com/dhkimxx/opencode-lodestar) | Keeps OpenCode on track through compaction: puts your request, the agent's latest steps, and the files it was working on back after each compaction. `/lodestar off` and `/lodestar on` turn it off and on. | v0.4.0 |
| [opencode-ask](https://github.com/dhkimxx/opencode-ask) | Multi-turn side questions with `/ask`, in a full-screen panel that never adds to your conversation. | v0.3.3 |
| [opencode-delete](https://github.com/dhkimxx/opencode-delete) | Deletes the current session with `/delete`, after a confirmation. | v0.1.0 |

## What it does

- **Checks your OpenCode version.** It refuses one older than these releases need, and says how to upgrade. A version newer than the one they were tested with gets a warning, and the install goes ahead.
- **Installs each plugin at a fixed release**, such as `github:dhkimxx/opencode-ask#v0.3.3`, with `opencode plugin add`.
- **Removes every other copy first**, so nothing loads twice:
  - other entries for the same plugin in your settings, such as `github:dhkimxx/opencode-ask` without a release, or an older release;
  - clones in OpenCode's plugins folder, which move to `~/.config/opencode/opencode-kit-backup/`;
  - downloaded copies in OpenCode's cache. OpenCode reuses those when a plugin is added again, even if a newer version exists.

It changes OpenCode's settings only through `opencode plugin add` and `opencode plugin remove`, and leaves other plugins alone, including other people's plugins with the same names.

## Options

Pass options after `bash -s --`:

```sh
# Only some of the plugins
curl -fsSL https://raw.githubusercontent.com/dhkimxx/opencode-kit/main/install.sh | bash -s -- --only lodestar,ask

# See what would change, without changing anything
curl -fsSL https://raw.githubusercontent.com/dhkimxx/opencode-kit/main/install.sh | bash -s -- --dry-run

# Remove the plugins
curl -fsSL https://raw.githubusercontent.com/dhkimxx/opencode-kit/main/install.sh | bash -s -- --uninstall
```

To update, run the install command again.

A running OpenCode picks up the changes within a few seconds. Restart it if a command such as `/ask` is missing.

## Requirements

- OpenCode 2.1.2 or newer. Tested with OpenCode 2.1.4.
- Linux or macOS, with `bash` and `curl`. On Windows, use WSL, or install each plugin by hand as its README describes.

## Install by hand

Each plugin can still be installed on its own, for example:

```sh
opencode plugin add github:dhkimxx/opencode-ask#v0.3.3
```

Use one form of the name per plugin. OpenCode treats `github:dhkimxx/opencode-ask` and `github:dhkimxx/opencode-ask#v0.3.3` as two plugins, and `opencode plugin remove` only removes the exact name you give it.

## License

[MIT](LICENSE)
