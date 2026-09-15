#!/bin/bash
# Rebuild the window-status formats from tmux-powerline's live templates,
# splicing the per-window agent style options (set by agent-scan.sh) in front
# of #W so the window NAME is recolored when an agent runs inside it.
#
# Done as a script instead of literal `set` lines in .tmux.conf because the
# templates contain invisible powerline glyphs (U+E0B0/U+E0B1) that do not
# survive hand transcription — and this way a powerline theme change is picked
# up automatically on the next conf reload.

set -u

INSTALL_ROOT=${AGENT_SESSIONS_ROOT:-"$HOME/.local/share/agent-sessions"}
P="$HOME/.tmux/plugins/tmux-powerline/powerline.sh"
if [ -x "$P" ]; then
  wf=$("$P" window-format)
  cf=$("$P" window-current-format)
else
  wf=$(tmux show-options -gv window-status-format)
  cf=$(tmux show-options -gv window-status-current-format)
fi

# Replacements live in variables: a literal } inside ${var/pat/rep} would end
# the expansion early.
rep_normal='#{@agent_style}#W'
rep_current='#{@agent_style_cur}#W'

case "$wf" in
  *'#{@agent_style}'*) ;;
  *) tmux set -g window-status-format "${wf/'#W'/$rep_normal}" ;;
esac
case "$cf" in
  *'#{@agent_style_cur}'*) ;;
  *) tmux set -g window-status-current-format "${cf/'#W'/$rep_current}" ;;
esac

scan_job="#($INSTALL_ROOT/tmux/agent-scan.sh)"
status_right=$(tmux show-options -gv status-right)
case "$status_right" in
  *"$scan_job"*) ;;
  *) tmux set -g status-right "$scan_job$status_right" ;;
esac
