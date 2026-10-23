#!/usr/bin/env bash
# Runs install.sh against a real OpenCode, in throwaway settings and cache folders, and checks what it leaves behind.
# Needs network access to GitHub. Usage: test/test.sh [path to opencode]
# KIT_BASH picks the bash that runs install.sh, such as /bin/bash on macOS, which is bash 3.2.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OPENCODE_BIN=${1:-$(command -v opencode || echo "$HOME/.opencode/bin/opencode")}
KIT_BASH=${KIT_BASH:-bash}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FAILED=0

# A fresh home for each scenario. Nothing outside it is read or written.
fresh() {
    rm -rf "${WORK:?}/home"
    mkdir -p "$WORK/home/config/opencode" "$WORK/home/project"
}

in_home() {
    (
        cd "$WORK/home/project"
        env -u BUN_BE_BUN -u OPENCODE_CONFIG_CONTENT -u OPENCODE_CLI_CONFIG_CONTENT -u OPENCODE_CONFIG \
            XDG_CONFIG_HOME="$WORK/home/config" XDG_CACHE_HOME="$WORK/home/cache" \
            XDG_DATA_HOME="$WORK/home/data" XDG_STATE_HOME="$WORK/home/state" NO_COLOR=1 "$@" </dev/null
    )
}

kit() { in_home env OPENCODE_BIN="$OPENCODE_BIN" "$KIT_BASH" "$ROOT/install.sh" "$@"; }
opencode() { in_home "$OPENCODE_BIN" "$@"; }

cli_json() { cat "$WORK/home/config/opencode/cli.json" 2>/dev/null || true; }
server_json() { cat "$WORK/home/config/opencode/opencode.json" 2>/dev/null || true; }
caches() {
    local dir
    for dir in "$WORK"/home/cache/opencode/npm/*; do [ -e "$dir" ] && basename "$dir"; done | sed 's/-[0-9a-f]*$//' | sort | tr '\n' ' '
}

check() {
    local what=$1
    shift
    if "$@"; then
        printf '  ok    %s\n' "$what"
    else
        printf '  FAIL  %s\n' "$what"
        FAILED=1
    fi
}
has() { grep -qF -- "$2" <<<"$1"; }
lacks() { ! grep -qF -- "$2" <<<"$1"; }
count() { grep -oF -- "$2" <<<"$1" | wc -l | tr -d ' '; }

# shellcheck disable=SC2016 # expanded by $KIT_BASH
echo "OpenCode: $("$OPENCODE_BIN" --version </dev/null), install.sh run by $("$KIT_BASH" -c 'echo bash $BASH_VERSION')"

echo "fresh install"
fresh
kit >"$WORK/out" 2>&1 || { cat "$WORK/out"; exit 1; }
check "ask and delete are in cli.json, pinned" has "$(cli_json)" '"github:dhkimxx/opencode-ask#v0.3.3"'
check "delete is pinned" has "$(cli_json)" '"github:dhkimxx/opencode-delete#v0.1.0"'
check "lodestar is in opencode.json, pinned" has "$(server_json)" '"github:dhkimxx/opencode-lodestar#v0.4.0"'
check "one download per plugin" test "$(caches)" = "git-opencode-ask git-opencode-delete git-opencode-lodestar "

echo "running it again changes nothing"
before="$(cli_json)$(server_json)"
kit >"$WORK/out" 2>&1 || { cat "$WORK/out"; exit 1; }
check "same settings" test "$before" = "$(cli_json)$(server_json)"
check "still one download per plugin" test "$(caches)" = "git-opencode-ask git-opencode-delete git-opencode-lodestar "

echo "cleans up other copies"
fresh
opencode plugin add github:dhkimxx/opencode-ask >/dev/null
opencode plugin add 'github:dhkimxx/opencode-lodestar#v0.3.0' >/dev/null
opencode plugin add github:dhkimxx/opencode-lodestar >/dev/null
mkdir -p "$WORK/home/config/opencode/plugins/opencode-delete"
printf '{\n  "name": "@dhkimxx/opencode-delete",\n  "version": "0.1.0"\n}\n' >"$WORK/home/config/opencode/plugins/opencode-delete/package.json"
# Entries that only look similar stay: another owner's repo, a local checkout, a longer name.
python3 -I - "$WORK/home/config/opencode/cli.json" <<'EOF'
import json, sys
path = sys.argv[1]
config = json.load(open(path))
config["plugins"] += ["github:someone/opencode-ask", "/home/me/src/opencode-ask", "github:dhkimxx/opencode-asking"]
json.dump(config, open(path, "w"), indent=2)
EOF
kit >"$WORK/out" 2>&1 || { cat "$WORK/out"; exit 1; }
check "the unpinned ask is gone" lacks "$(cli_json)" '"github:dhkimxx/opencode-ask"'
check "ask is listed once" test "$(count "$(cli_json)" 'dhkimxx/opencode-ask#')" = 1
check "lodestar is listed once, at v0.4.0" test "$(count "$(server_json)" 'dhkimxx/opencode-lodestar')" = 1
check "similar entries stay" has "$(cli_json)" '"github:someone/opencode-ask"'
check "local checkouts stay" has "$(cli_json)" '"/home/me/src/opencode-ask"'
check "longer names stay" has "$(cli_json)" '"github:dhkimxx/opencode-asking"'
check "the clone left the plugins folder" test ! -e "$WORK/home/config/opencode/plugins/opencode-delete"
check "the clone is in the backup folder" test -n "$(ls "$WORK/home/config/opencode/opencode-kit-backup" 2>/dev/null)"
check "old downloads are cleared" test "$(caches)" = "git-opencode-ask git-opencode-delete git-opencode-lodestar "

echo "--only touches only those plugins"
fresh
kit >/dev/null 2>&1
ask_cache=$(ls -d "$WORK/home/cache/opencode/npm"/git-opencode-ask-*/*)
kit --only lodestar >"$WORK/out" 2>&1 || { cat "$WORK/out"; exit 1; }
check "ask's download is untouched" test -d "$ask_cache"
check "output mentions only lodestar" lacks "$(cat "$WORK/out")" "opencode-ask"

echo "--dry-run changes nothing"
fresh
opencode plugin add github:dhkimxx/opencode-ask >/dev/null
before="$(cli_json)$(server_json)$(caches)"
kit --dry-run >"$WORK/out" 2>&1 || { cat "$WORK/out"; exit 1; }
check "same settings and downloads" test "$before" = "$(cli_json)$(server_json)$(caches)"
check "says what it would do" has "$(cat "$WORK/out")" "would install github:dhkimxx/opencode-ask#v0.3.3"

echo "--uninstall removes everything"
fresh
kit >/dev/null 2>&1
kit --uninstall >"$WORK/out" 2>&1 || { cat "$WORK/out"; exit 1; }
check "no entries left" lacks "$(cli_json)$(server_json)" "dhkimxx/opencode-"
check "no downloads left" test -z "$(caches)"

echo "refuses an OpenCode that is too old"
fresh
cat >"$WORK/old-opencode" <<'EOF'
#!/bin/sh
[ "$1" = --version ] && echo "opencode v2.0.27" && exit 0
echo "unexpected call: $*" >&2
exit 1
EOF
chmod +x "$WORK/old-opencode"
if in_home env OPENCODE_BIN="$WORK/old-opencode" "$KIT_BASH" "$ROOT/install.sh" >"$WORK/out" 2>&1; then status=0; else status=$?; fi
check "exits with an error" test "$status" = 1
check "says to upgrade" has "$(cat "$WORK/out")" "opencode upgrade"
check "changed nothing" test -z "$(cli_json)$(server_json)"

echo "warns about an OpenCode newer than tested"
fresh
cat >"$WORK/new-opencode" <<EOF
#!/bin/sh
[ "\$1" = --version ] && echo "opencode v9.0.0" && exit 0
exec "$OPENCODE_BIN" "\$@"
EOF
chmod +x "$WORK/new-opencode"
in_home env OPENCODE_BIN="$WORK/new-opencode" "$KIT_BASH" "$ROOT/install.sh" --only delete >"$WORK/out" 2>&1 || { cat "$WORK/out"; exit 1; }
check "warns" has "$(cat "$WORK/out")" "newer than"
check "installs anyway" has "$(cli_json)" '"github:dhkimxx/opencode-delete#v0.1.0"'

if [ "$FAILED" = 0 ]; then echo "All checks passed."; else echo "Some checks failed."; exit 1; fi
