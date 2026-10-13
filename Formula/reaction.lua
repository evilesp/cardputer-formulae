#!lua
-- reaction: a reaction-time test. space starts it: the screen turns red, then after a random wait it turns green,
-- and you press space as soon as it is green. A press while it is still red is a false start. The best time and
-- the average of the tries are kept (only the numbers, not the list). r clears the results, ctrl-q quits.
-- Needs the graphics and the ui package. Run it with --selftest to check the rules.

local MIN_WAIT, MAX_WAIT = 1500, 4000 -- the red wait in milliseconds

-- the red wait for a random number r from 0 up to 1 (not reaching 1)
local function waitFor(r)
  return MIN_WAIT + math.floor(r * (MAX_WAIT - MIN_WAIT))
end

-- a word for a reaction time in milliseconds
local function rating(ms)
  if ms < 200 then return "superb" end
  if ms < 250 then return "very fast" end
  if ms < 350 then return "good" end
  return "slow"
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(waitFor(0) == 1500, "the shortest wait is 1500 ms")
  check(waitFor(0.5) == 2750, "the middle wait is 2750 ms")
  check(waitFor(0.999) >= 3900 and waitFor(0.999) <= 3999, "the longest wait is just under 4000 ms")
  check(rating(180) == "superb" and rating(200) == "very fast", "superb under 200 ms")
  check(rating(249) == "very fast" and rating(250) == "good", "very fast under 250 ms")
  check(rating(349) == "good" and rating(350) == "slow", "good under 350 ms")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("reaction needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("reaction: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
-- state: "idle" (ready), "waiting" (red), "go" (green), "early" (false start), "result"
local state = "idle"
local targetAt, goAt = 0, 0
local last = 0 -- the last time in milliseconds
local tries, sum, best = 0, 0, 0 -- the numbers of the results, no list kept

local function average()
  return tries > 0 and sum // tries or 0
end

local function draw()
  local bg = (state == "waiting" or state == "early") and 0x8a1c1c or (state == "go" and 0x1c8a3a) or 0x0a0e18
  gfx.clear(bg)
  ui.label(4, 4, "REACTION", 0xe8ecf4)
  if state == "idle" then
    ui.center(50, "space starts the test", 0xe8ecf4, 1)
    ui.center(64, "wait for green, then press space", 0x8a94aa, 1)
  elseif state == "waiting" then
    ui.center(54, "wait for green...", 0xffd0d0, 2)
  elseif state == "go" then
    ui.center(54, "NOW! press space", 0xffffff, 2)
  elseif state == "early" then
    ui.center(50, "too soon!", 0xffffff, 2)
    ui.center(84, "space to try again", 0xffd0d0, 1)
  elseif state == "result" then
    ui.center(44, last .. " ms  " .. rating(last), 0x60e090, 2)
  end
  if tries > 0 then
    ui.label(4, H - 24, "best " .. best .. " ms   average " .. average() .. " ms   tries " .. tries, 0xe8ecf4)
  end
  ui.label(4, H - 10, "space start/try  r clear  ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("reaction: " .. tostring(h))
  return
end
math.randomseed(sys.millis())
local ok, problem = pcall(function()
  while true do
    if state == "waiting" and sys.millis() >= targetAt then
      state = "go"
      goAt = sys.millis()
    end
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if #k == 1 then k = k:lower() end
      local ready = state == "idle" or state == "result" or state == "early"
      if k == " " or k == "enter" then
        if ready then
          state = "waiting"
          targetAt = sys.millis() + waitFor(math.random())
        elseif state == "waiting" then
          state = "early"
        elseif state == "go" then
          last = sys.millis() - goAt
          tries = tries + 1
          sum = sum + last
          if tries == 1 or last < best then best = last end
          state = "result"
        end
      elseif k == "r" and ready then
        state, last, tries, sum, best = "idle", 0, 0, 0, 0
      end
      k = key.poll()
    end
    sys.sleep(20)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("reaction: " .. tostring(problem)) end
