#!/bin/bash

set -eu

SOURCE_ROOT=$(cd "$(dirname "$0")" && pwd -P)
TARGET_HOME=${AGENT_SESSIONS_HOME:-"$HOME"}
INSTALL_LINK="$TARGET_HOME/.local/share/agent-sessions"
CONFIG_DIR="$TARGET_HOME/.config/agent-sessions"
TMUX_CONF="$TARGET_HOME/.tmux.conf"
HAMMERSPOON_DIR="$TARGET_HOME/.hammerspoon"
HAMMERSPOON_INIT="$HAMMERSPOON_DIR/init.lua"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

TMUX_BEGIN='# >>> agent-sessions >>>'
TMUX_END='# <<< agent-sessions <<<'
HAMMERSPOON_BEGIN='-- >>> agent-sessions >>>'
HAMMERSPOON_END='-- <<< agent-sessions <<<'

backup_file() {
    local file=$1
    [ -e "$file" ] || return 0
    cp -p "$file" "$file.bak.$STAMP"
}

validate_block() {
    local file=$1 begin=$2 end=$3 begin_count end_count
    [ -e "$file" ] || return 0
    begin_count=$(grep -Fc -- "$begin" "$file" || true)
    end_count=$(grep -Fc -- "$end" "$file" || true)
    if { [ "$begin_count" -eq 0 ] && [ "$end_count" -eq 0 ]; } ||
       { [ "$begin_count" -eq 1 ] && [ "$end_count" -eq 1 ]; }; then
        return 0
    fi
    printf 'Malformed agent-sessions block in %s; leaving it unchanged\n' "$file" >&2
    return 1
}

append_block() {
    local file=$1 begin=$2 end=$3 body=$4 begin_count end_count
    mkdir -p "$(dirname "$file")"
    if [ -e "$file" ]; then
        begin_count=$(grep -Fc -- "$begin" "$file" || true)
        end_count=$(grep -Fc -- "$end" "$file" || true)
        if [ "$begin_count" -eq 1 ] && [ "$end_count" -eq 1 ]; then
            return 0
        fi
        if [ "$begin_count" -ne 0 ] || [ "$end_count" -ne 0 ]; then
            printf 'Malformed agent-sessions block in %s; leaving it unchanged\n' "$file" >&2
            return 1
        fi
        backup_file "$file"
    else
        : > "$file"
    fi
    printf '\n%s\n%s\n%s\n' "$begin" "$body" "$end" >> "$file"
}

remove_block() {
    local file=$1 begin=$2 end=$3 temporary begin_count end_count
    [ -e "$file" ] || return 0
    begin_count=$(grep -Fc -- "$begin" "$file" || true)
    end_count=$(grep -Fc -- "$end" "$file" || true)
    if [ "$begin_count" -eq 0 ] && [ "$end_count" -eq 0 ]; then
        return 0
    fi
    if [ "$begin_count" -ne 1 ] || [ "$end_count" -ne 1 ]; then
        printf 'Malformed agent-sessions block in %s; leaving it unchanged\n' "$file" >&2
        return 1
    fi
    temporary=$(mktemp)
    awk -v begin="$begin" -v end="$end" '
        $0 == begin { skipping = 1; next }
        $0 == end { skipping = 0; next }
        !skipping { print }
    ' "$file" > "$temporary"
    backup_file "$file"
    cat "$temporary" > "$file"
    rm -f "$temporary"
}

uninstall() {
    validate_block "$TMUX_CONF" "$TMUX_BEGIN" "$TMUX_END"
    validate_block "$HAMMERSPOON_INIT" "$HAMMERSPOON_BEGIN" "$HAMMERSPOON_END"
    remove_block "$TMUX_CONF" "$TMUX_BEGIN" "$TMUX_END"
    remove_block "$HAMMERSPOON_INIT" "$HAMMERSPOON_BEGIN" "$HAMMERSPOON_END"
    if [ -L "$INSTALL_LINK" ] && [ "$(readlink "$INSTALL_LINK")" = "$SOURCE_ROOT" ]; then
        rm "$INSTALL_LINK"
    fi
    printf 'Removed agent-sessions integration. Local config remains at %s\n' "$CONFIG_DIR"
}

if [ "${1:-}" = '--uninstall' ]; then
    uninstall
    exit 0
fi
if [ "$#" -ne 0 ]; then
    printf 'Usage: %s [--uninstall]\n' "$0" >&2
    exit 2
fi

validate_block "$TMUX_CONF" "$TMUX_BEGIN" "$TMUX_END"
validate_block "$HAMMERSPOON_INIT" "$HAMMERSPOON_BEGIN" "$HAMMERSPOON_END"

mkdir -p "$(dirname "$INSTALL_LINK")" "$CONFIG_DIR" "$HAMMERSPOON_DIR"
if [ -L "$INSTALL_LINK" ]; then
    if [ "$(readlink "$INSTALL_LINK")" != "$SOURCE_ROOT" ]; then
        printf '%s already points to another location\n' "$INSTALL_LINK" >&2
        exit 1
    fi
elif [ -e "$INSTALL_LINK" ]; then
    printf '%s exists and is not a symlink; leaving it unchanged\n' "$INSTALL_LINK" >&2
    exit 1
else
    ln -s "$SOURCE_ROOT" "$INSTALL_LINK"
fi

if [ ! -e "$CONFIG_DIR/config" ]; then
    cp "$SOURCE_ROOT/config.example" "$CONFIG_DIR/config"
    chmod 0600 "$CONFIG_DIR/config"
fi

tmux_body='source-file ~/.local/share/agent-sessions/tmux/agent-sessions.conf'
hammerspoon_body='require("hs.ipc")
agentMenubar = dofile(os.getenv("HOME") .. "/.local/share/agent-sessions/hammerspoon/agent-menubar.lua")'
append_block "$TMUX_CONF" "$TMUX_BEGIN" "$TMUX_END" "$tmux_body"
append_block "$HAMMERSPOON_INIT" "$HAMMERSPOON_BEGIN" "$HAMMERSPOON_END" "$hammerspoon_body"

printf 'Installed agent-sessions from %s\n' "$SOURCE_ROOT"
printf 'Edit %s, then reload tmux and Hammerspoon.\n' "$CONFIG_DIR/config"
