#!lua
-- wifimap: the Wi-Fi networks around you, by channel. Each column is a channel of the 2.4 GHz band (1 to 13); its height is
-- the strongest network on it, and the number under it is how many networks use it. The least crowded channel is shown at
-- the bottom: a router on that channel has the least competition. r scans again (a scan takes a few seconds), ctrl-q quits.
-- Needs the graphics, the ui package, a WiFi connection (or any scan) and firmware v0.1.0.18(beta) (net.scan with channels).
-- Run it with --selftest to check the summary.

-- the networks by channel: count and the strongest signal (dBm, nil when none)
local function summarize(list)
  local by = {}
  for ch = 1, 13 do by[ch] = { count = 0, best = nil } end
  for _, n in ipairs(list) do
    local c = by[n.channel]
    if c then
      c.count = c.count + 1
      if c.best == nil or n.rssi > c.best then c.best = n.rssi end
    end
  end
  return by
end

-- the channel with the fewest networks (the first one when they are equal)
local function leastCrowded(by)
  local best = 1
  for ch = 2, 13 do
    if by[ch].count < by[best].count then best = ch end
  end
  return best
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local by = summarize({
    { ssid = "a", rssi = -40, channel = 1 },
    { ssid = "b", rssi = -70, channel = 1 },
    { ssid = "c", rssi = -60, channel = 6 },
    { ssid = "d", rssi = -50, channel = 99 },
  })
  check(by[1].count == 2 and by[1].best == -40, "channel 1 has two networks, the strongest at -40 dBm")
  check(by[6].count == 1 and by[6].best == -60 and by[2].count == 0 and by[2].best == nil, "channel 6 and an empty channel")
  check(by[13] and by[13].count == 0, "channel 13 exists")
  check(leastCrowded(by) == 2, "the least crowded channel is the first empty one")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("wifimap needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not net.scan then
  print("wifimap needs firmware v0.1.0.18(beta) or newer: SystemBackUpdate")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("wifimap: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local by, free, message = nil, nil, "scanning..."

local function scan()
  message = "scanning, a few seconds..."
  local list, err = net.scan()
  if not list then
    message = "scan failed: " .. tostring(err)
    return
  end
  by = summarize(list)
  free = leastCrowded(by)
  message = nil
end

local function draw()
  gfx.clear(0x0a0c14)
  ui.label(8, 4, "WIFI CHANNELS", 0xe8ecf4)
  if by then
    for ch = 1, 13 do
      local x = 12 + (ch - 1) * 17
      local c = by[ch]
      local hgt = c.best and math.max(4, (c.best + 100) * 0.7) or 0
      local colour = ch == free and 0x60ff90 or (c.count > 2 and 0xff6060 or 0x40c0ff)
      gfx.fill(x, 100 - hgt, 12, hgt, colour)
      ui.label(x + 1, 104, tostring(ch), 0x8a94aa)
      ui.label(x + 1, 116, tostring(c.count), 0xe8ecf4)
    end
    ui.label(8, 24, "least crowded: channel " .. free, 0x60ff90)
  end
  ui.label(8, H - 10, message or "r scan again   ctrl-q quit", message and 0xffe060 or 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("wifimap: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  scan()
  local next = sys.millis() + 60000
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "r" then scan() next = sys.millis() + 60000 end
      k = key.poll()
    end
    if sys.millis() >= next then
      scan()
      next = sys.millis() + 60000
    end
    sys.sleep(200)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("wifimap: " .. tostring(problem)) end
