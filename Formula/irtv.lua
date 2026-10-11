#!lua
-- irtv: a remote control on the screen. It shows the buttons you taught the remote app (brew install remote), as large
-- buttons you can press: w a s d move between them, enter sends the signal, keys 1 to 9 send the first nine buttons at
-- once, ctrl-q quits. The signals are the ones saved in /home/user/remote-NAME.rem and the LED pin is the TX pin set in
-- the remote app (pin 44 until you change it).
--   irtv NAME        e.g. irtv tv  (without a name, you choose from your remotes)
-- Needs firmware v0.1.0.13(beta) (graphics and infrared) and the ui package. Run it with --selftest to check the reading.

local CONFIG = "/home/user/.remote"

-- the buttons of a remote file: "NAME|t1 t2 t3" per line
local function parseRemote(text)
  local buttons = {}
  for line in text:gmatch("[^\n]+") do
    local name, times = line:match("^([^|]+)|(.*)$")
    if name then
      local timings = {}
      for t in times:gmatch("%d+") do timings[#timings + 1] = tonumber(t) end
      if #timings >= 2 then buttons[#buttons + 1] = { name = name, timings = timings } end
    end
  end
  return buttons
end

-- the TX pin from the settings file of the remote app ("tx=44"), 44 when there is none
local function txPin(text)
  local n = text and tonumber(text:match("tx=(%d+)"))
  return n or 44
end

-- the names of the remotes in a folder listing ("remote-tv.rem" is "tv")
local function remoteNames(listing)
  local names = {}
  for _, f in ipairs(listing) do
    local n = f:match("^remote%-([%w_%-]+)%.rem$")
    if n then names[#names + 1] = n end
  end
  table.sort(names)
  return names
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local b = parseRemote("Power|9000 4500 560\nVol+|560 560\nbad\n|1 2\n")
  check(#b == 2 and b[1].name == "Power" and #b[1].timings == 3 and b[2].timings[2] == 560, "the buttons are read")
  check(txPin("tx=12\nrx=5\n") == 12 and txPin("rx=5\n") == 44 and txPin(nil) == 44, "the TX pin")
  local names = remoteNames({ "remote-tv.rem", "remote-dvd.rem", "x.txt", "remote-.rem" })
  check(#names == 2 and names[1] == "dvd" and names[2] == "tv", "the remotes are found and sorted")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("irtv needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not ir or not driver then
  print("irtv needs the infrared of firmware v0.1.0.11 or newer")
  return
end
local ui, uiErr = driver.load("ui")
if not ui then
  print("irtv: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local COLS_B = 2
local buttons, tx, name
local sel, message = 1, ""

local function draw()
  gfx.clear(0x0a0c14)
  ui.panel(2, 2, W - 4, H - 4, "remote: " .. name)
  local rows = math.ceil(#buttons / COLS_B)
  local bw, bh = 108, 16
  for i, b in ipairs(buttons) do
    local col, row = (i - 1) % COLS_B, (i - 1) // COLS_B
    local label = (i <= 9 and (i .. " ") or "  ") .. b.name
    ui.button(8 + col * (bw + 4), 20 + row * (bh + 3), bw, bh, label:sub(1, 16), i == sel and "focus" or "normal")
  end
  ui.label(8, H - 24, message ~= "" and message or "enter sends   1-9 send at once", 0x8a94aa)
  gfx.flush()
end

local function send(i)
  local b = buttons[i]
  if not b then return end
  sel = i
  local ok, err = ir.send(tx, b.timings)
  message = ok and ("sent " .. b.name) or ("failed: " .. tostring(err))
end

local function handle(k)
  if k == "ctrl-q" then return false end
  if #k == 1 then k = k:lower() end
  message = ""
  if k:match("^[1-9]$") then
    send(tonumber(k))
    return true
  end
  local a = ui.keyAction(k)
  if a == "up" then sel = math.max(1, sel - COLS_B)
  elseif a == "down" then sel = math.min(#buttons, sel + COLS_B)
  elseif a == "left" then sel = math.max(1, sel - 1)
  elseif a == "right" then sel = math.min(#buttons, sel + 1)
  elseif a == "ok" then send(sel) end
  return true
end

local w, h = ui.open()
if not w then
  print("irtv: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  name = arg[1]
  if not name then
    local names = remoteNames(fs.list("/home/user") or {})
    if #names == 0 then
      ui.message("No remotes", { "Teach one with the remote app:", "brew install remote" })
      return
    end
    local c = ui.choose("Which remote?", names)
    if not c then return end
    name = names[c]
  end
  local text = fs.read("/home/user/remote-" .. name .. ".rem")
  if not text then
    ui.message("No such remote", { "remote-" .. name .. ".rem is missing" })
    return
  end
  buttons = parseRemote(text)
  if #buttons == 0 then
    ui.message("Empty remote", { name .. " has no buttons yet" })
    return
  end
  tx = txPin(fs.read(CONFIG))
  while true do
    local k = key.poll()
    while k do
      if not handle(k) then return end
      k = key.poll()
    end
    draw()
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("irtv: " .. tostring(problem)) end
