#!lua
-- timer: a countdown with big digits. timer 25m, timer 90 (seconds), timer 1h30m, timer 1m30s. Space pauses and goes
-- on, r starts again, q quits. At zero it beeps three times and waits for r.
-- Pomodoro: timer 25m, then timer 5m for the break.

local USAGE = "usage: timer DURATION   e.g. timer 25m, timer 90, timer 1h30m, timer 1m30s"

local FONT = {
  ["0"] = { "###", "# #", "# #", "# #", "###" },
  ["1"] = { " # ", "## ", " # ", " # ", "###" },
  ["2"] = { "###", "  #", "###", "#  ", "###" },
  ["3"] = { "###", "  #", "###", "  #", "###" },
  ["4"] = { "# #", "# #", "###", "  #", "  #" },
  ["5"] = { "###", "#  ", "###", "  #", "###" },
  ["6"] = { "###", "#  ", "###", "# #", "###" },
  ["7"] = { "###", "  #", "  #", "  #", "  #" },
  ["8"] = { "###", "# #", "###", "# #", "###" },
  ["9"] = { "###", "# #", "###", "  #", "###" },
  [":"] = { "   ", " # ", "   ", " # ", "   " },
}

-- "90" is seconds; "1h30m", "25m", "1m30s" are units in any order. Returns the seconds, or nil.
local function parseDuration(text)
  if text:match("^%d+$") then return tonumber(text) end
  local total, pos = 0, 1
  local units = { h = 3600, m = 60, s = 1 }
  while pos <= #text do
    local num, unit, nextPos = text:match("^(%d+)([hms])()", pos)
    if not num then return nil end
    total = total + tonumber(num) * units[unit]
    pos = nextPos
  end
  if pos == 1 then return nil end
  return total
end

local function clock(seconds)
  local h, m, s = seconds // 3600, seconds % 3600 // 60, seconds % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
  return string.format("%02d:%02d", m, s)
end

local total = parseDuration(arg[1] or "")
if not total then
  print(USAGE)
  return
end
local ROWS = select(2, term.size())

local left = total * 1000     -- milliseconds left
local running = true
local last = sys.millis()
local beeped = false

local function beep()
  for _ = 1, 3 do
    if audio then audio.synth("speaker", "", "square", 880, 0.3, 16000) end
    sys.sleep(150)
  end
end

local function draw()
  term.clear()
  term.text(0, 0, "timer", "green")
  local shown = clock(math.ceil(left / 1000))
  local x = 2
  for c in shown:gmatch(".") do
    local glyph = FONT[c]
    for row = 1, 5 do term.text(x, 1 + row, glyph[row], "text") end
    x = x + 4
  end
  term.text(0, 8, "left " .. shown, "text")
  if left <= 0 then
    term.text(0, 10, "time's up!", "red")
  elseif running then
    term.text(0, 10, "running", "green")
  else
    term.text(0, 10, "paused", "warn")
  end
  term.text(0, ROWS - 2, "space pause   r restart", "dim")
  term.text(0, ROWS - 1, "q quit", "dim")
  term.flush()
end

local function restart()
  left = total * 1000
  running = true
  beeped = false
  last = sys.millis()
end

-- returns false when the player quits
local function handle(k)
  if k == "q" then return false end
  if k == "r" then
    restart()
  elseif k == " " and left > 0 then
    running = not running
    last = sys.millis()
  end
  return true
end

term.fullscreen(true)
local quit = false
while not quit do
  local now = sys.millis()
  if running and left > 0 then
    left = left - (now - last)
    if left <= 0 then
      left = 0
      running = false
    end
  end
  last = now
  if left <= 0 and not beeped then
    beeped = true
    draw()
    beep()
  end
  draw()
  local k = key.poll()
  while k do
    if not handle(k) then
      quit = true
      break
    end
    k = key.poll()
  end
  sys.sleep(100)
end
term.fullscreen(false)
