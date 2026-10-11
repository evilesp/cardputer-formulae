#!lua
-- pomodoro: work in 25 minute blocks with short breaks (5 minutes), and a long break (15 minutes) after every four blocks.
-- Three short beeps mark the end of a block. space starts and pauses, s skips to the next block, r starts the block again,
-- + and - change the length of a work block (when stopped), ctrl-q quits. Needs the graphics and the ui package and
-- firmware v0.1.0.18(beta) for the beeps. Run it with --selftest to check the timing.

local WORK, SHORT, LONG = 25 * 60, 5 * 60, 15 * 60
local BLOCKS_BEFORE_LONG = 4

-- "MM:SS" for a number of seconds (never negative)
local function clock(seconds)
  if seconds < 0 then seconds = 0 end
  return string.format("%02d:%02d", seconds // 60, seconds % 60)
end

-- the next phase after the current one: work, then a short break, then work ... and a long break after four blocks
local function nextPhase(phase, blocks)
  if phase == "work" then
    if blocks % BLOCKS_BEFORE_LONG == 0 then return "long", blocks end
    return "short", blocks
  end
  return "work", blocks + (phase == "short" and 0 or 0)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(clock(0) == "00:00" and clock(65) == "01:05" and clock(25 * 60) == "25:00", "the clock text")
  check(clock(-3) == "00:00", "no negative time")
  local phase, blocks = "work", 1
  phase, blocks = nextPhase(phase, blocks)
  check(phase == "short", "a work block is followed by a short break")
  phase = nextPhase("short", blocks)
  check(phase == "work", "a short break is followed by work")
  phase, blocks = nextPhase("work", 4)
  check(phase == "long", "after four work blocks comes the long break")
  check(WORK == 1500 and SHORT == 300 and LONG == 900, "the lengths")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("pomodoro needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("pomodoro: " .. tostring(uiErr))
  return
end

local work = WORK
local phase, blocks = "work", 0
local left = work
local running = false
local function lengthOf(p)
  if p == "work" then return work end
  if p == "short" then return SHORT end
  return LONG
end

local function nextBlock()
  local nxt, b = nextPhase(phase, blocks)
  if phase == "work" then blocks = blocks + 1 end
  phase = nxt
  left = lengthOf(phase)
end

local function beeps()
  if audio and audio.beep then
    for i = 0, 2 do pcall(audio.beep, 1000, 120) end
  end
end

local function draw()
  gfx.clear(0x0a0c14)
  local label = phase == "work" and "WORK" or (phase == "short" and "SHORT BREAK" or "LONG BREAK")
  ui.label(8, 6, label, phase == "work" and 0xf0a040 or 0x60ff90, 1)
  ui.label(150, 6, "block " .. blocks, 0x8a94aa)
  ui.center(34, clock(left), 0xe8ecf4, 5)
  local total = lengthOf(phase)
  ui.bar(20, 90, 200, 8, total - left, total, phase == "work" and 0xf0a040 or 0x60ff90)
  ui.label(8, 112, running and "space pause   s skip   r restart" or "space start   + - length of work   ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("pomodoro: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local last = sys.millis()
  while true do
    local now = sys.millis()
    if running then
      left = left - (now - last) / 1000
      if left <= 0 then
        beeps()
        nextBlock()
        running = false
      end
    end
    last = now
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == " " then running = not running
      elseif k == "s" then nextBlock(); running = false
      elseif k == "r" then left = lengthOf(phase)
      elseif (k == "+" or k == "=") and not running and phase == "work" then
        work = math.min(60 * 60, work + 60)
        left = work
      elseif k == "-" and not running and phase == "work" then
        work = math.max(60, work - 60)
        left = work
      end
      k = key.poll()
    end
    draw()
    sys.sleep(100)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("pomodoro: " .. tostring(problem)) end
