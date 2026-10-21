#!/usr/bin/env bash
# Installs, updates, or removes dhkimxx's OpenCode plugins in one step.
#
#   curl -fsSL https://raw.githubusercontent.com/dhkimxx/opencode-kit/main/install.sh | bash
#
# OpenCode's settings are changed only through `opencode plugin add` and `opencode plugin remove`.
set -euo pipefail

KIT_VERSION=0.1.0
# OpenCode versions this set of releases was tested with. Older versions are refused; newer ones get a warning.
OPENCODE_MIN=2.1.2
OPENCODE_TESTED=2.1.2
# Each plugin and the release installed for it.
PLUGINS="lodestar:v0.3.1 ask:v0.3.3 delete:v0.1.0"
OWNER=dhkimxx

usage() {
    cat <<EOF
opencode-kit $KIT_VERSION: installs dhkimxx's OpenCode plugins (lodestar, ask, delete).

Usage: install.sh [options]

Options:
    --only <names>   Install or remove only these plugins, comma-separated (e.g. lodestar,ask)
    --uninstall      Remove the plugins instead of installing them
    --dry-run        Show what would change, and change nothing
    -h, --help       Show this help

Run it again to update. Each run first removes every other copy of these plugins:
other entries in your settings, clones in OpenCode's plugins folder, and downloaded copies.

Examples:
    curl -fsSL https://raw.githubusercontent.com/$OWNER/opencode-kit/main/install.sh | bash
    curl -fsSL https://raw.githubusercontent.com/$OWNER/opencode-kit/main/install.sh | bash -s -- --only lodestar
    curl -fsSL https://raw.githubusercontent.com/$OWNER/opencode-kit/main/install.sh | bash -s -- --uninstall
EOF
}

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    MUTED=$'\033[0;2m' RED=$'\033[0;31m' YELLOW=$'\033[0;33m' NC=$'\033[0m'
else
    MUTED="" RED="" YELLOW="" NC=""
fi

say() { printf '%s\n' "$*"; }
# Paths under the home folder are shown as ~/…
# shellcheck disable=SC2088 # the ~ is printed, not expanded
short() {
    case $1 in
        "$HOME"/*) printf '~/%s\n' "${1#"$HOME"/}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}
note() { printf '%s%s%s\n' "$MUTED" "$*" "$NC"; }
warn() { printf '%sWarning:%s %s\n' "$YELLOW" "$NC" "$*" >&2; }
fail() {
    printf '%sError:%s %s\n' "$RED" "$NC" "$*" >&2
    exit 1
}

DRY_RUN=false

# OpenCode must never read this script: under `curl | bash` it is the shell's standard input.
opencode_cmd() { "$OPENCODE" "$@" </dev/null; }

find_opencode() {
    if [ -n "${OPENCODE_BIN:-}" ]; then
        printf '%s\n' "$OPENCODE_BIN"
    elif command -v opencode >/dev/null 2>&1; then
        command -v opencode
    elif [ -x "$HOME/.opencode/bin/opencode" ]; then
        printf '%s\n' "$HOME/.opencode/bin/opencode"
    fi
}

# Prints -1, 0, or 1. A pre-release such as 2.2.0-beta.1 comes before 2.2.0.
compare_versions() {
    local a=$1 b=$2 a_core b_core i x y
    a_core=${a%%-*}
    b_core=${b%%-*}
    local IFS=.
    # shellcheck disable=SC2206 # splitting on dots is the point
    local a_parts=($a_core) b_parts=($b_core)
    for i in 0 1 2; do
        x=${a_parts[$i]:-0}
        y=${b_parts[$i]:-0}
        x=${x//[!0-9]/}
        y=${y//[!0-9]/}
        if [ "${x:-0}" -gt "${y:-0}" ]; then echo 1 && return; fi
        if [ "${x:-0}" -lt "${y:-0}" ]; then echo -1 && return; fi
    done
    if [ "$a" = "$a_core" ] && [ "$b" != "$b_core" ]; then echo 1 && return; fi
    if [ "$a" != "$a_core" ] && [ "$b" = "$b_core" ]; then echo -1 && return; fi
    echo 0
}

check_opencode() {
    OPENCODE=$(find_opencode)
    [ -n "$OPENCODE" ] || fail "OpenCode is not installed. Install it first: curl -fsSL https://opencode.ai/v2/install | bash"
    local output version
    output=$(opencode_cmd --version 2>/dev/null) || fail "could not run $OPENCODE --version"
    version=${output##* }
    version=${version#v}
    [ -n "$version" ] || fail "could not read OpenCode's version from: $output"
    if [ "$(compare_versions "$version" "$OPENCODE_MIN")" = -1 ]; then
        fail "OpenCode $version is too old for these plugins, which need $OPENCODE_MIN or newer. Run \`opencode upgrade\`, then run this again."
    fi
    if [ "$(compare_versions "$version" "$OPENCODE_TESTED")" = 1 ]; then
        warn "OpenCode $version is newer than $OPENCODE_TESTED, the version these releases were tested with. Installing anyway."
    fi
    note "OpenCode $version ($(short "$OPENCODE"))"
}

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/opencode/npm"
# OpenCode reads server settings from the first of these that exists, and `opencode plugin` edits that one.
SERVER_CONFIGS="opencode.json opencode.jsonc .opencode/opencode.json .opencode/opencode.jsonc"

server_config() {
    local name
    for name in $SERVER_CONFIGS; do
        if [ -f "$CONFIG_DIR/$name" ]; then
            printf '%s\n' "$CONFIG_DIR/$name"
            return
        fi
    done
}

# Every plugin spec in a settings file that points at one of our repositories or packages, in any form:
# github:dhkimxx/opencode-ask, …#v0.3.3, git+https://github.com/dhkimxx/opencode-ask.git, @dhkimxx/opencode-ask@1.0.0.
specs_in() {
    local file=$1 plugin=$2
    [ -f "$file" ] || return 0
    grep -oE "\"[^\"]*${OWNER}/opencode-${plugin}(\\.git)?([#@][^\"]*)?\"" "$file" | tr -d '"' | sort -u || true
}

# The settings files `opencode plugin` edits: cli.json for TUI plugins, and the server settings file.
edited_configs() {
    local file
    printf '%s\n' "$CONFIG_DIR/cli.json"
    file=$(server_config)
    [ -z "$file" ] || printf '%s\n' "$file"
}

configured_specs() {
    local plugin=$1 file
    while IFS= read -r file; do specs_in "$file" "$plugin"; done <<<"$(edited_configs)"
}

remove_plugin() {
    local plugin=$1 file spec dir name backup stamp configs
    configs=$(edited_configs)
    while IFS= read -r spec; do
        [ -n "$spec" ] || continue
        if $DRY_RUN; then
            say "  would remove $spec"
        elif opencode_cmd plugin remove "$spec" >/dev/null; then
            say "  removed $spec"
        else
            warn "could not remove $spec"
        fi
    done <<<"$(configured_specs "$plugin" | sort -u)"
    # Settings files that OpenCode also reads, but that `opencode plugin` doesn't edit.
    for name in $SERVER_CONFIGS config.json; do
        file="$CONFIG_DIR/$name"
        if printf '%s\n' "$configs" | grep -qxF "$file"; then continue; fi
        if [ -n "$(specs_in "$file" "$plugin")" ]; then
            warn "$file also lists opencode-$plugin. Remove it there by hand, or OpenCode loads it twice."
        fi
    done

    # Clones in OpenCode's plugins folder load without any settings entry. They move to a backup folder instead.
    stamp=$(date +%Y%m%d%H%M%S)
    for dir in "$CONFIG_DIR"/plugins/*; do
        [ -e "$dir" ] || continue
        if grep -qE "\"name\": *\"@${OWNER}/opencode-${plugin}\"" "$dir/package.json" 2>/dev/null; then
            backup="$CONFIG_DIR/opencode-kit-backup/$(basename "$dir")-$stamp"
            if $DRY_RUN; then
                say "  would move $(short "$dir") to $(short "$backup")"
            else
                mkdir -p "$CONFIG_DIR/opencode-kit-backup"
                mv "$dir" "$backup"
                say "  moved $(short "$dir") to $(short "$backup")"
            fi
        fi
    done

    # Downloaded copies. Reinstalling from the same spec reuses them without checking for a newer one.
    for dir in "$CACHE_DIR"/git-opencode-"$plugin"-* "$CACHE_DIR/@$OWNER/opencode-$plugin"@*; do
        [ -d "$dir" ] || continue
        if compgen -G "$dir/*/node_modules/@$OWNER/opencode-$plugin" >/dev/null; then
            if $DRY_RUN; then
                note "  would clear $(short "$dir")"
            else
                rm -rf "$dir"
                note "  cleared $(short "$dir")"
            fi
        fi
    done
}

install_plugin() {
    local plugin=$1 tag=$2 spec output
    spec="github:$OWNER/opencode-$plugin#$tag"
    if $DRY_RUN; then
        say "  would install $spec"
        return 0
    fi
    if ! output=$(opencode_cmd plugin add "$spec" 2>&1); then
        printf '%s\n' "$output" >&2
        fail "could not install $spec. Run this again to retry."
    fi
    if [ "$(configured_specs "$plugin" | sort -u)" != "$spec" ]; then
        warn "opencode-$plugin is listed more than once in your settings: $(configured_specs "$plugin" | sort -u | tr '\n' ' ')"
    fi
    say "  installed $spec"
}

main() {
    local only="" uninstall=false entry plugin tag selected=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --only)
                [ $# -ge 2 ] || fail "--only needs a list of plugins, such as --only lodestar,ask"
                only=$2
                shift 2
                ;;
            --only=*)
                only=${1#--only=}
                shift
                ;;
            --uninstall)
                uninstall=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                usage >&2
                fail "unknown option: $1"
                ;;
        esac
    done

    if [ -n "$only" ]; then
        for plugin in ${only//,/ }; do
            case " $PLUGINS " in
                *" $plugin:"*) selected="$selected $plugin" ;;
                *) fail "unknown plugin: $plugin. Choose from: lodestar, ask, delete" ;;
            esac
        done
    else
        for entry in $PLUGINS; do selected="$selected ${entry%%:*}"; done
    fi

    say "opencode-kit $KIT_VERSION"
    check_opencode
    $DRY_RUN && note "Dry run: nothing will be changed."

    for entry in $PLUGINS; do
        plugin=${entry%%:*}
        tag=${entry#*:}
        case " $selected " in *" $plugin "*) ;; *) continue ;; esac
        say "opencode-$plugin"
        remove_plugin "$plugin"
        $uninstall || install_plugin "$plugin" "$tag"
    done

    if $DRY_RUN; then
        say "Dry run finished."
    elif $uninstall; then
        say "Done. The plugins are removed."
    else
        say "Done. A running OpenCode picks the plugins up within a few seconds; restart it if a command is missing."
    fi
}

main "$@"
