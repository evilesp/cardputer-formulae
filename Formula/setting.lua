#!lua
-- setting: the settings of the Cardputer in pictures. WiFi: scan the networks, connect with the password, and save one
-- to connect to at boot. Brightness and volume, saved and used at every boot. Connect at boot: on or off.
-- w s move, enter chooses, a d change a value, backspace goes back, ctrl-q goes back (at the main menu it quits).
-- Needs the ui package and firmware v0.1.0.16(beta) (net.scan, net.connect, sys.setting). Run it with --selftest to check
-- the helpers.

-- the bars of a signal of rssi dBm: 0 to 4
local function bars(rssi)
  if rssi >= -55 then return 4 end
  if rssi >= -67 then return 3 end
  if rssi >= -75 then return 2 end
  if rssi >= -85 then return 1 end
  return 0
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- a password on the screen: a star for every letter
local function masked(text)
  return string.rep("*", #text)
end

-- a text cut to n characters
local function fit(text, n)
  if #text <= n then return text end
  return text:sub(1, n - 2) .. ".."
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(bars(-40) == 4 and bars(-60) == 3 and bars(-70) == 2 and bars(-80) == 1 and bars(-95) == 0, "the signal bars")
  check(clamp(5, 10, 200) == 10 and clamp(300, 10, 200) == 200 and clamp(50, 10, 200) == 50, "a value stays in its range")
  check(masked("abc") == "***" and masked("") == "", "a password shows stars")
  check(fit("short", 10) == "short" and fit("a very long network name", 10) == "a very l..", "a long name is cut")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("setting needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not net or not net.scan or not net.saved or not sys.setting then
  print("setting needs firmware v0.1.0.16(beta) or newer: SystemBackUpdate")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("setting: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local T = ui.theme

-- ---- the WiFi part ----

-- the password of a network, typed on the screen; nil when the user backs out
local function askPassword(ssid)
  local text = ""
  while true do
    gfx.clear(T.bg)
    ui.panel(20, 30, 200, 75, "password: " .. fit(ssid, 18))
    ui.label(28, 50, masked(text) .. "_", T.text)
    ui.label(28, 70, "enter: connect   ctrl-q: back", T.dim)
    gfx.flush()
    local k = key.poll()
    while k do
      if k == "enter" then return text
      elseif k == "backspace" then text = text:sub(1, -2)
      elseif k == "ctrl-q" then return nil
      elseif #k == 1 and k:byte() >= 32 and k:byte() < 127 and #text < 63 then text = text .. k
      end
      k = key.poll()
    end
    sys.sleep(25)
  end
end

-- the list of networks in range; returns the one chosen, or nil
local function pickNetwork()
  gfx.clear(T.bg)
  ui.panel(2, 2, W - 4, H - 4, "WiFi")
  ui.label(14, 40, "scanning, a few seconds...", T.text)
  gfx.flush()
  local list, err = net.scan()
  if not list then
    ui.message("Scan failed", { tostring(err) })
    return nil
  end
  local seen, nets = {}, {}
  for _, n in ipairs(list) do
    if not seen[n.ssid] then
      seen[n.ssid] = true
      nets[#nets + 1] = n
    end
  end
  if #nets == 0 then
    ui.message("No networks", { "none in range" })
    return nil
  end
  local sel, top, rows = 1, 1, 7
  while true do
    gfx.clear(T.bg)
    ui.panel(2, 2, W - 4, H - 4, "choose a network")
    for i = 0, rows - 1 do
      local idx = top + i
      local n = nets[idx]
      if not n then break end
      local y = 18 + i * 14
      local ink = T.text
      if idx == sel then
        gfx.fill(6, y - 1, W - 12, 13, T.accent)
        ink = T.bg
      end
      ui.label(10, y + 1, fit(n.ssid, 22), ink)
      for b = 1, 4 do
        local hgt = b * 2
        gfx.fill(196 + b * 4, y + 9 - hgt, 2, hgt, b <= bars(n.rssi) and ink or T.light)
      end
      if not n.open then ui.label(218, y + 1, "*", ink) end
    end
    gfx.flush()
    local k = key.poll()
    while k do
      local a = ui.keyAction(k)
      if a == "up" then sel = math.max(1, sel - 1)
      elseif a == "down" then sel = math.min(#nets, sel + 1)
      elseif a == "ok" then return nets[sel]
      elseif a == "back" then return nil
      end
      if sel < top then top = sel end
      if sel > top + rows - 1 then top = sel - rows + 1 end
      k = key.poll()
    end
    sys.sleep(25)
  end
end

local function connectFlow()
  local n = pickNetwork()
  if not n then return end
  local pass = ""
  if not n.open then
    pass = askPassword(n.ssid)
    if pass == nil then return end
  end
  gfx.clear(T.bg)
  ui.panel(2, 2, W - 4, H - 4, "WiFi")
  ui.label(14, 40, "connecting to " .. fit(n.ssid, 24) .. "...", T.text)
  gfx.flush()
  local ok, why = net.connect(n.ssid, pass, 15)
  if not ok then
    ui.message("Could not connect", { tostring(why) })
    return
  end
  local c = ui.choose("Connect at boot?", { "Yes, save it", "No" })
  if c == 1 then
    local saved, err = net.save(n.ssid, pass)
    if saved then ui.message("Saved", { n.ssid .. " connects at boot" })
    else ui.message("Not saved", { tostring(err) }) end
  else
    ui.message("Connected", { n.ssid })
  end
end

-- ---- the sliders ----

-- a value from lo to hi with a bar: a and d (or the arrows) change it by step, enter and backspace leave it. Returns the value.
local function slider(title, value, lo, hi, step, apply)
  while true do
    gfx.clear(T.bg)
    ui.panel(2, 2, W - 4, H - 4, title)
    ui.bar(20, 48, 200, 14, value - lo, hi - lo, T.accent, tostring(value))
    ui.label(20, 74, "a d change   enter saved", T.dim)
    ui.label(20, 86, "backspace back", T.dim)
    gfx.flush()
    local k = key.poll()
    while k do
      local a = ui.keyAction(k)
      local new = value
      if a == "left" or a == "down" then new = clamp(value - step, lo, hi)
      elseif a == "right" or a == "up" then new = clamp(value + step, lo, hi)
      elseif a == "ok" or a == "back" then return value
      end
      if new ~= value then
        value = new
        apply(value)
      end
      k = key.poll()
    end
    sys.sleep(25)
  end
end

local function brightness()
  local saved = tonumber(sys.setting("brightness") or "") or 128
  local v = slider("brightness", saved, 10, 255, 16, function(x) sys.setting("brightness", x) end)
  return v
end

local function volume()
  local saved = tonumber(sys.setting("volume") or "") or (audio and audio.volume and audio.volume()) or 50
  return slider("volume", saved, 0, 100, 5, function(x)
    sys.setting("volume", x)
    if audio and audio.synth then pcall(audio.synth, "speaker", "", "sine", 660, 0.08, 16000) end
  end)
end

-- ---- the main menu ----

local function statusLines()
  local line1
  if net.connected() then line1 = "WiFi: " .. fit(net.ssid() or "?", 20) .. "  " .. (net.ip() or "")
  else line1 = "WiFi: not connected" end
  local ssid, auto = net.saved()
  local line2
  if ssid then line2 = "saved: " .. fit(ssid, 18) .. (auto and ", at boot" or ", not at boot")
  else line2 = "no network saved yet" end
  return line1, line2
end

local function mainMenu()
  local sel = 1
  while true do
    local ssid, auto = net.saved()
    local items = {
      "WiFi",
      "Brightness",
      "Volume",
      "Connect at boot: " .. (ssid and (auto and "on" or "off") or "no network"),
      "Quit",
    }
    gfx.clear(T.bg)
    ui.panel(2, 2, W - 4, H - 4, "Settings")
    local line1, line2 = statusLines()
    ui.label(10, 18, line1, T.dim)
    ui.label(10, 28, line2, T.dim)
    for i, item in ipairs(items) do
      local y = 42 + (i - 1) * 14
      local ink = T.text
      if i == sel then
        gfx.fill(8, y - 1, W - 16, 13, T.accent)
        ink = T.bg
      end
      ui.label(12, y + 1, item, ink)
    end
    gfx.flush()
    local k = key.poll()
    while k do
      local a = ui.keyAction(k)
      if k == "ctrl-q" then return end
      if a == "up" then sel = sel > 1 and sel - 1 or #items
      elseif a == "down" then sel = sel < #items and sel + 1 or 1
      elseif a == "ok" then
        if sel == 1 then
          local c = ui.choose("WiFi", { "Scan and connect", "Disconnect", "Back" })
          if c == 1 then connectFlow()
          elseif c == 2 then
            net.disconnect()
            ui.message("WiFi", { "disconnected" })
          end
        elseif sel == 2 then brightness()
        elseif sel == 3 then volume()
        elseif sel == 4 then
          if not ssid then
            ui.message("Connect at boot", { "Save a network first:", "WiFi, Scan and connect." })
          else
            local ok, err = net.setAuto(not auto)
            if not ok then ui.message("Not changed", { tostring(err) }) end
          end
        elseif sel == 5 then return
        end
      end
      k = key.poll()
    end
    sys.sleep(25)
  end
end

local w, h = ui.open()
if not w then
  print("setting: " .. tostring(h))
  return
end
local ok, problem = pcall(mainMenu)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("setting: " .. tostring(problem)) end
