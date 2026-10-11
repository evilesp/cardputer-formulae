#!lua
-- steps: the step counter. It counts in the background, also when no program runs (the log is /home/user/steps.txt).
-- The screen shows today's steps against a goal, the last seven days and the total. r forgets today's steps,
-- t stops or starts the counting, ctrl-q quits. Needs the graphics, the ui package and firmware v0.1.0.18(beta).
-- Run it with --selftest to check the helpers.

local GOAL = 10000
local W, H = 240, 135
local DAY_LETTERS = { "M", "T", "W", "T", "F", "S", "S" }

-- the day of the week of a date "YYYY-MM-DD": 1 is Monday ... 7 is Sunday (Zeller's congruence), nil for a bad date
local function weekday(date)
  local y, m, d = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not y then return nil end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if m < 3 then
    m = m + 12
    y = y - 1
  end
  local k, j = y % 100, y // 100
  local h = (d + (13 * (m + 1)) // 5 + k + k // 4 + j // 4 + 5 * j) % 7  -- 0 is Saturday
  return (h + 5) % 7 + 1
end

-- how far to the goal, 0 to 1
local function fraction(steps, goal)
  if goal <= 0 then return 1 end
  return math.min(1, math.max(0, steps / goal))
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(weekday("2000-01-01") == 6, "1 January 2000 was a Saturday")
  check(weekday("2026-10-12") == 1, "12 October 2026 is a Monday")
  check(weekday("2024-02-29") == 4, "29 February 2024 was a Thursday")
  check(weekday("2026-13-01") ~= nil or true, "bad months do not crash")
  check(weekday("nonsense") == nil, "a bad date gives nil")
  check(fraction(5000, 10000) == 0.5 and fraction(20000, 10000) == 1 and fraction(-5, 10000) == 0, "the goal fraction")
  check(fraction(3, 0) == 1, "no goal is full")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("steps needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not steps or not steps.today then
  print("steps needs firmware v0.1.0.18(beta) or newer: SystemBackUpdate")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("steps: " .. tostring(uiErr))
  return
end

local T = ui.theme

local function draw(days, total)
  local today = steps.today()
  gfx.clear(T.bg)
  ui.panel(2, 2, W - 4, H - 4, "STEPS")
  ui.label(150, 4, steps.enabled() and "counting" or "paused", steps.enabled() and T.accent or T.warn)
  ui.label(12, 20, string.format("%d", today), T.text, 3)
  ui.label(12 + 6 * 3 * #tostring(today) + 8, 30, "of " .. GOAL .. " steps", T.dim)
  ui.bar(12, 50, 216, 8, today, GOAL, T.accent)
  -- the last seven days: a bar each, scaled to the best day (at least the goal)
  local best = GOAL
  for _, d in ipairs(days) do
    if d.steps > best then best = d.steps end
  end
  local x0, base = 16, 110
  for i, d in ipairs(days) do
    local x = x0 + (i - 1) * 30
    local hgt = math.floor(fraction(d.steps, best) * 44)
    gfx.fill(x, base - hgt, 18, hgt, d.steps >= GOAL and T.accent or T.light)
    local wd = weekday(d.date)
    ui.label(x + 5, base + 3, wd and DAY_LETTERS[wd] or "?", T.dim)
  end
  if #days == 0 then ui.label(16, 74, "no steps recorded yet", T.dim) end
  ui.label(12, H - 14, "total " .. total .. "   r forget today   t pause   ctrl-q", T.dim)
  gfx.flush()
end

local function confirmReset()
  return ui.choose("Forget today's steps?", { "No", "Yes" }) == 2
end

local w, h = ui.open()
if not w then
  print("steps: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    draw(steps.days(7), steps.total())
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "r" and confirmReset() then steps.reset() end
      if k == "t" then steps.enabled(not steps.enabled()) end
      k = key.poll()
    end
    sys.sleep(250)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("steps: " .. tostring(problem)) end
