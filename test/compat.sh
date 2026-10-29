#!/usr/bin/env bash
# Runs install.sh with a stand-in for OpenCode that only records what it is asked to do, so it runs anywhere,
# including the bash 3.2 that macOS ships: docker run --rm -v "$PWD:/w" -w /w bash:3.2 bash test/compat.sh
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FAILED=0
echo "bash $BASH_VERSION"

# The version lives in a file, so `upgrade` can change it. STUB_UPGRADE=fail makes the upgrade fail.
cat >"$WORK/opencode" <<'EOF'
#!/bin/sh
if [ "$1" = --version ]; then echo "opencode v$(cat "$STUB_STATE")"; exit 0; fi
echo "$*" >>"$STUB_LOG"
if [ "$1" = upgrade ]; then
    [ "${STUB_UPGRADE:-}" = fail ] && { echo "upgrade failed" >&2; exit 1; }
    # The version is the last argument, after any --method.
    for last; do :; done
    echo "$last" >"$STUB_STATE"
fi
EOF
chmod +x "$WORK/opencode"

fresh() {
    rm -rf "${WORK:?}/home"
    mkdir -p "$WORK/home/config/opencode/plugins/opencode-delete" "$WORK/home/cache/opencode/npm"
    cat >"$WORK/home/config/opencode/cli.json" <<'EOF'
{
  "plugins": [
    "github:dhkimxx/opencode-ask",
    { "package": "github:dhkimxx/opencode-ask#v0.3.2", "options": {} },
    "github:someone/opencode-ask",
    "github:dhkimxx/opencode-asking"
  ]
}
EOF
    printf '{ "plugins": ["github:dhkimxx/opencode-lodestar#v0.3.0"] }\n' >"$WORK/home/config/opencode/opencode.json"
    printf '{ "plugins": ["github:dhkimxx/opencode-lodestar"] }\n' >"$WORK/home/config/opencode/config.json"
    printf '{\n  "name": "@dhkimxx/opencode-delete"\n}\n' >"$WORK/home/config/opencode/plugins/opencode-delete/package.json"
    mkdir -p "$WORK/home/cache/opencode/npm/git-opencode-ask-0123456789ab/1/node_modules/@dhkimxx/opencode-ask"
    # Someone else's repo with the same name shares the folder prefix, but not the package inside.
    mkdir -p "$WORK/home/cache/opencode/npm/git-opencode-ask-ba9876543210/1/node_modules/opencode-ask"
    : >"$WORK/log"
}

# STUB_VERSION, set for one call, is the OpenCode version that call sees.
kit() {
    echo "${STUB_VERSION:-2.2.0}" >"$WORK/version"
    env HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home/config" XDG_CACHE_HOME="$WORK/home/cache" \
        OPENCODE_BIN="$WORK/opencode" STUB_LOG="$WORK/log" STUB_STATE="$WORK/version" NO_COLOR=1 "$BASH" "$ROOT/install.sh" "$@" </dev/null
}

check() {
    local what=$1
    shift
    if "$@"; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what" && FAILED=1; fi
}
has() { grep -qF -- "$2" "$1"; }
lacks() { ! grep -qF -- "$2" "$1"; }

echo "install"
fresh
kit >"$WORK/out" 2>&1 || { cat "$WORK/out"; exit 1; }
check "removes the unpinned ask" has "$WORK/log" "plugin remove github:dhkimxx/opencode-ask"
check "removes an entry with options" has "$WORK/log" "plugin remove github:dhkimxx/opencode-ask#v0.3.2"
check "removes the old lodestar" has "$WORK/log" "plugin remove github:dhkimxx/opencode-lodestar#v0.3.0"
check "leaves another owner's repo" lacks "$WORK/log" "someone"
check "leaves a longer name" lacks "$WORK/log" "opencode-asking"
check "installs all three, pinned" has "$WORK/log" "plugin add github:dhkimxx/opencode-delete#v0.1.0"
check "points at config.json, which it can't edit" has "$WORK/out" "config.json also lists opencode-lodestar"
check "moves the clone out of the plugins folder" test ! -e "$WORK/home/config/opencode/plugins/opencode-delete"
check "shows home paths as ~" has "$WORK/out" "moved ~/config/opencode/plugins/opencode-delete"
check "clears our download" test ! -e "$WORK/home/cache/opencode/npm/git-opencode-ask-0123456789ab"
check "keeps someone else's download" test -d "$WORK/home/cache/opencode/npm/git-opencode-ask-ba9876543210"

echo "dry run"
fresh
kit --dry-run --only ask,delete >"$WORK/out" 2>&1 || { cat "$WORK/out"; exit 1; }
check "calls nothing" test ! -s "$WORK/log"
check "keeps the clone" test -e "$WORK/home/config/opencode/plugins/opencode-delete"
check "says what it would do" has "$WORK/out" "would install github:dhkimxx/opencode-ask#v0.3.3"
check "skips lodestar" lacks "$WORK/out" "lodestar"

echo "arguments and versions"
fresh
if kit --only nope >"$WORK/out" 2>&1; then status=0; else status=$?; fi
check "rejects an unknown plugin" test "$status" = 1
if STUB_VERSION=2.1.1 STUB_UPGRADE=fail kit >"$WORK/out" 2>&1; then status=0; else status=$?; fi
check "refuses 2.1.1 when it can't be upgraded" test "$status" = 1
check "and changes nothing" lacks "$WORK/log" "plugin add"
fresh
if STUB_VERSION=2.3.0-beta.1 kit --dry-run >"$WORK/out" 2>&1; then status=0; else status=$?; fi
check "takes a newer pre-release, with a warning" has "$WORK/out" "newer than 2.2.0"
check "and leaves it alone" lacks "$WORK/log" "upgrade"
fresh
if STUB_VERSION=2.1.2-beta.3 STUB_UPGRADE=fail kit --dry-run >"$WORK/out" 2>&1; then status=0; else status=$?; fi
check "a dry run only says what it would upgrade" has "$WORK/out" "would upgrade OpenCode from 2.1.2-beta.3 to 2.2.0"

echo "upgrading OpenCode"
fresh
STUB_VERSION=2.1.2 kit >"$WORK/out" 2>&1 || { cat "$WORK/out"; exit 1; }
check "upgrades an older OpenCode to the tested one" has "$WORK/log" "upgrade 2.2.0"
check "before it installs the plugins" test "$(grep -n -m1 '^upgrade' "$WORK/log" | cut -d: -f1)" -lt "$(grep -n -m1 'plugin add' "$WORK/log" | cut -d: -f1)"
check "says so" has "$WORK/out" "Upgrading OpenCode from 2.1.2 to 2.2.0"
fresh
kit >"$WORK/out" 2>&1 || { cat "$WORK/out"; exit 1; }
check "leaves the tested version alone" lacks "$WORK/log" "upgrade"
fresh
mkdir -p "$WORK/home/.opencode/bin" && cp "$WORK/opencode" "$WORK/home/.opencode/bin/opencode"
echo 2.1.2 >"$WORK/version"
env HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home/config" XDG_CACHE_HOME="$WORK/home/cache" OPENCODE_BIN="$WORK/home/.opencode/bin/opencode" \
    STUB_LOG="$WORK/log" STUB_STATE="$WORK/version" NO_COLOR=1 "$BASH" "$ROOT/install.sh" --only delete </dev/null >"$WORK/out" 2>&1 || { cat "$WORK/out"; exit 1; }
check "names the curl method for an OpenCode the install script put in ~/.opencode" has "$WORK/log" "upgrade --method curl 2.2.0"
fresh
STUB_VERSION=2.1.2 kit --keep-opencode >"$WORK/out" 2>&1 || { cat "$WORK/out"; exit 1; }
check "--keep-opencode doesn't upgrade" lacks "$WORK/log" "upgrade"
check "and still installs" has "$WORK/log" "plugin add"
fresh
STUB_VERSION=2.1.2 kit --uninstall >"$WORK/out" 2>&1 || { cat "$WORK/out"; exit 1; }
check "--uninstall doesn't upgrade" lacks "$WORK/log" "upgrade"
fresh
STUB_VERSION=2.1.3 STUB_UPGRADE=fail kit >"$WORK/out" 2>&1 || { cat "$WORK/out"; exit 1; }
check "a failed upgrade of a usable OpenCode only warns" has "$WORK/out" "could not upgrade OpenCode to 2.2.0"
check "and installs on it" has "$WORK/log" "plugin add github:dhkimxx/opencode-lodestar"

if [ "$FAILED" = 0 ]; then echo "All checks passed."; else echo "Some checks failed."; exit 1; fi
