# Agent sessions for tmux and macOS

This bundle surfaces Codex session titles and activity from two places:

- local Codex processes running in tmux panes;
- Codex processes managed by HerdR inside an SSH session on a devbox.

It adds a unified `prefix + w` picker and a compact macOS menu-bar item. The
menu bar shows working and idle counts (`●5 ○2`); its dropdown shows full
titles and switches directly to the selected local tmux pane or remote HerdR
agent.

## Requirements

- macOS 13 or newer
- tmux and fzf
- Hammerspoon
- Tailscale, connected to the devbox tailnet
- Ghostty, or another terminal configured in `config`
- HerdR running on the devbox
- Codex terminal-title updates enabled (the default)

Install the macOS dependencies with Homebrew if needed:

```sh
brew bundle --file agent-sessions/Brewfile
```

## Install

From the repository root:

```sh
./agent-sessions/install.sh
```

The installer:

1. symlinks this directory to `~/.local/share/agent-sessions`;
2. creates `~/.config/agent-sessions/config` when absent;
3. appends one marked source block to `~/.tmux.conf` when absent;
4. appends one marked loader block to `~/.hammerspoon/init.lua` when absent;
5. creates timestamped backups before changing an existing config file.

It does not replace existing tmux or Hammerspoon configuration.

Edit the per-Mac configuration:

```sh
$EDITOR ~/.config/agent-sessions/config
```

Then reload tmux and Hammerspoon. In tmux:

```sh
tmux source-file ~/.tmux.conf
```

In Hammerspoon, choose **Reload Config**. The installed `hs.ipc` integration
also makes this available afterward:

```sh
hs -c 'hs.reload()'
```

## Use

- Press `prefix + w` in tmux for the unified fuzzy picker.
- Use `j` and `k` to move, and `Enter` to select.
- Click the `●n ○n` macOS menu-bar item for the same agent sessions.
- `●` means working; `○` means idle or waiting for attention.

The remote rows are fetched live with `herdr agent list`. Selecting one calls
`herdr agent focus`, switches the attached local tmux client to the SSH pane,
and activates the configured terminal application.

Verify discovery without opening the picker:

```sh
~/.local/share/agent-sessions/bin/session-picker.sh --list
```

## Configuration

`~/.config/agent-sessions/config` is a user-owned shell configuration file.
The installer never overwrites it. Supported settings are documented in
[`config.example`](config.example).

`HERDR_TARGET` is the only intentional host coupling. tmux pane identifiers
and HerdR pane identifiers are discovered again on each refresh.

## Remove

From the same repository checkout used to install:

```sh
./agent-sessions/install.sh --uninstall
```

This removes the marked integration blocks and the managed symlink after
creating backups. It retains `~/.config/agent-sessions/config`.
