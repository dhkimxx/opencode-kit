# Releasing

## Versions

- Versions follow [Semantic Versioning](https://semver.org).
- Every release is an annotated git tag named `vX.Y.Z`, made on `main`. A tag is never moved or reused.
- `main` is what the install command runs, so it is always ready to release. Work happens on branches and merges into `main` when it is ready.
- A release can be pinned by its tag: `curl -fsSL https://raw.githubusercontent.com/dhkimxx/opencode-kit/v0.1.0/install.sh | bash`.

## When a plugin is released

1. In `install.sh`, update the plugin's release in `PLUGINS`. If the new set was tested with another OpenCode version, update `OPENCODE_TESTED`, and `OPENCODE_MIN` if a plugin now needs a newer OpenCode.
2. Update the table and requirements in `README.md`.
3. Release the kit as below. A new plugin release is a minor version of the kit.

## Steps

1. Update `KIT_VERSION` in `install.sh` and add a section for it to `CHANGELOG.md`.
2. Run the tests:

   ```sh
   bash test/test.sh                 # a real OpenCode, in throwaway folders; needs GitHub access
   bash test/compat.sh               # a stand-in OpenCode
   docker run --rm -v "$PWD:/w" -w /w bash:3.2 bash test/compat.sh   # the bash that macOS ships
   ```

3. Commit, for example `Release v0.2.0`, then tag and push:

   ```sh
   git tag -a v0.2.0 -m "v0.2.0"
   git push origin main v0.2.0
   ```

4. The Release workflow checks that the tag matches `KIT_VERSION` and creates a GitHub release with the notes from `CHANGELOG.md`.
