#!/bin/bash
# Unified session inventory and switcher for local tmux windows and HerdR on the devbox.

set -u
export LANG='en_US.UTF-8'
export LC_CTYPE='en_US.UTF-8'

CONFIG_FILE=${AGENT_SESSIONS_CONFIG:-"$HOME/.config/agent-sessions/config"}
if [ -r "$CONFIG_FILE" ]; then
    # This is a user-owned shell configuration containing simple assignments.
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
fi

HERDR_TARGET=${HERDR_TARGET:-'azureadmin@bhume-devbox-yash'}
DEVBOX_NAME=${DEVBOX_NAME:-"${HERDR_TARGET#*@}"}
TMUX_BIN=${TMUX_BIN:-}
TAILSCALE_BIN=${TAILSCALE_BIN:-}
FZF_BIN=${FZF_BIN:-}
PYTHON_BIN=${PYTHON_BIN:-}

[ -n "$TMUX_BIN" ] || TMUX_BIN=$(command -v tmux || true)
[ -n "$TAILSCALE_BIN" ] || TAILSCALE_BIN=$(command -v tailscale || true)
[ -n "$TAILSCALE_BIN" ] || TAILSCALE_BIN='/Applications/Tailscale.app/Contents/MacOS/Tailscale'
[ -n "$FZF_BIN" ] || FZF_BIN=$(command -v fzf || true)
[ -n "$PYTHON_BIN" ] || PYTHON_BIN=$(command -v python3 || true)

[ -x "$TMUX_BIN" ] || { printf 'tmux is required\n' >&2; exit 1; }

latest_tmux_client() {
    "$TMUX_BIN" list-clients -F '#{client_activity} #{client_name}' 2>/dev/null |
        sort -rn | head -n 1 | cut -d ' ' -f 2-
}

switch_tmux_target() {
    local target=$1 client
    client=$(latest_tmux_client)
    [ -n "$client" ] || return 1
    "$TMUX_BIN" switch-client -c "$client" -t "$target"
}

focus_remote_agent() {
    local agent_target=$1 tmux_target=$2
    case "$agent_target" in
        *[!A-Za-z0-9:_-]*) return 1 ;;
    esac
    [ -x "$TAILSCALE_BIN" ] || return 1
    "$TAILSCALE_BIN" ssh "$HERDR_TARGET" "herdr agent focus $agent_target" >/dev/null 2>&1 &&
        switch_tmux_target "$tmux_target"
}

case "${1:-}" in
    --focus-local)
        [ "$#" -eq 2 ] || exit 2
        switch_tmux_target "$2"
        exit $?
        ;;
    --focus-remote)
        [ "$#" -eq 3 ] || exit 2
        focus_remote_agent "$2" "$3"
        exit $?
        ;;
esac

rows=$(mktemp -t tmux-session-picker.XXXXXX)
trap 'rm -f "$rows"' EXIT HUP INT TERM

sep='__CODEX_SESSION_FIELD__'
ssh_tmux_target=''
while IFS= read -r record; do
    target=${record%%"$sep"*}
    record=${record#*"$sep"}
    window_name=${record%%"$sep"*}
    record=${record#*"$sep"}
    pane_title=${record%%"$sep"*}
    agent_style=${record#*"$sep"}
    marker='  '
    if [[ "$agent_style" == *'colour114'* ]]; then
        marker='● '
    elif [[ "$agent_style" == *'colour214'* ]]; then
        marker='○ '
    fi

    if [[ "$pane_title" == *"$DEVBOX_NAME"* ]]; then
        ssh_tmux_target=$target
        title='HerdR devbox'
    elif [ -n "$agent_style" ] && [ -n "$pane_title" ]; then
        title=$pane_title
    else
        title=$window_name
    fi
    title=${title//$'\t'/ }
    title=${title//$'\n'/ }
    printf 'local\t%s\t-\tLOCAL   %s%-7s %s\n' "$target" "$marker" "$target" "$title" >> "$rows"
done < <("$TMUX_BIN" list-windows -a -F "#{session_name}:#{window_index}${sep}#{window_name}${sep}#{pane_title}${sep}#{@agent_style}")

remote_ok=0
if [ -n "$ssh_tmux_target" ] && [ -x "$TAILSCALE_BIN" ] && [ -x "$PYTHON_BIN" ]; then
    if remote_json=$("$TAILSCALE_BIN" ssh "$HERDR_TARGET" 'herdr agent list' 2>/dev/null); then
        if printf '%s' "$remote_json" | "$PYTHON_BIN" -c '
import json
import sys

ssh_target = sys.argv[1]
payload = json.load(sys.stdin)
agents = payload.get("result", {}).get("agents", [])
for agent in agents:
    pane_id = str(agent.get("pane_id", ""))
    if not pane_id:
        continue
    state = str(agent.get("agent_status", "unknown"))
    marker = "●" if state == "working" else "○"
    title = agent.get("terminal_title_stripped") or agent.get("terminal_title") or pane_id
    title = str(title).replace("\t", " ").replace("\n", " ")
    print(f"remote\t{pane_id}\t{ssh_target}\tDEVBOX  {marker} {title}")
' "$ssh_tmux_target" >> "$rows"; then
            remote_ok=1
        fi
    fi
fi

if [ "${1:-}" = '--list' ] || [ "${TMUX_SESSION_PICKER_LIST_ONLY:-0}" = 1 ]; then
    cat "$rows"
    [ "$remote_ok" = 1 ] || printf 'remote_status=unavailable\n' >&2
    exit 0
fi

[ -x "$FZF_BIN" ] || { printf 'fzf is required for the interactive picker\n' >&2; exit 1; }

choice=$("$FZF_BIN" \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=4 \
    --layout=reverse \
    --bind='j:down,k:up' \
    --info=inline \
    --prompt='session> ' \
    --pointer='▶' \
    --header='LOCAL = tmux window   DEVBOX = HerdR agent' \
    < "$rows") || exit 0

IFS=$'\t' read -r kind target tmux_target _ <<< "$choice"
case "$kind" in
    local)
        switch_tmux_target "$target" || "$TMUX_BIN" display-message 'Could not switch tmux window'
        ;;
    remote)
        focus_remote_agent "$target" "$tmux_target" ||
            "$TMUX_BIN" display-message 'Could not focus the selected HerdR agent'
        ;;
esac
