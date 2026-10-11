#!lua
-- metronome: a click at the tempo you set, with a higher tone on the first beat of every bar, and a pendulum on the
-- screen. w and s change the tempo by 5 beats a minute, a and d by 1, space starts and stops, b changes the beats in a
-- bar (2 to 7). ctrl-q quits. Needs the speaker (firmware v0.1.0.6 or newer), the graphics and the ui package.
-- Run it with --selftest to check the timing.

local MIN_BPM, MAX_BPM = 30, 240

local function clampBpm(bpm)
  if bpm < MIN_BPM then return MIN_BPM end
  if bpm > MAX_BPM then return MAX_BPM end
  return bpm
end

-- the time between two beats in milliseconds
local function interval(bpm)
  return 60000 / bpm
end

-- where the pendulum is, from -1 (left) to 1 (right), at a moment `phase` (0 to 1) between the beats of a swing:
-- it goes right on one beat and left on the next
local function pendulum(beatNo, phase)
  local from = (beatNo % 2 == 0) and -1 or 1
  return from + (-2 * from) * phase
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(clampBpm(10) == 30 and clampBpm(300) == 240 and clampBpm(120) == 120, "the tempo stays between 30 and 240")
  check(interval(60) == 1000 and interval(120) == 500, "60 beats a minute is one a second")
  check(pendulum(0, 0) == -1 and pendulum(0, 1) == 1, "on an even beat the pendulum goes from left to right")
  check(pendulum(1, 0) == 1 and pendulum(1, 1) == -1, "on an odd beat it comes back")
  check(pendulum(0, 0.5) == 0, "it is in the middle half way")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("metronome needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not audio or not driver then
  print("metronome needs the audio of firmware v0.1.0.6 or newer")
  return
end
local ui, uiErr = driver.load("ui")
if not ui then
  print("metronome: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local bpm, perBar, running = 100, 4, false
local beatNo, nextBeat, lastBeat = 0, 0, 0
local flashUntil = 0

local function click(accent)
  audio.synth("speaker", "", "square", accent and 1320 or 880, 0.03, 16000)
end

local function draw(now)
  gfx.clear(0x0a0c14)
  ui.center(8, "METRONOME", 0xe8ecf4, 1)
  ui.center(22, tostring(bpm), 0xffe060, 4)
  ui.center(58, "beats a minute", 0x8a94aa, 1)
  local phase = 0
  if running then phase = math.min(1, (now - lastBeat) / interval(bpm)) end
  local p = running and pendulum(beatNo - 1, phase) or 0
  local px = W // 2 + math.floor(p * 70)
  gfx.line(W // 2, 120, px, 74, 0x8a94aa)
  gfx.disc(px, 74, 6, now < flashUntil and 0xffffff or 0x60c8ff)
  for i = 1, perBar do
    local x = W // 2 + (i - (perBar + 1) / 2) * 14
    local on = running and ((beatNo - 1) % perBar) + 1 == i
    gfx.fill(math.floor(x) - 4, 124, 8, 5, on and (i == 1 and 0xff6060 or 0x60e060) or 0x2a3040)
  end
  ui.label(4, 126, "w s tempo", 0x8a94aa)
  ui.label(W - 76, 126, running and "space: stop" or "space: start", 0x8a94aa)
  gfx.flush()
end

local function handle(k, now)
  if k == "ctrl-q" then return false end
  if #k == 1 then k = k:lower() end
  if k == "w" then bpm = clampBpm(bpm + 5)
  elseif k == "s" then bpm = clampBpm(bpm - 5)
  elseif k == "d" then bpm = clampBpm(bpm + 1)
  elseif k == "a" then bpm = clampBpm(bpm - 1)
  elseif k == "b" then perBar = perBar % 6 + 2
  elseif k == " " then
    running = not running
    beatNo = 0
    nextBeat = now
  end
  return true
end

local w, h = ui.open()
if not w then
  print("metronome: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    local now = sys.millis()
    local k = key.poll()
    while k do
      if not handle(k, now) then return end
      k = key.poll()
    end
    if running and now >= nextBeat then
      beatNo = beatNo + 1
      click((beatNo - 1) % perBar == 0)
      lastBeat = now
      nextBeat = nextBeat + interval(bpm)
      flashUntil = now + 80
    end
    draw(now)
    sys.sleep(10)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("metronome: " .. tostring(problem)) end
