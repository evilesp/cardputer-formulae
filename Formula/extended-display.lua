#!lua
-- extended-display: a second screen on the free pins of the Cardputer (an SPI panel). It shows a copy of the terminal and of
-- the graphics of apps. The controller of the panel comes from a driver package (xd-ili9341, xd-ili9488, xd-st7789 ...) and the
-- wiring from the config file /etc/extended-display.json (JSON: driver, width, height, rotation, freq, brightness, pins).
--
--   apt install extended-display ili9341   install the command and the driver (apt install extended-display-driver also works)
--   extended-display set [DRIVER]          write the config for a driver (it is downloaded when missing) and open it in nano
--   extended-display set KEY VALUE         change one value: rotation 1, brightness 40, pins.cs 3, freq 20000000, invert true
--   extended-display start [DRIVER]        start the display (with DRIVER: use that driver from now on)
--   extended-display stop | restart        stop the display / start it again from the config
--   extended-display bright PERCENT        backlight, 0 to 100
--   extended-display status | test | list  what runs, colour bars to check the wiring, the drivers
--   extended-display enable | disable      start it at every boot (a line in ~/.profile)
--   extended-display --config FILE ...     use another config file (--profile FILE: another boot script)
-- Needs firmware v0.1.0.25 or newer (the xdisp module). The panel uses SPI3, so the spi module of apps is busy while it runs.

if not xdisp then
  print("extended-display needs the xdisp module of firmware v0.1.0.25: SystemUpdate")
  return 1
end

local CONFIG = "/etc/extended-display.json"
local PROFILE = "/home/user/.profile"
local START_LINE = "extended-display start"
local KNOWN = { "ili9341", "ili9342", "ili9488", "st7789", "st7789-240", "st7789-135", "st7735", "st7796" }

-- the keys of the config file in the order they are written; the value is how it is read from text
local KEYS = {
  { "driver", "string" }, { "width", "number" }, { "height", "number" }, { "memory_width", "number" },
  { "memory_height", "number" }, { "offset_x", "number" }, { "offset_y", "number" }, { "depth", "number" },
  { "rotation", "number" }, { "scale", "number" }, { "freq", "number" }, { "brightness", "number" },
  { "invert", "boolean" }, { "bgr", "boolean" },
}
local PINS = { "sclk", "mosi", "miso", "cs", "dc", "rst", "bl" }

local args = { table.unpack(arg or {}) }
while (args[1] == "--config" or args[1] == "--profile") and args[2] do
  if args[1] == "--config" then CONFIG = args[2] else PROFILE = args[2] end
  table.remove(args, 1)
  table.remove(args, 1)
end

local function say(text) print(text) end
local function problem(text)
  print("extended-display: " .. text)
  return 1
end

-- ---- the config file ----

local function readConfig()
  local text = fs.read(CONFIG)
  if not text then return nil, CONFIG .. " does not exist yet (extended-display set DRIVER makes it)" end
  local json, err = driver.load("json")
  if not json then return nil, "the json driver is missing: " .. tostring(err) end
  local cfg, why = json.decode(text)
  if type(cfg) ~= "table" then return nil, CONFIG .. " is not valid JSON: " .. tostring(why) end
  return cfg
end

local function encode(value)
  local kind = type(value)
  if kind == "string" then return '"' .. value:gsub('[\\"]', "\\%0") .. '"' end
  if kind == "number" then
    if value == math.floor(value) then return string.format("%d", value) end
    return tostring(value)
  end
  return tostring(value)
end

-- the start-up list in a JSON file is a list of byte lists, or {"cmd": [bytes], "delay": ms} when the command needs a wait
local function normalizeInit(init)
  local out = {}
  for i, c in ipairs(init) do
    if type(c) ~= "table" then return nil, "init entry " .. i .. " must be a list of bytes" end
    if c.cmd then
      local e = { table.unpack(c.cmd) }
      e.delay = c.delay
      out[i] = e
    else
      out[i] = c
    end
  end
  return out
end

local function encodeInit(init)
  local rows = {}
  for _, c in ipairs(init) do
    local bytes = {}
    for _, b in ipairs(c) do bytes[#bytes + 1] = string.format("%d", b) end
    local list = "[" .. table.concat(bytes, ", ") .. "]"
    if c.delay then list = '{"cmd": ' .. list .. ', "delay": ' .. string.format("%d", c.delay) .. "}" end
    rows[#rows + 1] = "    " .. list
  end
  return "[\n" .. table.concat(rows, ",\n") .. "\n  ]"
end

local function writeConfig(cfg)
  local lines = {}
  for _, k in ipairs(KEYS) do
    local v = cfg[k[1]]
    if v ~= nil then lines[#lines + 1] = '  "' .. k[1] .. '": ' .. encode(v) end
  end
  local pins = {}
  for _, name in ipairs(PINS) do
    pins[#pins + 1] = '"' .. name .. '": ' .. encode((cfg.pins and cfg.pins[name]) or -1)
  end
  lines[#lines + 1] = '  "pins": { ' .. table.concat(pins, ", ") .. " }"
  if type(cfg.init) == "table" then lines[#lines + 1] = '  "init": ' .. encodeInit(normalizeInit(cfg.init) or {}) end
  local text = "{\n" .. table.concat(lines, ",\n") .. "\n}\n"
  local ok, err = fs.write(CONFIG, text)
  if not ok then return false, tostring(err) end
  return true
end

-- ---- drivers ----

local function packageOf(name)
  name = name:lower()
  if name:sub(1, 3) == "xd-" then return name end
  return "xd-" .. name
end

local function shortName(pkg)
  return (pkg:gsub("^xd%-", ""))
end

-- loads the driver data; a driver that is not installed is downloaded (it needs WiFi and the lists of "apt update")
local function loadDriver(name)
  local pkg = packageOf(name)
  local drv, err = driver.load(pkg)
  if drv then return drv end
  if brew and brew.install then
    say("Get: driver " .. pkg)
    local ok, out = brew.install(pkg)
    if not ok and tostring(out):find("brew update", 1, true) and brew.update then
      say("Reading package lists...")
      brew.update()
      ok, out = brew.install(pkg)
    end
    if ok then
      drv, err = driver.load(pkg)
      if drv then return drv end
    else
      err = tostring(out):gsub("\n+$", "")
    end
  end
  return nil, "driver " .. shortName(pkg) .. " is not available: " .. tostring(err)
end

local function defaultPins()
  local free = gpio.pins()
  local pins = {}
  for i, name in ipairs({ "bl", "rst", "cs", "dc", "sclk", "mosi" }) do pins[name] = free[i] or -1 end
  pins.miso = -1
  return pins
end

-- a config with the values of a driver and the default pins; keepFrom is an older config whose pins and settings stay
local function configFor(drv, keepFrom)
  local cfg = {
    driver = shortName(packageOf(drv.name)), width = drv.width, height = drv.height, memory_width = drv.memory_width,
    memory_height = drv.memory_height, offset_x = drv.offset_x, offset_y = drv.offset_y, depth = drv.depth or 16,
    rotation = 0, scale = 0, freq = drv.freq or 20000000, brightness = 100, invert = drv.invert or false,
    bgr = drv.bgr or false, pins = defaultPins(),
  }
  if keepFrom then
    cfg.pins = keepFrom.pins or cfg.pins
    cfg.rotation = keepFrom.rotation or 0
    cfg.brightness = keepFrom.brightness or 100
    cfg.scale = keepFrom.scale or 0
    if keepFrom.freq then cfg.freq = math.min(keepFrom.freq, cfg.freq) end
  end
  return cfg
end

-- the table for xdisp.start: the config over the driver (the config may carry its own init list for an unknown controller)
local function startTable(cfg, drv)
  local t = {
    driver = cfg.driver, width = cfg.width or drv.width, height = cfg.height or drv.height,
    memory_width = cfg.memory_width or drv.memory_width, memory_height = cfg.memory_height or drv.memory_height,
    offset_x = cfg.offset_x or drv.offset_x, offset_y = cfg.offset_y or drv.offset_y, depth = cfg.depth or drv.depth,
    rotation = cfg.rotation or 0, scale = cfg.scale or 0, freq = cfg.freq or drv.freq, bright = cfg.brightness or 100,
    invert = cfg.invert, bgr = cfg.bgr, pins = cfg.pins, init = drv.init,
  }
  if t.invert == nil then t.invert = drv.invert end
  if t.bgr == nil then t.bgr = drv.bgr end
  return t
end

-- ---- commands ----

local function describe(info)
  return string.format("%s %dx%d (panel %dx%d), rotation %d, scale %.2g, %.1f MHz, brightness %d%%", info.driver,
    info.width, info.height, info.panel_width, info.panel_height, info.rotation, info.scale, info.freq / 1e6, info.bright)
end

local function cmdStart(name)
  local cfg, err = readConfig()
  if name then
    local drv, why = loadDriver(name)
    if not drv then return problem(why) end
    cfg = configFor(drv, cfg)
    local ok, wr = writeConfig(cfg)
    if not ok then return problem("cannot write " .. CONFIG .. ": " .. wr) end
  elseif not cfg then
    return problem(err)
  end
  if not cfg.driver or cfg.driver == "" then return problem("no driver in " .. CONFIG .. " (extended-display set DRIVER)") end
  local drv
  if type(cfg.init) == "table" then
    local list, why = normalizeInit(cfg.init)  -- the config carries its own start-up list
    if not list then return problem(why) end
    drv = { init = list }
  else
    local why
    drv, why = loadDriver(cfg.driver)
    if not drv then return problem(why) end
  end
  local ok, w, h = xdisp.start(startTable(cfg, drv))
  if not ok then return problem(tostring(w)) end
  local info = xdisp.info()
  say("extended-display: started, " .. describe(info))
  return 0
end

local function cmdStop()
  if xdisp.stop() then say("extended-display: stopped") else say("extended-display: it was not running") end
  return 0
end

local function cmdRestart()
  if xdisp.info() then xdisp.stop() end
  return cmdStart(nil)
end

local function cmdBright(value)
  local n = tonumber(value or "")
  if not n or n < 0 or n > 100 then return problem("usage: extended-display bright PERCENT (0 to 100)") end
  n = math.floor(n + 0.5)
  local cfg = readConfig()
  if cfg then
    cfg.brightness = n
    writeConfig(cfg)
  end
  if xdisp.info() then
    local ok, err = xdisp.bright(n)
    if not ok then return problem(tostring(err)) end
    say("extended-display: brightness " .. n .. "%")
  else
    say("extended-display: brightness " .. n .. "% saved, the display is not running")
  end
  return 0
end

local function cmdStatus()
  local info = xdisp.info()
  if info then
    say("running: " .. describe(info))
    local p = info.pins
    say(string.format("pins: sclk %d, mosi %d, miso %d, cs %d, dc %d, rst %d, bl %d", p.sclk, p.mosi, p.miso, p.cs, p.dc, p.rst, p.bl))
    say("pictures sent: " .. info.frames)
  else
    say("not running")
  end
  say("config: " .. CONFIG .. (fs.exists(CONFIG) and "" or " (missing)"))
  return 0
end

local function cmdList()
  say("drivers (apt install extended-display NAME):")
  for _, name in ipairs(KNOWN) do
    local mark = fs.exists("/usr/local/lib/drivers/xd-" .. name .. ".lua") and " [installed]" or ""
    say("  " .. name .. mark)
  end
  return 0
end

local function cmdTest()
  local ok, err = xdisp.test()
  if not ok then return problem(tostring(err)) end
  say("extended-display: colour bars drawn; the white square is the top left corner")
  return 0
end

-- sets one value of the config: set rotation 1, set pins.cs 3, set invert true
local function setValue(key, text)
  local cfg, err = readConfig()
  if not cfg then return problem(err) end
  local pin = key:match("^pins%.(%w+)$")
  if pin then
    local known = false
    for _, name in ipairs(PINS) do if name == pin then known = true end end
    local n = tonumber(text)
    if not known or not n then return problem("pins.NAME is one of " .. table.concat(PINS, ", ") .. ", the value a GPIO number or -1") end
    cfg.pins = cfg.pins or {}
    cfg.pins[pin] = math.floor(n)
  else
    local kind
    for _, k in ipairs(KEYS) do if k[1] == key then kind = k[2] end end
    if key == "brightness" then kind = "number" end
    if not kind then return problem("unknown key " .. key .. " (see the file: extended-display set)") end
    if kind == "number" then
      local n = tonumber(text)
      if not n then return problem(key .. " is a number") end
      cfg[key] = n
    elseif kind == "boolean" then
      if text ~= "true" and text ~= "false" then return problem(key .. " is true or false") end
      cfg[key] = (text == "true")
    else
      cfg[key] = text
    end
  end
  local ok, wr = writeConfig(cfg)
  if not ok then return problem("cannot write " .. CONFIG .. ": " .. wr) end
  say(CONFIG .. ": " .. key .. " = " .. text .. (xdisp.info() and "  (extended-display restart to use it)" or ""))
  return 0
end

-- opens the config file in nano
local function edit()
  if not fs.exists("/usr/local/bin/nano") then
    say("Get: nano")
    local ok, out = brew.install("nano")
    if not ok and tostring(out):find("brew update", 1, true) and brew.update then
      brew.update()
      ok = brew.install("nano")
    end
    if not ok then
      say("extended-display: nano is not installed (apt install nano); the file is " .. CONFIG)
      return 1
    end
  end
  local code = fs.read("/usr/local/bin/nano")
  if not code then return problem("cannot read nano") end
  local chunk, err = load((code:gsub("^#![^\n]*", "")), "=nano")
  if not chunk then return problem("nano: " .. tostring(err)) end
  local saved = arg
  arg = { CONFIG }
  local ok, why = pcall(chunk, CONFIG)
  arg = saved
  if not ok and not tostring(why):find("interrupted", 1, true) then return problem("nano: " .. tostring(why)) end
  local cfg, bad = readConfig()
  if not cfg then
    say("extended-display: " .. tostring(bad))
    return 1
  end
  say("saved " .. CONFIG .. (xdisp.info() and ": extended-display restart" or ": extended-display start"))
  return 0
end

local function cmdSet(a, b)
  if a and b then return setValue(a, b) end
  if a then  -- a driver name
    local drv, why = loadDriver(a)
    if not drv then return problem(why) end
    local ok, wr = writeConfig(configFor(drv, readConfig()))
    if not ok then return problem("cannot write " .. CONFIG .. ": " .. wr) end
    say("driver " .. shortName(packageOf(a)) .. ": " .. (drv.info or ""))
  elseif not fs.exists(CONFIG) then
    return problem("which driver? extended-display set DRIVER   (extended-display list)")
  end
  return edit()
end

local function cmdBoot(on)
  local text = fs.read(PROFILE) or ""
  local lines, found = {}, false
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line == START_LINE then found = true else lines[#lines + 1] = line end
  end
  while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
  if on then lines[#lines + 1] = START_LINE end
  local ok, err = fs.write(PROFILE, table.concat(lines, "\n") .. "\n")
  if not ok then return problem("cannot write " .. PROFILE .. ": " .. tostring(err)) end
  if on then say("the display starts at every boot (" .. PROFILE .. ")")
  else say(found and "the display no longer starts at boot" or "it was not set to start at boot") end
  return 0
end

local USAGE = [[
usage: extended-display COMMAND
  set [DRIVER]       write the config for a driver and open it in nano
  set KEY VALUE      change one value (rotation 1, brightness 40, pins.cs 3)
  start [DRIVER]     start the display (DRIVER: switch to that driver)
  stop | restart     stop it / start it again from the config
  bright PERCENT     backlight 0 to 100
  status | test      what runs / colour bars
  list               the drivers
  enable | disable   start it at every boot
install: apt install extended-display ili9341]]

local cmd = args[1]
if cmd == "set" then return cmdSet(args[2], args[3]) end
if cmd == "start" then return cmdStart(args[2]) end
if cmd == "stop" then return cmdStop() end
if cmd == "restart" then return cmdRestart() end
if cmd == "bright" or cmd == "brightness" then return cmdBright(args[2]) end
if cmd == "status" or cmd == "info" then return cmdStatus() end
if cmd == "test" then return cmdTest() end
if cmd == "list" then return cmdList() end
if cmd == "enable" then return cmdBoot(true) end
if cmd == "disable" then return cmdBoot(false) end
print(USAGE)
return cmd and 1 or 0
