#!lua
-- stopwatch: a stopwatch with laps. space starts and stops it, l takes a lap (the time of the lap and the time since the start),
-- r resets it while it is stopped, ctrl-q quits. It keeps counting while the screen shows other things, and shows the best and
-- the worst lap. Needs the graphics and the ui package. Run it with --selftest to check the time formats.

-- milliseconds as "MM:SS.cc" (minutes go over 99 as 100:00.00 and on)
local function clock(ms)
  local cs = (ms // 10) % 100
  local s = (ms // 1000) % 60
  local m = ms // 60000
  return string.format("%02d:%02d.%02d", m, s, cs)
end

-- the laps as { lapTime, total } for the list of totals taken at each press of "lap"
local function laps(totals)
  local out, prev = {}, 0
  for i, t in ipairs(totals) do
    out[i] = { t - prev, t }
    prev = t
  end
  return out
end

-- the index of the best (shortest) and the worst (longest) lap, or nil with fewer than two laps
local function extremes(list)
  if #list < 2 then return nil end
  local best, worst = 1, 1
  for i, l in ipairs(list) do
    if l[1] < list[best][1] then best = i end
    if l[1] > list[worst][1] then worst = i end
  end
  return best, worst
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(clock(0) == "00:00.00" and clock(1234) == "00:01.23" and clock(61005) == "01:01.00" and clock(3599990) == "59:59.99", "clock")
  check(clock(6000000) == "100:00.00", "more than 99 minutes")
  local l = laps({ 1000, 2500, 3000 })
  check(#l == 3 and l[1][1] == 1000 and l[2][1] == 1500 and l[3][1] == 500 and l[3][2] == 3000, "laps")
  local best, worst = extremes(l)
  check(best == 3 and worst == 2, "best and worst lap")
  check(extremes({ { 1, 1 } }) == nil, "no best with one lap")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("stopwatch needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("stopwatch: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local running, startedAt, elapsed, totals = false, 0, 0, {}

local function now()
  return running and (elapsed + sys.millis() - startedAt) or elapsed
end

local function draw()
  gfx.clear(0x0a0e18)
  local t = now()
  ui.center(8, clock(t), running and 0x60e090 or 0xe8ecf4, 4)
  ui.label(4, 46, running and "running" or (t > 0 and "stopped" or "ready"), running and 0x60e090 or 0x8a94aa)
  local list = laps(totals)
  local best, worst = extremes(list)
  ui.label(4, 58, "lap", 0x8a94aa); ui.label(40, 58, "lap time", 0x8a94aa); ui.label(130, 58, "total", 0x8a94aa)
  -- the newest laps, newest on top
  local row = 0
  for i = #list, math.max(1, #list - 4), -1 do
    local colour = (i == best and 0x60e090) or (i == worst and 0xff7070) or 0xe8ecf4
    ui.label(4, 70 + row * 10, tostring(i), colour)
    ui.label(40, 70 + row * 10, clock(list[i][1]), colour)
    ui.label(130, 70 + row * 10, clock(list[i][2]), colour)
    row = row + 1
  end
  ui.label(4, H - 10, "space start/stop  l lap  r reset  ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("stopwatch: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if #k == 1 then k = k:lower() end
      if k == " " or k == "enter" then
        if running then
          elapsed = elapsed + sys.millis() - startedAt
          running = false
        else
          startedAt = sys.millis()
          running = true
        end
      elseif k == "l" and (running or elapsed > 0) then
        totals[#totals + 1] = now()
      elseif k == "r" and not running then
        elapsed, totals = 0, {}
      end
      k = key.poll()
    end
    sys.sleep(20)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("stopwatch: " .. tostring(problem)) end
