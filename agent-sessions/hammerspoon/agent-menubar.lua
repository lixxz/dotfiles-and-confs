local M = {}

local home = os.getenv("HOME")
local installRoot = os.getenv("AGENT_SESSIONS_ROOT") or (home .. "/.local/share/agent-sessions")
local configPath = os.getenv("AGENT_SESSIONS_CONFIG") or (home .. "/.config/agent-sessions/config")
local PICKER = installRoot .. "/bin/session-picker.sh"

local function readConfig(path)
  local config = {}
  local file = io.open(path, "r")
  if not file then
    return config
  end
  for line in file:lines() do
    local key, value = line:match("^%s*([A-Z_]+)%s*=%s*(.-)%s*$")
    if key and value and not line:match("^%s*#") then
      value = value:gsub("^['\"]", ""):gsub("['\"]$", "")
      config[key] = value
    end
  end
  file:close()
  return config
end

local config = readConfig(configPath)
local REFRESH_SECONDS = tonumber(config.REFRESH_SECONDS) or 15
local TERMINAL_APP = config.TERMINAL_APP or "Ghostty"
if REFRESH_SECONDS < 5 then
  REFRESH_SECONDS = 5
end

M.sessions = {}
M.remoteUnavailable = false
M.refreshTask = nil
M.focusTasks = {}
M.item = hs.menubar.new(true, "codex-agent-sessions")
M.item:setTitle("Agents …")
M.item:setTooltip("Codex sessions in local tmux and devbox HerdR")

local function parseSessions(output)
  local sessions = {}
  for line in output:gmatch("[^\n]+") do
    local kind, target, tmuxTarget, display = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t(.*)$")
    if kind and (display:find("●", 1, true) or display:find("○", 1, true)) then
      table.insert(sessions, {
        kind = kind,
        target = target,
        tmuxTarget = tmuxTarget,
        display = display,
        working = display:find("●", 1, true) ~= nil,
      })
    end
  end
  return sessions
end

local function setSummaryTitle()
  local working = 0
  local idle = 0
  for _, session in ipairs(M.sessions) do
    if session.working then
      working = working + 1
    else
      idle = idle + 1
    end
  end
  M.item:setTitle(string.format("●%d ○%d", working, idle))
end

local function focusSession(session)
  local args
  if session.kind == "remote" then
    args = { "--focus-remote", session.target, session.tmuxTarget }
  else
    args = { "--focus-local", session.target }
  end

  local task
  task = hs.task.new(PICKER, function(exitCode)
    M.focusTasks[task] = nil
    if exitCode == 0 then
      hs.application.launchOrFocus(TERMINAL_APP)
    else
      hs.alert.show("Could not switch Codex session")
    end
  end, args)
  if not task then
    hs.alert.show("Could not start the Codex session switcher")
    return
  end
  M.focusTasks[task] = true
  if not task:start() then
    M.focusTasks[task] = nil
    hs.alert.show("Could not start the Codex session switcher")
  end
end

local function menuItemFor(session)
  local title = session.display:gsub("^LOCAL%s+", ""):gsub("^DEVBOX%s+", "")
  return {
    title = title,
    fn = function()
      focusSession(session)
    end,
  }
end

local function buildMenu()
  local menu = {}
  local localSessions = {}
  local remoteSessions = {}
  for _, session in ipairs(M.sessions) do
    if session.kind == "remote" then
      table.insert(remoteSessions, session)
    else
      table.insert(localSessions, session)
    end
  end

  table.insert(menu, { title = "Local tmux", disabled = true })
  if #localSessions == 0 then
    table.insert(menu, { title = "No local Codex sessions", disabled = true, indent = 1 })
  else
    for _, session in ipairs(localSessions) do
      table.insert(menu, menuItemFor(session))
    end
  end

  table.insert(menu, { title = "-" })
  table.insert(menu, { title = "Devbox HerdR", disabled = true })
  if M.remoteUnavailable then
    table.insert(menu, { title = "Unavailable", disabled = true, indent = 1 })
  elseif #remoteSessions == 0 then
    table.insert(menu, { title = "No remote Codex sessions", disabled = true, indent = 1 })
  else
    for _, session in ipairs(remoteSessions) do
      table.insert(menu, menuItemFor(session))
    end
  end

  table.insert(menu, { title = "-" })
  table.insert(menu, { title = "Refresh", fn = function() M.refresh() end })
  return menu
end

function M.refresh()
  if M.refreshTask then
    return
  end

  local task
  task = hs.task.new(PICKER, function(exitCode, stdOut, stdErr)
    M.refreshTask = nil
    if exitCode == 0 then
      M.sessions = parseSessions(stdOut or "")
      M.remoteUnavailable = (stdErr or ""):find("remote_status=unavailable", 1, true) ~= nil
      setSummaryTitle()
    end
  end, { "--list" })

  if not task then
    return
  end
  M.refreshTask = task
  if not task:start() then
    M.refreshTask = nil
  end
end

M.item:setMenu(function()
  M.refresh()
  return buildMenu()
end)
M.timer = hs.timer.doEvery(REFRESH_SECONDS, M.refresh)
M.refresh()

return M
