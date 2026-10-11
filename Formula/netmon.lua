#!lua
-- netmon: watches how fast a web address answers and draws a chart of the last 100 answers: the time of each in
-- milliseconds, and a red mark for one that failed. It fetches a few bytes every few seconds. ctrl-q quits.
--   netmon [URL [SECONDS]]      e.g. netmon http://example.com 3   (http://example.com every 2 seconds by default)
-- Needs WiFi (wifi connect SSID PASS), the graphics and the ui package. Run it with --selftest to check the statistics.

local KEEP = 100

-- the statistics of a list of answers: each is a time in milliseconds, or false for a failed one
local function stats(samples)
  local n, sum, lo, hi, failed = 0, 0, nil, nil, 0
  for _, v in ipairs(samples) do
    if v then
      n = n + 1
      sum = sum + v
      if not lo or v < lo then lo = v end
      if not hi or v > hi then hi = v end
    else
      failed = failed + 1
    end
  end
  return { count = n, failed = failed, min = lo, max = hi, avg = n > 0 and sum / n or nil }
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local s = stats({ 40, 60, false, 20 })
  check(s.count == 3 and s.failed == 1 and s.min == 20 and s.max == 60 and s.avg == 40, "min, max, average and failures")
  s = stats({})
  check(s.count == 0 and s.avg == nil and s.min == nil, "no answers, no numbers")
  s = stats({ false, false })
  check(s.failed == 2 and s.avg == nil, "only failures")
  if failed == 0 then print("selftest ok") end
  return
end

local url = arg[1] or "http://example.com"
local every = tonumber(arg[2] or "") or 2
if every < 1 or every > 3600 then
  print("usage: netmon [URL [SECONDS]]   (SECONDS 1 to 3600)")
  return
end
if not gfx then
  print("netmon needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not driver then
  print("netmon: this firmware has no driver module")
  return
end
if not net.connected() then
  print("netmon: no WiFi connection (wifi connect SSID PASS)")
  return
end
local ui, uiErr = driver.load("ui")
if not ui then
  print("netmon: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local PLOT_X, PLOT_Y, PLOT_W, PLOT_H = 30, 16, 206, 78
local samples = {}
local lastCode, lastError = nil, nil

local function measure()
  local t0 = sys.millis()
  local code, body = net.fetch(url, 256)
  local ms = sys.millis() - t0
  if code then
    lastCode, lastError = code, nil
    samples[#samples + 1] = ms
  else
    lastCode, lastError = nil, tostring(body)
    samples[#samples + 1] = false
  end
  if #samples > KEEP then table.remove(samples, 1) end
end

local function draw()
  gfx.clear(0x0a0c14)
  ui.label(4, 3, url:sub(1, 36), 0xe8ecf4)
  gfx.rect(PLOT_X - 1, PLOT_Y - 1, PLOT_W + 2, PLOT_H + 2, 0x4a5470)
  local s = stats(samples)
  local top = math.max(100, s.max or 100)
  ui.label(2, PLOT_Y - 2, tostring(math.floor(top)), 0x8a94aa)
  ui.label(2, PLOT_Y + PLOT_H - 8, "0", 0x8a94aa)
  local step = PLOT_W / KEEP
  local prevX, prevY
  for i, v in ipairs(samples) do
    local x = PLOT_X + math.floor((i - 1) * step)
    if v then
      local y = PLOT_Y + PLOT_H - 1 - math.floor(math.min(v, top) / top * (PLOT_H - 1))
      if prevX then gfx.line(prevX, prevY, x, y, 0x60c8ff) else gfx.pixel(x, y, 0x60c8ff) end
      prevX, prevY = x, y
    else
      gfx.vline(x, PLOT_Y, PLOT_Y + PLOT_H - 1, 0xc03030)
      prevX, prevY = nil, nil
    end
  end
  local last = samples[#samples]
  ui.label(4, PLOT_Y + PLOT_H + 6, last and string.format("last %d ms", last) or (lastError or "waiting"), last and 0x60e060 or 0xff6060)
  if s.avg then
    ui.label(4, PLOT_Y + PLOT_H + 16, string.format("min %d  avg %d  max %d  failed %d", s.min, s.avg, s.max, s.failed), 0x8a94aa)
  end
  ui.label(4, H - 10, lastCode and ("HTTP " .. lastCode .. "   ctrl-q quit") or "ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("netmon: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local nextAt = 0
  while true do
    local now = sys.millis()
    if now >= nextAt then
      measure()
      nextAt = sys.millis() + every * 1000
    end
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      k = key.poll()
    end
    draw()
    sys.sleep(100)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("netmon: " .. tostring(problem)) end
