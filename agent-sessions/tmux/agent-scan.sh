#!/bin/bash
# Colors the window NAME in the tmux status bar when a Claude Code / Codex CLI
# session runs inside the window:
#
#   green        = agent busy (braille spinner leads the pane title)
#   orange bold  = agent idle -> finished or waiting on you
#
# Stamps @agent_state on each pane for the picker, plus two per-window options
# consumed by the status formats: @agent_style and @agent_style_cur.
#
# Triggered once per status-interval by an invisible #() job in status-right.
# Detection walks the process tree (pane_current_command is useless here: the
# native Claude binary reports its version number, npm Codex reports "node").

set -u

pane_pids=$(tmux list-panes -a -F '#{pane_pid}' | tr '\n' ' ') || exit 0

# Pane pids that host an agent: every claude/codex process whose ancestry
# reaches a pane pid.
agent_panes=$(ps -axo pid=,ppid=,comm= | awk -v roots="$pane_pids" '
  BEGIN { n = split(roots, r, " "); for (i = 1; i <= n; i++) root[r[i]] = 1 }
  {
    ppid[$1] = $2
    c = $3; for (i = 4; i <= NF; i++) c = c " " $i
    comm[$1] = c
  }
  END {
    for (p in ppid) {
      if (comm[p] !~ /(^|\/)claude$/ && comm[p] !~ /(^|\/)codex$/) continue
      d = 0
      for (cur = p; cur in ppid && d < 25; cur = ppid[cur]) {
        if (cur in root) { print cur; break }
        d++
      }
    }
  }')

# Per-agent-pane records: "pane_id window_id busy|idle". Busy = pane title starts with
# a braille spinner char (U+2800-U+28FF = bytes E2 A0..A3 xx), which both TUIs
# show while their agent is working. Byte prefixes live in variables because
# macOS bash 3.2 rejects $'..' in patterns; [[ ]] instead of case because
# bash 3.2 cannot parse `case` inside $(..).
b0=$'\xe2\xa0' b1=$'\xe2\xa1' b2=$'\xe2\xa2' b3=$'\xe2\xa3'
records=$(tmux list-panes -a -F '#{pane_id}|#{window_id}|#{pane_pid}|#{pane_title}' |
  while IFS='|' read -r pane win pid title; do
    grep -q "^$pid$" <<<"$agent_panes" || continue
    state=idle
    if [[ "$title" == "$b0"* || "$title" == "$b1"* || "$title" == "$b2"* || "$title" == "$b3"* ]]; then
      state=busy
    fi
    printf '%s\t%s\t%s\n' "$pane" "$win" "$state"
  done)

# Keep the per-pane state current when agents start, stop, or move between panes.
tmux list-panes -a -F "#{pane_id}	#{@agent_state}" |
  while IFS=$'\t' read -r pane current; do
    state=$(awk -F '\t' -v pane="$pane" '$1 == pane { print $3; exit }' <<<"$records")
    [ "$state" = "$current" ] || tmux set-option -p -t "$pane" @agent_state "$state"
  done

# One state per window; an idle agent anywhere in the window wins attention.
states=$(awk -F '\t' '
  NF >= 3 {
    win[$2] = 1
    if ($3 == "idle") attn[$2] = 1
  }
  END { for (w in win) print w "\t" (w in attn ? "attn" : "busy") }
' <<<"$records")

# Apply only on change so the status line is not redrawn needlessly.
tmux list-windows -a -F "#{window_id}	#{@agent_style}	#{@agent_style_cur}" |
  while IFS=$'\t' read -r w cur_normal cur_current; do
    state=$(grep -m1 "^$w"$'\t' <<<"$states" | cut -f2)
    normal="" current=""
    if [ "$state" = busy ]; then
      normal="#[fg=colour114]" current="#[fg=colour28]"
    elif [ "$state" = attn ]; then
      normal="#[fg=colour214,bold]" current="#[fg=colour166,bold]"
    fi
    [ "$normal" = "$cur_normal" ] || tmux set-option -w -t "$w" @agent_style "$normal"
    [ "$current" = "$cur_current" ] || tmux set-option -w -t "$w" @agent_style_cur "$current"
  done

exit 0
