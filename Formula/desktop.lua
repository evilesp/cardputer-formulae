#!lua
-- desktop: a small graphical desktop with touch, like a Linux desktop on top of a server install. Top bar with the clock,
-- icons of every app, windows you drag by the title bar, a task bar, a start menu and a quick panel.
--   desktop               starts the desktop (also what `desktop enable` runs at every boot)
--   desktop enable        start the desktop after boot (adds a line to ~/.profile, like graphical.target)
--   desktop disable       back to the text terminal at boot (removes that line)
--   desktop status        is it enabled, what is installed
--   desktop list          the desktop packages (apps, themes, wallpapers) that are installed
--   desktop install NAME  installs a desktop package: NAME of the repository, or a full URL of a .app/.theme/.wall file
--   desktop remove NAME   removes one
-- Gestures (one finger): tap = click; double tap on a title bar = maximize; long press on an icon = menu; drag a title bar
-- = move the window; drag the grip in the corner = resize; drag in a list = scroll; swipe down from the top edge = quick
-- panel; swipe up from the bottom edge = start menu; swipe left/right on the desktop = next/previous page of icons.
-- Without a touch screen the arrow keys move a pointer, enter presses, space is a long press, ctrl-q quits.
-- Packages are plain text files that anyone can write and share (no firmware update needed):
--   /usr/share/desktop/apps/NAME.app      Name=, Exec=(a program of /usr/local/bin or a path), Icon=(letter), Color=0xRRGGBB, Comment=
--   /usr/share/desktop/themes/NAME.theme  bg= bar= text= dim= accent= panel= title= border= danger= wall_top= wall_bottom=
--   /usr/share/desktop/wallpapers/NAME.wall  top=0xRRGGBB bottom=0xRRGGBB
--   /etc/desktop.conf and /home/user/.desktop.conf (the second wins):  theme=ubuntu  wallpaper=NAME  hidden=app1,app2
-- The touch reading is in one place (readPointer): it uses touch.read() when the firmware has it. Run with --selftest.

local APPS_DIR, THEMES_DIR, WALL_DIR = "/usr/share/desktop/apps", "/usr/share/desktop/themes", "/usr/share/desktop/wallpapers"
local CONF_SYS, CONF_USER = "/etc/desktop.conf", "/home/user/.desktop.conf"
local REPO = "https://raw.githubusercontent.com/evilesp/cardputer-formulae/main/Desktop/"

-- ---------------------------------------------------------------- small helpers

local function readFile(path)
  if not (fs and fs.read) then return nil end
  local ok, data = pcall(fs.read, path)
  if ok and type(data) == "string" then return data end
  return nil
end

local function listDir(path)
  if not (fs and fs.list) then return {} end
  local ok, list = pcall(fs.list, path)
  local out = {}
  if ok and type(list) == "table" then
    for _, e in ipairs(list) do
      local name = type(e) == "table" and e.name or e
      if type(name) == "string" and name ~= "" and name:sub(-1) ~= "/" then out[#out + 1] = name end
    end
  end
  table.sort(out)
  return out
end

-- "key=value" lines, # starts a comment; numbers like 0xRRGGBB are kept as text and converted by the caller
local function parseKV(text)
  local t = {}
  for line in (text or ""):gmatch("[^\r\n]+") do
    if not line:match("^%s*#") then
      local k, v = line:match("^%s*([%w_%.]+)%s*=%s*(.-)%s*$")
      if k then t[k:lower()] = v end
    end
  end
  return t
end

local function color(v, default)
  if type(v) == "number" then return v end
  if type(v) ~= "string" then return default end
  local hex = v:match("^#(%x%x%x%x%x%x)$") or v:match("^0[xX](%x+)$")
  if hex then return tonumber(hex, 16) end
  return tonumber(v) or default
end

local function mix(a, b, t)
  if t <= 0 then return a elseif t >= 1 then return b end
  local ar, ag, ab = (a >> 16) & 255, (a >> 8) & 255, a & 255
  return (math.floor(ar + (((b >> 16) & 255) - ar) * t + 0.5) << 16) | (math.floor(ag + (((b >> 8) & 255) - ag) * t + 0.5) << 8)
    | math.floor(ab + ((b & 255) - ab) * t + 0.5)
end

local function clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end

-- text that fits in `chars` characters
local function fit(text, chars)
  text = tostring(text)
  if #text <= chars then return text end
  if chars <= 2 then return text:sub(1, math.max(0, chars)) end
  return text:sub(1, chars - 2) .. ".."
end

local THEMES = {
  ubuntu = { bg = 0x2c001e, bar = 0x1d0014, text = 0xf2f2f2, dim = 0xaea79f, accent = 0xe95420, panel = 0x3a1a30, title = 0x5e2750,
             border = 0x77216f, danger = 0xc7162b, wall_top = 0x5e2750, wall_bottom = 0x2c001e },
  dark = { bg = 0x10131c, bar = 0x0a0c14, text = 0xe8ecf4, dim = 0x8a94aa, accent = 0x3cc878, panel = 0x1c2233, title = 0x34447c,
           border = 0x5870b0, danger = 0xe05050, wall_top = 0x1c2a4a, wall_bottom = 0x0a0c14 },
  light = { bg = 0xe8ecf2, bar = 0xd0d6e2, text = 0x1c2233, dim = 0x5a6478, accent = 0x2a70e0, panel = 0xf8f9fc, title = 0xc0c8dc,
            border = 0x8090b0, danger = 0xc03030, wall_top = 0xa8d0f0, wall_bottom = 0xe8f0f8 },
}
local THEME_KEYS = { "bg", "bar", "text", "dim", "accent", "panel", "title", "border", "danger", "wall_top", "wall_bottom" }

-- a theme: the named built-in one, then the colours of a .theme file on top of it
local function makeTheme(name, themeFile)
  local base = THEMES[name] or THEMES.ubuntu
  local t = {}
  for _, k in ipairs(THEME_KEYS) do t[k] = base[k] end
  if themeFile then
    local kv = parseKV(themeFile)
    for _, k in ipairs(THEME_KEYS) do t[k] = color(kv[k], t[k]) end
  end
  return t
end

-- the apps listed in a .app file (Name, Exec, Icon, Color, Comment)
local function parseApp(text, file)
  local kv = parseKV(text)
  if not kv.name or not kv.exec then return nil end
  local id = file:gsub("%.app$", "")
  return { id = id, name = kv.name, exec = kv.exec, icon = (kv.icon or kv.name):sub(1, 2):upper(),
           color = color(kv.color, nil), comment = kv.comment or "", file = true }
end

local ICON_COLORS = { 0xe95420, 0x3584e4, 0x26a269, 0xc061cb, 0xf5c211, 0x1a9fb8, 0xe01b24, 0x9a6b3e }
local function iconColor(name)
  local h = 0
  for i = 1, #name do h = (h * 31 + name:byte(i)) % 1000003 end
  return ICON_COLORS[h % #ICON_COLORS + 1]
end

-- ---------------------------------------------------------------- gestures
-- One finger. update(x, y, down, now) is called every frame and returns nil or an event name:
-- "down" "tap" "dtap" "long" "drag" (dx, dy since the last event; x0, y0 where it started) "drop" and "swipe" (dir "up" "down" "left" "right")
local Gesture = {}
Gesture.__index = Gesture

function Gesture.new(unit)
  return setmetatable({ unit = unit or 8, down = false, x = 0, y = 0, x0 = 0, y0 = 0, t0 = 0, moved = false, long = false,
                        lastTap = -10000, lastTapX = 0, lastTapY = 0, dx = 0, dy = 0, dir = nil, dragging = false }, Gesture)
end

function Gesture:update(x, y, down, now)
  local slop = self.unit * 1.5
  if down and not self.down then
    self.down, self.x0, self.y0, self.x, self.y, self.t0, self.moved, self.long, self.dragging = true, x, y, x, y, now, false, false, false
    return "down"
  elseif down and self.down then
    self.dx, self.dy = x - self.x, y - self.y
    self.x, self.y = x, y
    if not self.moved and math.abs(x - self.x0) + math.abs(y - self.y0) > slop then self.moved = true end
    if self.moved then
      self.dragging = true
      if self.dx ~= 0 or self.dy ~= 0 then return "drag" end
    elseif not self.long and now - self.t0 > 550 then
      self.long = true
      return "long"
    end
  elseif not down and self.down then
    self.down = false
    self.x, self.y = x, y
    if self.moved then
      local ax, ay = self.x - self.x0, self.y - self.y0
      local fast = now - self.t0 < 450
      if fast and math.max(math.abs(ax), math.abs(ay)) > self.unit * 5 then
        if math.abs(ay) >= math.abs(ax) then self.dir = ay < 0 and "up" or "down" else self.dir = ax < 0 and "left" or "right" end
        self.dragging = false
        return "swipe"
      end
      self.dragging = false
      return "drop"
    elseif self.long then
      return nil
    else
      local double = now - self.lastTap < 350 and math.abs(x - self.lastTapX) + math.abs(y - self.lastTapY) < slop * 2
      self.lastTap, self.lastTapX, self.lastTapY = double and -10000 or now, x, y
      return double and "dtap" or "tap"
    end
  end
  return nil
end

-- ---------------------------------------------------------------- the pointer: touch, or the keyboard as a mouse

local pointer = { x = 0, y = 0, down = false, keyboard = false }

-- the touch reading in one place. touch.read() may give x, y (nil when not touched), or a table of points, or { x =, y = }.
local function readPointer(w, h, held, pressedKeys)
  if touch and touch.read then
    local ok, a, b = pcall(touch.read)
    if ok then
      if type(a) == "table" then
        local p = a[1] or a
        if p and (p.x or p[1]) then
          pointer.x, pointer.y, pointer.down = p.x or p[1], p.y or p[2], true
        else
          pointer.down = false
        end
      elseif type(a) == "number" and type(b) == "number" then
        pointer.x, pointer.y, pointer.down = a, b, true
      else
        pointer.down = false
      end
      pointer.keyboard = false
      return
    end
  end
  -- no touch: the keyboard is the mouse
  pointer.keyboard = true
  local step = math.max(2, w // 60)
  for _, k in ipairs(held) do
    if k == "left" or k == "a" then pointer.x = pointer.x - step end
    if k == "right" or k == "d" then pointer.x = pointer.x + step end
    if k == "up" or k == "w" then pointer.y = pointer.y - step end
    if k == "down" or k == "s" then pointer.y = pointer.y + step end
  end
  pointer.x, pointer.y = clamp(pointer.x, 0, w - 1), clamp(pointer.y, 0, h - 1)
  pointer.down = pressedKeys.enter or false
end

-- ---------------------------------------------------------------- commands (the terminal side)

local function readConf()
  local conf = parseKV(readFile(CONF_SYS))
  for k, v in pairs(parseKV(readFile(CONF_USER))) do conf[k] = v end
  return conf
end

local function writeUserConf(conf)
  local lines = {}
  for k, v in pairs(conf) do lines[#lines + 1] = k .. "=" .. v end
  table.sort(lines)
  if fs and fs.write then return pcall(fs.write, CONF_USER, table.concat(lines, "\n") .. "\n") end
  return false
end

local PROFILE = "/home/user/.profile"

local function profileLines()
  local out = {}
  for line in (readFile(PROFILE) or ""):gmatch("([^\n]*)\n?") do out[#out + 1] = line end
  while #out > 0 and out[#out] == "" do out[#out] = nil end
  return out
end

local function isEnabled()
  for _, line in ipairs(profileLines()) do
    if line:match("^%s*desktop%s*$") then return true end
  end
  return false
end

local function setEnabled(on)
  local lines, out, found = profileLines(), {}, false
  for _, line in ipairs(lines) do
    if line:match("^%s*desktop%s*$") then found = true; if on then out[#out + 1] = line end else out[#out + 1] = line end
  end
  if on and not found then out[#out + 1] = "desktop" end
  return pcall(fs.write, PROFILE, table.concat(out, "\n") .. "\n")
end

local function kindOf(name)
  local ext = name:match("%.(%a+)$")
  if ext == "app" then return APPS_DIR end
  if ext == "theme" then return THEMES_DIR end
  if ext == "wall" then return WALL_DIR end
  return nil
end

local function installPackage(spec)
  if not net or not net.connected or not net.connected() then return false, "no WiFi: wifi connect SSID PASSWORD" end
  local url = spec:find("://", 1, true) and spec or (REPO .. spec)
  local name = url:match("([^/]+)$") or spec
  if not kindOf(name) then
    for _, ext in ipairs({ ".app", ".theme", ".wall" }) do
      if not spec:find("://", 1, true) and not name:find("%.") then
        local status, body = net.get(REPO .. name .. ext, 8192)
        if status == 200 and body then url, name = REPO .. name .. ext, name .. ext; break end
      end
    end
  end
  local dir = kindOf(name)
  if not dir then return false, "the package must be a .app, .theme or .wall file: " .. name end
  local status, body = net.get(url, 8192)
  if status ~= 200 or not body then return false, "download failed (" .. tostring(status) .. "): " .. url end
  if dir == APPS_DIR and not parseApp(body, name) then return false, "not a valid .app file (needs Name= and Exec=)" end
  local ok, err = pcall(fs.write, dir .. "/" .. name, body)
  if not ok then return false, tostring(err) end
  return true, dir .. "/" .. name
end

local function removePackage(name)
  for _, dir in ipairs({ APPS_DIR, THEMES_DIR, WALL_DIR }) do
    for _, f in ipairs(listDir(dir)) do
      if f == name or f:gsub("%.%a+$", "") == name then
        if fs.remove and pcall(fs.remove, dir .. "/" .. f) then return true, dir .. "/" .. f end
      end
    end
  end
  return false, "no such package: " .. name
end

-- ---------------------------------------------------------------- selftest

if arg and arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then failed = failed + 1; print("selftest failed: " .. what) end
  end
  local kv = parseKV("# c\nName = Calc\nexec=calc\nIcon=C\nColor=0xe95420\nbad line\n")
  check(kv.name == "Calc" and kv.exec == "calc" and kv.color == "0xe95420", "key=value parsing")
  check(color("0xe95420") == 0xe95420 and color("#102030") == 0x102030 and color("x", 7) == 7 and color(5) == 5, "colours")
  local app = parseApp("Name=Clock\nExec=clock\nIcon=Ck\n", "clock.app")
  check(app and app.id == "clock" and app.icon == "CK" and app.color == nil, "an .app file")
  check(parseApp("Name=No exec\n", "x.app") == nil, "an .app file needs Exec")
  local th = makeTheme("dark", "accent=0x112233\nbogus=1\n")
  check(th.accent == 0x112233 and th.bg == THEMES.dark.bg, "a .theme file changes only its keys")
  check(makeTheme("nothing").bg == THEMES.ubuntu.bg, "an unknown theme falls back to the default")
  check(fit("abcdefgh", 5) == "abc..", "fit")
  check(fit("abc", 5) == "abc" and #fit("abcdefgh", 5) == 5, "fit keeps the width")
  check(mix(0, 0xffffff, 0.5) == 0x808080 and clamp(5, 0, 3) == 3, "mix and clamp")
  -- gestures: a tap, a double tap, a long press, a drag and a swipe
  local g = Gesture.new(8)
  check(g:update(50, 50, true, 0) == "down" and g:update(50, 50, false, 80) == "tap", "a tap")
  check(g:update(50, 50, true, 200) == "down" and g:update(50, 50, false, 260) == "dtap", "a double tap")
  g = Gesture.new(8)
  g:update(50, 50, true, 0)
  check(g:update(50, 50, true, 700) == "long" and g:update(50, 50, true, 800) == nil and g:update(50, 50, false, 900) == nil, "a long press fires once and no tap follows")
  g = Gesture.new(8)
  g:update(50, 50, true, 0)
  check(g:update(80, 50, true, 600) == "drag" and g.dx == 30, "a drag")
  check(g:update(80, 50, false, 650) == "drop", "a slow drag ends in a drop")
  g = Gesture.new(8)
  g:update(100, 20, true, 0)
  g:update(100, 60, true, 100)
  check(g:update(100, 100, false, 150) == "swipe" and g.dir == "down", "a quick move is a swipe")
  g = Gesture.new(8)
  g:update(150, 50, true, 0)
  g:update(100, 50, true, 80)
  g:update(40, 50, false, 120)
  check(g.dir == "left", "a swipe to the left")
  if failed == 0 then print("selftest ok") end
  return
end

-- ---------------------------------------------------------------- the terminal commands

local cmd = arg and arg[1]
if cmd == "enable" or cmd == "disable" then
  local ok, err = setEnabled(cmd == "enable")
  print(ok and (cmd == "enable" and "the desktop starts after boot (graphical.target). Back to text: desktop disable"
                or "the text terminal starts at boot (multi-user.target)") or ("desktop: " .. tostring(err)))
  return
elseif cmd == "status" then
  print("desktop: " .. (isEnabled() and "enabled at boot" or "disabled at boot (desktop enable)"))
  print("touch: " .. ((touch and touch.read) and "yes" or "no (keyboard pointer)"))
  for _, d in ipairs({ APPS_DIR, THEMES_DIR, WALL_DIR }) do print(d .. ": " .. #listDir(d) .. " files") end
  return
elseif cmd == "list" then
  for _, d in ipairs({ APPS_DIR, THEMES_DIR, WALL_DIR }) do
    for _, f in ipairs(listDir(d)) do print(d .. "/" .. f) end
  end
  return
elseif cmd == "install" and arg[2] then
  for i = 2, #arg do
    local ok, msg = installPackage(arg[i])
    print((ok and "installed " or "desktop: ") .. msg)
  end
  return
elseif cmd == "remove" and arg[2] then
  for i = 2, #arg do
    local ok, msg = removePackage(arg[i])
    print((ok and "removed " or "desktop: ") .. msg)
  end
  return
elseif cmd and cmd ~= "start" then
  print("usage: desktop [start|enable|disable|status|list|install NAME|remove NAME]")
  return
end

if not gfx then
  print("desktop needs the graphics: update the firmware (SystemUpdateBeta)")
  return
end

-- ---------------------------------------------------------------- the desktop

local conf = readConf()
local theme = makeTheme(conf.theme or "ubuntu", readFile(THEMES_DIR .. "/" .. (conf.theme or "") .. ".theme"))
local wallTop, wallBottom = theme.wall_top, theme.wall_bottom
if conf.wallpaper then
  local wk = parseKV(readFile(WALL_DIR .. "/" .. conf.wallpaper .. ".wall"))
  wallTop, wallBottom = color(wk.top, wallTop), color(wk.bottom, wallBottom)
end

local W, H, K, U            -- screen size, scale (1 on a small screen, more on a big one), the text line height
local BAR_H, TASK_H
local apps, hidden = {}, {}
local windows, focusId, nextId = {}, nil, 1
local page, menuOpen, quickOpen, popup, toast, toastUntil = 1, false, false, nil, nil, 0
local menuScroll = 0
local gesture
local running = true
local drag = nil            -- { kind = "move"|"resize"|"scroll"|"slider", ... }
local now = 0

local function text(x, y, s, c, size) gfx.text(math.floor(x), math.floor(y), s, c, size or K) end
local function tw(s, size) return #s * 6 * (size or K) end
local function showToast(s) toast, toastUntil = s, now + 2200 end

local function setHidden(list)
  hidden = {}
  for id in (list or ""):gmatch("[^,%s]+") do hidden[id] = true end
end

-- the apps: built-in windows, the .app files, then every program of /usr/local/bin that has no .app file
local BUILTIN = {
  { id = "files", name = "Files", icon = "Fi", color = 0x3584e4, kind = "files" },
  { id = "settings", name = "Settings", icon = "St", color = 0x77767b, kind = "settings" },
  { id = "monitor", name = "Monitor", icon = "Mo", color = 0x26a269, kind = "monitor" },
  { id = "about", name = "About", icon = "Ab", color = 0xe95420, kind = "about" },
}

local function loadApps()
  apps = {}
  local seen = {}
  for _, a in ipairs(BUILTIN) do apps[#apps + 1] = a; seen[a.id] = true end
  for _, f in ipairs(listDir(APPS_DIR)) do
    local a = parseApp(readFile(APPS_DIR .. "/" .. f) or "", f)
    if a and not seen[a.id] then
      a.color = a.color or iconColor(a.name)
      apps[#apps + 1] = a
      seen[a.id] = true
      seen[a.exec] = true
    end
  end
  for _, f in ipairs(listDir("/usr/local/bin")) do
    if f ~= "desktop" and not seen[f] and not f:find("%.") then
      apps[#apps + 1] = { id = f, name = f, exec = f, icon = f:sub(1, 2):upper(), color = iconColor(f), comment = "program" }
      seen[f] = true
    end
  end
end

local function visibleApps()
  local out = {}
  for _, a in ipairs(apps) do if not hidden[a.id] then out[#out + 1] = a end end
  return out
end

-- ---- running a program full screen: the desktop gives the screen back, runs it, and takes it again
local function runProgram(app)
  local path = app.exec:find("/", 1, true) and app.exec or ("/usr/local/bin/" .. app.exec)
  local words = {}
  for wd in app.exec:gmatch("%S+") do words[#words + 1] = wd end
  if #words > 1 and not app.exec:find("/", 1, true) then
    path = "/usr/local/bin/" .. words[1]
  elseif #words > 1 then
    path = words[1]
  end
  local src = readFile(path)
  if not src then showToast("not found: " .. path); return end
  local chunk, err = load(src, "=" .. (words[1] or app.exec))
  if not chunk then showToast("error: " .. tostring(err):sub(1, 40)); return end
  local savedArg = arg
  local newArg = {}
  for i = 2, #words do newArg[i - 1] = words[i] end
  arg = newArg
  gfx.close()
  local ok, problem = pcall(chunk)
  arg = savedArg
  local w2, h2 = gfx.open("native")
  if w2 then W, H = w2, h2 end
  if not ok and not tostring(problem):find("interrupted", 1, true) then showToast(fit(tostring(problem), 36)) end
end

-- ---- windows
local function newWindow(app)
  for _, win in ipairs(windows) do
    if win.app.id == app.id then focusId = win.id; win.min = false; return win end
  end
  local ww, wh = math.min(W - 8 * K, 200 * K), math.min(H - BAR_H - TASK_H - 8 * K, 110 * K)
  local off = ((#windows) % 4) * 8 * K
  local win = { id = nextId, app = app, title = app.name, x = 4 * K + off, y = BAR_H + 4 * K + off, w = ww, h = wh, scroll = 0,
                max = false, min = false, dir = "/", sel = nil }
  win.x = clamp(win.x, 0, math.max(0, W - win.w))
  win.y = clamp(win.y, BAR_H, math.max(BAR_H, H - TASK_H - win.h))
  nextId = nextId + 1
  windows[#windows + 1] = win
  focusId = win.id
  return win
end

local function launch(app)
  menuOpen, quickOpen, popup = false, false, nil
  if app.kind then newWindow(app) else runProgram(app) end
end

local function windowRect(win)
  if win.max then return 0, BAR_H, W, H - BAR_H - TASK_H end
  return win.x, win.y, win.w, win.h
end

local function focusWindow(win)
  for i, other in ipairs(windows) do
    if other == win then table.remove(windows, i); break end
  end
  windows[#windows + 1] = win
  focusId = win.id
  win.min = false
end

local function closeWindow(win)
  for i, other in ipairs(windows) do
    if other == win then table.remove(windows, i); break end
  end
  focusId = windows[#windows] and windows[#windows].id or nil
end

local function winAt(x, y)
  for i = #windows, 1, -1 do
    local win = windows[i]
    if not win.min then
      local wx, wy, ww, wh = windowRect(win)
      if x >= wx and x < wx + ww and y >= wy and y < wy + wh then return win end
    end
  end
  return nil
end

-- ---- the content of the built-in windows
local sysInfo = { at = -10000 }
local function refreshInfo()
  if now - sysInfo.at < 1500 then return end
  sysInfo.at = now
  local free, total = 0, 0
  if sys.heap then free, total = sys.heap() end
  sysInfo.free, sysInfo.total = free or 0, total or 0
  if sys.battery then sysInfo.bat, sysInfo.mv, sysInfo.charging = sys.battery() end
  sysInfo.wifi = net and net.connected and net.connected() and (net.ssid and net.ssid() or "connected") or "off"
  sysInfo.ip = net and net.ip and net.ip() or ""
end

local function fileEntries(dir)
  local out = {}
  if dir ~= "/" then out[1] = ".." end
  for _, name in ipairs(listDir(dir)) do out[#out + 1] = name end
  if fs and fs.info then
    local ok, info = pcall(fs.info, dir)
    if ok and type(info) == "table" then
      for _, e in ipairs(info) do
        if type(e) == "table" and e.name and e.dir then
          local present = false
          for _, n in ipairs(out) do if n == e.name then present = true; break end end
          if not present then out[#out + 1] = e.name end
        end
      end
    end
  end
  return out
end

local function isDir(parent, name)
  if name == ".." then return true end
  local path = (parent == "/" and "" or parent) .. "/" .. name
  if fs and fs.stat then
    local ok, st = pcall(fs.stat, path)
    if ok and type(st) == "table" then return st.dir == true or st.type == "dir" end
  end
  return not name:find("%.")
end

local function slider(x, y, w, h, value, maxv, c)
  gfx.fill(x, y + h // 2 - K, w, 2 * K, theme.border)
  local px = x + math.floor(w * clamp(value / maxv, 0, 1))
  gfx.fill(x, y + h // 2 - K, px - x, 2 * K, c)
  gfx.disc(px, y + h // 2, h // 2, c)
end

-- the places that react to a tap or a drag, collected while drawing: x, y, w, h, action
local hits, hitCount = {}, 0
local function hit(x, y, w, h, action, arg1)
  hitCount = hitCount + 1
  local e = hits[hitCount]
  if not e then e = {}; hits[hitCount] = e end
  e.x, e.y, e.w, e.h, e.action, e.arg = math.floor(x), math.floor(y), math.floor(w), math.floor(h), action, arg1
end

local function drawWindowContent(win, x, y, w, h)
  local rowH = 11 * K
  local focused = win.id == focusId
  if win.app.kind == "files" then
    local entries = fileEntries(win.dir)
    local rows = math.max(1, h // rowH)
    win.scroll = clamp(win.scroll, 0, math.max(0, #entries - rows))
    gfx.fill(x, y, w, h, theme.panel)
    for r = 1, rows do
      local i = win.scroll + r
      local name = entries[i]
      if not name then break end
      local dirEntry = isDir(win.dir, name)
      local ry = y + (r - 1) * rowH
      if win.sel == i then gfx.fill(x, ry, w, rowH, theme.accent) end
      gfx.fill(x + 2 * K, ry + 2 * K, 6 * K, 6 * K, dirEntry and 0xf5c211 or theme.dim)
      text(x + 11 * K, ry + 2 * K, fit(name, (w - 14 * K) // (6 * K)), win.sel == i and 0xffffff or theme.text)
      hit(x, ry, w, rowH, "file", { win = win, index = i, name = name, dir = dirEntry })
    end
    hit(x, y, w, h, "scroll", win)
    text(x + 2 * K, y + h - 9 * K, fit(win.dir, (w - 4 * K) // (6 * K)), theme.dim)
  elseif win.app.kind == "settings" then
    gfx.fill(x, y, w, h, theme.panel)
    local bright = tonumber(sys.setting and sys.setting("brightness") or "") or 128
    local vol = tonumber(sys.setting and sys.setting("volume") or "") or 50
    text(x + 4 * K, y + 4 * K, "Brightness", theme.text)
    slider(x + 4 * K, y + 14 * K, w - 8 * K, 10 * K, bright, 255, theme.accent)
    hit(x + 4 * K, y + 12 * K, w - 8 * K, 14 * K, "slider", { key = "brightness", max = 255, min = 10, x = x + 4 * K, w = w - 8 * K })
    text(x + 4 * K, y + 30 * K, "Volume", theme.text)
    slider(x + 4 * K, y + 40 * K, w - 8 * K, 10 * K, vol, 100, theme.accent)
    hit(x + 4 * K, y + 38 * K, w - 8 * K, 14 * K, "slider", { key = "volume", max = 100, min = 0, x = x + 4 * K, w = w - 8 * K })
    text(x + 4 * K, y + 56 * K, "Theme: " .. (conf.theme or "ubuntu"), theme.text)
    local bw = 40 * K
    local names = { "ubuntu", "dark", "light" }
    for i, n in ipairs(names) do
      local bx = x + 4 * K + (i - 1) * (bw + 3 * K)
      gfx.fill(bx, y + 66 * K, bw, 11 * K, (conf.theme or "ubuntu") == n and theme.accent or theme.light or theme.title)
      text(bx + 3 * K, y + 68 * K, n, 0xffffff)
      hit(bx, y + 66 * K, bw, 11 * K, "theme", n)
    end
    text(x + 4 * K, y + 82 * K, "More themes: desktop install NAME", theme.dim, 1)
  elseif win.app.kind == "monitor" then
    refreshInfo()
    gfx.fill(x, y, w, h, theme.panel)
    local used = sysInfo.total > 0 and (sysInfo.total - sysInfo.free) or 0
    text(x + 4 * K, y + 4 * K, "Memory " .. sysInfo.free .. " / " .. sysInfo.total .. " KB free", theme.text)
    gfx.fill(x + 4 * K, y + 14 * K, w - 8 * K, 8 * K, theme.border)
    if sysInfo.total > 0 then gfx.fill(x + 4 * K, y + 14 * K, math.floor((w - 8 * K) * used / sysInfo.total), 8 * K, theme.accent) end
    text(x + 4 * K, y + 28 * K, "Battery " .. tostring(sysInfo.bat or "?") .. "%" .. (sysInfo.charging and " charging" or ""), theme.text)
    gfx.fill(x + 4 * K, y + 38 * K, w - 8 * K, 8 * K, theme.border)
    gfx.fill(x + 4 * K, y + 38 * K, math.floor((w - 8 * K) * clamp((sysInfo.bat or 0) / 100, 0, 1)), 8 * K, 0x26a269)
    text(x + 4 * K, y + 52 * K, "WiFi " .. tostring(sysInfo.wifi), theme.text)
    text(x + 4 * K, y + 64 * K, "IP " .. tostring(sysInfo.ip), theme.dim)
    text(x + 4 * K, y + 76 * K, "Uptime " .. math.floor((sys.uptime and sys.uptime() or 0)) .. " s", theme.dim)
  else
    gfx.fill(x, y, w, h, theme.panel)
    text(x + 4 * K, y + 4 * K, "Cardputer Linux desktop", theme.text)
    text(x + 4 * K, y + 18 * K, "touch: " .. ((touch and touch.read) and "yes" or "no (keys)"), theme.dim)
    text(x + 4 * K, y + 30 * K, "screen " .. W .. "x" .. H, theme.dim)
    text(x + 4 * K, y + 42 * K, "apps " .. #apps, theme.dim)
    text(x + 4 * K, y + 58 * K, "Packages: desktop install NAME", theme.dim, 1)
  end
  if focused then gfx.rect(x - 1, y - 1, w + 2, h + 2, theme.accent) end
end

local function drawWindow(win)
  local x, y, w, h = windowRect(win)
  local tb = 12 * K
  local focused = win.id == focusId
  gfx.fill(x, y, w, tb, focused and theme.title or theme.bar)
  text(x + 4 * K, y + 2 * K, fit(win.title, (w - 40 * K) // (6 * K)), theme.text)
  -- close, maximize, minimize
  gfx.fill(x + w - 11 * K, y + 1 * K, 10 * K, 10 * K, theme.danger)
  text(x + w - 9 * K, y + 2 * K, "x", 0xffffff)
  gfx.rect(x + w - 22 * K, y + 2 * K, 8 * K, 8 * K, theme.text)
  gfx.hline(x + w - 32 * K, x + w - 26 * K, y + 9 * K, theme.text)
  hit(x + w - 11 * K, y, 11 * K, tb, "close", win)
  hit(x + w - 23 * K, y, 11 * K, tb, "maximize", win)
  hit(x + w - 34 * K, y, 11 * K, tb, "minimize", win)
  hit(x, y, w - 34 * K, tb, "title", win)
  drawWindowContent(win, x, y + tb, w, h - tb)
  if not win.max then
    gfx.triangle(x + w - 1, y + h - 8 * K, x + w - 1, y + h - 1, x + w - 8 * K, y + h - 1, theme.dim)  -- the resize grip
    hit(x + w - 10 * K, y + h - 10 * K, 10 * K, 10 * K, "grip", win)
  end
  hit(x, y, w, h, "focus", win)
end

-- ---- the icons, the bars, the menus
local function layoutIcons()
  local cell = 46 * K
  local cols = math.max(1, W // cell)
  local top = BAR_H + 4 * K
  local rows = math.max(1, (H - TASK_H - top) // (cell + 2 * K))
  return cell, cols, rows, top
end

local function drawIcon(x, y, size, app, highlight)
  local c = app.color or iconColor(app.name)
  gfx.fill(x + 2 * K, y, size - 4 * K, size, c)
  gfx.fill(x, y + 2 * K, size, size - 4 * K, c)
  gfx.disc(x + 3 * K, y + 3 * K, 3 * K, c)
  gfx.disc(x + size - 3 * K - 1, y + 3 * K, 3 * K, c)
  gfx.disc(x + 3 * K, y + size - 3 * K - 1, 3 * K, c)
  gfx.disc(x + size - 3 * K - 1, y + size - 3 * K - 1, 3 * K, c)
  if highlight then gfx.rect(x - 1, y - 1, size + 2, size + 2, 0xffffff) end
  local label = app.icon or app.name:sub(1, 2)
  text(x + (size - tw(label, K * 2)) // 2, y + (size - 8 * K * 2) // 2, label, 0xffffff, K * 2)
end

local function drawDesktop()
  -- the wallpaper: a vertical gradient in bands
  local band = math.max(2, H // 40)
  for y = 0, H - 1, band do gfx.fill(0, y, W, band, mix(wallTop, wallBottom, y / H)) end
  local list = visibleApps()
  local cell, cols, rows, top = layoutIcons()
  local perPage = cols * rows
  local pages = math.max(1, math.ceil(#list / perPage))
  page = clamp(page, 1, pages)
  local xPad = (W - cols * cell) // 2
  for n = 1, perPage do
    local app = list[(page - 1) * perPage + n]
    if not app then break end
    local col, row = (n - 1) % cols, (n - 1) // cols
    local x, y = xPad + col * cell + (cell - 28 * K) // 2, top + row * (cell + 2 * K)
    drawIcon(x, y, 28 * K, app)
    local chars = cell // (6 * K)
    local label = fit(app.name, chars)
    text(xPad + col * cell + (cell - tw(label)) // 2, y + 30 * K, label, 0xffffff)
    hit(xPad + col * cell, y, cell, cell, "icon", app)
  end
  if pages > 1 then
    for p = 1, pages do gfx.disc(W // 2 + (p - (pages + 1) / 2) * 8 * K, H - TASK_H - 6 * K, 2 * K, p == page and 0xffffff or theme.dim) end
  end
end

local function clockText()
  local s = sys.date and sys.date("%H:%M") or ""
  return type(s) == "string" and s or ""
end

local function drawBars()
  refreshInfo()
  gfx.fill(0, 0, W, BAR_H, theme.bar)
  text(4 * K, (BAR_H - 8 * K) // 2, "Activities", theme.text)
  hit(0, 0, 60 * K, BAR_H, "menu")
  local c = clockText()
  text((W - tw(c)) // 2, (BAR_H - 8 * K) // 2, c, theme.text)
  local right = (sysInfo.bat and (tostring(sysInfo.bat) .. "%") or "") .. (sysInfo.wifi ~= "off" and " wifi" or "")
  text(W - tw(right) - 4 * K, (BAR_H - 8 * K) // 2, right, theme.dim)
  hit(W // 2, 0, W // 2, BAR_H, "quick")
  -- the task bar
  gfx.fill(0, H - TASK_H, W, TASK_H, theme.bar)
  gfx.fill(2 * K, H - TASK_H + 2 * K, 30 * K, TASK_H - 4 * K, menuOpen and theme.accent or theme.title)
  text(5 * K, H - TASK_H + (TASK_H - 8 * K) // 2, "Menu", 0xffffff)
  hit(0, H - TASK_H, 34 * K, TASK_H, "menu")
  local x = 36 * K
  local tabW = math.min(48 * K, math.max(20 * K, (W - x - 4 * K) // math.max(1, #windows)))
  for _, win in ipairs(windows) do
    local on = win.id == focusId and not win.min
    gfx.fill(x, H - TASK_H + 2 * K, tabW - 2 * K, TASK_H - 4 * K, on and theme.accent or theme.panel)
    text(x + 2 * K, H - TASK_H + (TASK_H - 8 * K) // 2, fit(win.title, (tabW - 6 * K) // (6 * K)), on and 0xffffff or theme.text)
    hit(x, H - TASK_H, tabW, TASK_H, "tab", win)
    x = x + tabW
  end
end

local function drawMenu()
  local list = visibleApps()
  local mw, rowH = math.min(W, 110 * K), 12 * K
  local mh = math.min(H - BAR_H - TASK_H, #list * rowH + 4 * K)
  local mx, my = 0, H - TASK_H - mh
  gfx.fill(mx, my, mw, mh, theme.panel)
  gfx.rect(mx, my, mw, mh, theme.border)
  local rows = (mh - 4 * K) // rowH
  menuScroll = clamp(menuScroll, 0, math.max(0, #list - rows))
  for r = 1, rows do
    local app = list[menuScroll + r]
    if not app then break end
    local ry = my + 2 * K + (r - 1) * rowH
    gfx.fill(mx + 3 * K, ry + 1 * K, 9 * K, 9 * K, app.color or iconColor(app.name))
    text(mx + 15 * K, ry + 2 * K, fit(app.name, (mw - 18 * K) // (6 * K)), theme.text)
    hit(mx, ry, mw, rowH, "menuitem", app)
  end
  hit(mx, my, mw, mh, "menuscroll")
end

local function drawQuick()
  local qw, qh = math.min(W, 150 * K), 76 * K
  local qx, qy = W - qw, BAR_H
  gfx.fill(qx, qy, qw, qh, theme.panel)
  gfx.rect(qx, qy, qw, qh, theme.border)
  local bright = tonumber(sys.setting and sys.setting("brightness") or "") or 128
  local vol = tonumber(sys.setting and sys.setting("volume") or "") or 50
  text(qx + 4 * K, qy + 3 * K, "Brightness", theme.dim)
  slider(qx + 4 * K, qy + 12 * K, qw - 8 * K, 10 * K, bright, 255, theme.accent)
  hit(qx + 4 * K, qy + 10 * K, qw - 8 * K, 14 * K, "slider", { key = "brightness", max = 255, min = 10, x = qx + 4 * K, w = qw - 8 * K })
  text(qx + 4 * K, qy + 27 * K, "Volume", theme.dim)
  slider(qx + 4 * K, qy + 36 * K, qw - 8 * K, 10 * K, vol, 100, theme.accent)
  hit(qx + 4 * K, qy + 34 * K, qw - 8 * K, 14 * K, "slider", { key = "volume", max = 100, min = 0, x = qx + 4 * K, w = qw - 8 * K })
  local bw = (qw - 12 * K) // 3
  local labels = { { "Text", "exit" }, { "Reboot", "reboot" }, { "Off", "poweroff" } }
  for i, l in ipairs(labels) do
    local bx = qx + 4 * K + (i - 1) * (bw + 2 * K)
    gfx.fill(bx, qy + 54 * K, bw, 16 * K, i == 3 and theme.danger or theme.title)
    text(bx + (bw - tw(l[1])) // 2, qy + 58 * K, l[1], 0xffffff)
    hit(bx, qy + 54 * K, bw, 16 * K, "power", l[2])
  end
  hit(qx, qy, qw, qh, "quickpanel")
end

local function drawPopup()
  local p = popup
  local pw, ph = 56 * K, 26 * K
  local px, py = clamp(p.x, 0, W - pw), clamp(p.y, BAR_H, H - TASK_H - ph)
  gfx.fill(px, py, pw, ph, theme.panel)
  gfx.rect(px, py, pw, ph, theme.border)
  text(px + 4 * K, py + 3 * K, "Open", theme.text)
  hit(px, py, pw, 13 * K, "popopen", p.app)
  text(px + 4 * K, py + 16 * K, "Hide", theme.text)
  hit(px, py + 13 * K, pw, 13 * K, "pophide", p.app)
  hit(0, 0, W, H, "popclose")
end

local function render()
  hitCount = 0
  hit(0, BAR_H, W, H - BAR_H - TASK_H, "desktop")  -- first, so everything drawn later is tested before it
  drawDesktop()
  -- the hit list is searched from the end, so what is drawn later (on top) is tested first
  for _, win in ipairs(windows) do if not win.min then drawWindow(win) end end
  drawBars()
  if menuOpen then drawMenu() end
  if quickOpen then drawQuick() end
  if popup then drawPopup() end
  if toast and now < toastUntil then
    local tx = (W - tw(toast)) // 2
    gfx.fill(tx - 4 * K, H - TASK_H - 16 * K, tw(toast) + 8 * K, 12 * K, 0x000000)
    text(tx, H - TASK_H - 14 * K, toast, 0xffffff)
  end
  if pointer.keyboard then
    local px, py = math.floor(pointer.x), math.floor(pointer.y)
    gfx.triangle(px, py, px + 6 * K, py + 4 * K, px + 3 * K, py + 7 * K, 0xffffff)
  end
  gfx.flush()
end

-- the first hit of the list (from the top) under the point
local function hitAt(x, y, only)
  for i = hitCount, 1, -1 do
    local e = hits[i]
    if x >= e.x and x < e.x + e.w and y >= e.y and y < e.y + e.h and (not only or e.action == only) then return e end
  end
  return nil
end

-- the value of a slider for a point, saved as a setting
local function setSlider(a, x)
  local v = a.min + (a.max - a.min) * clamp((x - a.x) / a.w, 0, 1)
  v = math.floor(v + 0.5)
  if sys.setting then pcall(sys.setting, a.key, v) end
  if a.key == "volume" and audio and audio.volume then pcall(audio.volume, v) end
end

local function saveTheme(name)
  conf.theme = name
  theme = makeTheme(name, readFile(THEMES_DIR .. "/" .. name .. ".theme"))
  wallTop, wallBottom = theme.wall_top, theme.wall_bottom
  conf.wallpaper = nil
  writeUserConf(conf)
end

local function doAction(e, kind)
  local a = e.action
  if a == "close" then closeWindow(e.arg)
  elseif a == "maximize" then e.arg.max = not e.arg.max
  elseif a == "minimize" then e.arg.min = true; focusId = nil
  elseif a == "tab" then
    if e.arg.id == focusId and not e.arg.min then e.arg.min = true; focusId = nil else focusWindow(e.arg) end
  elseif a == "menu" then menuOpen, quickOpen, popup = not menuOpen, false, nil
  elseif a == "quick" then quickOpen, menuOpen = not quickOpen, false
  elseif a == "menuitem" or a == "icon" then if kind == "long" and a == "icon" then popup = { x = e.x, y = e.y, app = e.arg } else launch(e.arg) end
  elseif a == "popopen" then launch(e.arg)
  elseif a == "pophide" then
    hidden[e.arg.id] = true
    local ids = {}
    for id in pairs(hidden) do ids[#ids + 1] = id end
    table.sort(ids)
    conf.hidden = table.concat(ids, ",")
    writeUserConf(conf)
    popup = nil
  elseif a == "popclose" then popup = nil
  elseif a == "theme" then saveTheme(e.arg)
  elseif a == "power" then
    if e.arg == "exit" then running = false
    elseif e.arg == "reboot" and sys.reboot then running = false; gfx.close(); sys.reboot()
    elseif e.arg == "poweroff" and sys.powerOff then running = false; gfx.close(); sys.powerOff() end
  elseif a == "file" then
    local win, name = e.arg.win, e.arg.name
    focusWindow(win)
    if e.arg.dir then
      if name == ".." then win.dir = win.dir:match("^(.*)/[^/]*$") or "/"; if win.dir == "" then win.dir = "/" end
      else win.dir = (win.dir == "/" and "" or win.dir) .. "/" .. name end
      win.scroll, win.sel = 0, nil
    elseif win.sel == e.arg.index then
      local path = (win.dir == "/" and "" or win.dir) .. "/" .. name
      if name:match("%.lua$") then launch({ id = path, name = name, exec = path }) else showToast(name) end
    else
      win.sel = e.arg.index
    end
  elseif a == "focus" then focusWindow(e.arg)
  end
end

-- ---------------------------------------------------------------- the loop

local function handleEvent(ev)
  local x, y = gesture.x, gesture.y
  if ev == "down" then
    drag = nil
    local s = hitAt(x, y, "slider")
    if s and (quickOpen or (winAt(x, y) and s.arg)) then drag = { kind = "slider", a = s.arg }; setSlider(s.arg, x) ; return end
    local g = hitAt(x, y, "grip")
    if g and winAt(x, y) == g.arg then drag = { kind = "resize", win = g.arg }; focusWindow(g.arg); return end
    local t = hitAt(x, y, "title")
    if t then drag = { kind = "move", win = t.arg }; focusWindow(t.arg); return end
    local sc = hitAt(x, y, "scroll")
    if sc then drag = { kind = "scroll", win = sc.arg, acc = 0 } end
  elseif ev == "drag" then
    if not drag then return end
    if drag.kind == "slider" then setSlider(drag.a, x)
    elseif drag.kind == "move" and not drag.win.max then
      drag.win.x = clamp(drag.win.x + gesture.dx, -drag.win.w + 24 * K, W - 24 * K)
      drag.win.y = clamp(drag.win.y + gesture.dy, BAR_H, H - TASK_H - 12 * K)
    elseif drag.kind == "resize" then
      drag.win.w = clamp(drag.win.w + gesture.dx, 70 * K, W - drag.win.x)
      drag.win.h = clamp(drag.win.h + gesture.dy, 40 * K, H - TASK_H - drag.win.y)
    elseif drag.kind == "scroll" then
      drag.acc = drag.acc - gesture.dy
      local step = 11 * K
      while drag.acc >= step do drag.win.scroll = drag.win.scroll + 1; drag.acc = drag.acc - step end
      while drag.acc <= -step do drag.win.scroll = drag.win.scroll - 1; drag.acc = drag.acc + step end
    end
  elseif ev == "drop" then
    drag = nil
  elseif ev == "swipe" then
    local d = gesture.dir
    local startY = gesture.y0
    drag = nil
    if d == "down" and startY < BAR_H + 6 * K then quickOpen, menuOpen = true, false
    elseif d == "up" and startY > H - TASK_H - 6 * K then menuOpen, quickOpen = true, false
    elseif d == "up" and quickOpen then quickOpen = false
    elseif d == "down" and menuOpen then menuOpen = false
    elseif (d == "left" or d == "right") and not winAt(gesture.x0, gesture.y0) and not menuOpen and not quickOpen then
      page = page + (d == "left" and 1 or -1)
    elseif menuOpen and (d == "up" or d == "down") then
      menuScroll = menuScroll + (d == "up" and 3 or -3)
    end
  elseif ev == "tap" or ev == "dtap" or ev == "long" then
    drag = nil
    -- a tap outside an open menu or panel closes it
    local e = hitAt(x, y)
    if popup and (not e or e.action ~= "popopen" and e.action ~= "pophide") then popup = nil; return end
    if menuOpen and (not e or (e.action ~= "menuitem" and e.action ~= "menuscroll" and e.action ~= "menu")) then menuOpen = false; return end
    if quickOpen and (not e or (e.action ~= "power" and e.action ~= "slider" and e.action ~= "quickpanel" and e.action ~= "quick")) then quickOpen = false; return end
    if e and e.action == "title" and ev == "dtap" then e.arg.max = not e.arg.max; return end
    if e and e.action == "icon" then
      if ev == "long" then doAction(e, "long") elseif ev == "tap" then doAction(e, "tap") end
      return
    end
    if ev == "long" then return end
    if e and e.action ~= "desktop" and e.action ~= "title" and e.action ~= "scroll" and e.action ~= "focus" and e.action ~= "menuscroll"
       and e.action ~= "quickpanel" and e.action ~= "slider" and e.action ~= "grip" then
      doAction(e, "tap")
    elseif e and (e.action == "scroll" or e.action == "focus") then
      local win = winAt(x, y)
      if win then focusWindow(win) end
      local f = hitAt(x, y, "file")
      if f then doAction(f, "tap") end
    elseif e and e.action == "slider" then
      setSlider(e.arg, x)
    end
  end
end

local function main()
  local w, h = gfx.open("native")  -- the screen in its own pixels (800x480); an older firmware ignores the argument
  if not w then print("desktop: " .. tostring(h)); return end
  W, H = w, h
  K = clamp(math.min(W, H) // 240, 1, 4)
  if W >= 400 or H >= 400 then K = math.max(K, 2) end
  U = 8 * K
  BAR_H, TASK_H = 12 * K, 14 * K
  gesture = Gesture.new(8 * K)
  setHidden(conf.hidden)
  loadApps()
  pointer.x, pointer.y = W // 2, H // 2
  while running do
    now = sys.millis()
    local held = key.down and key.down() or {}
    local pressed = {}
    local k = key.poll()
    while k do
      if k == "ctrl-q" then running = false end
      pressed[k] = true
      k = key.poll()
    end
    local heldSet = {}
    for _, name in ipairs(held) do heldSet[name] = true end
    if heldSet.enter then pressed.enter = true end
    if pressed[" "] and pointer.keyboard then pointer.down = true end
    readPointer(W, H, held, pressed)
    if pointer.keyboard and heldSet[" "] then pointer.down = true end
    local ev = gesture:update(pointer.x, pointer.y, pointer.down, now)
    if ev then handleEvent(ev) end
    -- the keyboard shortcuts: tab opens the menu, escape closes what is open
    if pressed["tab"] then menuOpen, quickOpen = not menuOpen, false end
    if pressed["esc"] or pressed["escape"] then menuOpen, quickOpen, popup = false, false, nil end
    render()
    sys.sleep(15)
  end
end

local ok, problem = pcall(main)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("desktop: " .. tostring(problem)) end
