#!lua
-- cava: an animation of bars that dance like the audio visualizer of the same name. It is only a picture: nothing
-- is read from the microphone or the speaker. The bars on the left are higher on average, as in a spectrum, and
-- each bar falls back slowly after a peak. q quits.

local COLS, ROWS = term.size()
local BARS = 20                   -- one bar every second column
local BAR_TOP = 1                 -- the title is on row 0
local BAR_BOTTOM = ROWS - 2       -- the key hint is on the last row
local HEIGHT = BAR_BOTTOM - BAR_TOP + 1
local FALL = 0.04                 -- how far a bar drops per frame after a peak

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- each bar has its own speed and starting point in two waves, so the bars never move in step
local SPEED, PHASE = {}, {}
for i = 1, BARS do
  SPEED[i] = 0.05 + math.random() * 0.12
  PHASE[i] = math.random() * 6.28
end

-- the height of bar i (0..1) at time t
local function target(i, t)
  local tilt = 1 - (i - 1) / BARS * 0.5
  local wave = 0.5 + 0.3 * math.sin(t * SPEED[i] + PHASE[i]) + 0.2 * math.sin(t * SPEED[i] * 2.7 + PHASE[i] * 1.3)
  return clamp(wave * tilt, 0, 1)
end

local function draw(shown)
  term.clear()
  term.text(0, 0, "cava", "cyan")
  local cells = {}
  for y = BAR_TOP, BAR_BOTTOM do
    cells[y] = {}
    for x = 1, COLS do cells[y][x] = " " end
  end
  for i = 1, BARS do
    local h = math.floor(shown[i] * HEIGHT + 0.5)
    for y = BAR_BOTTOM - h + 1, BAR_BOTTOM do
      if y >= BAR_TOP then cells[y][2 * i - 1] = "#" end
    end
  end
  for y = BAR_TOP, BAR_BOTTOM do
    term.text(0, y, table.concat(cells[y]), "white")
  end
  term.text(0, ROWS - 1, "q quit", "dim")
  term.flush()
end

local shown = {}
for i = 1, BARS do shown[i] = 0 end
local t, quit = 0, false

term.fullscreen(true)
while not quit do
  local k = key.poll()
  while k do
    if k == "q" then quit = true end
    k = key.poll()
  end
  if quit then break end

  t = t + 1
  for i = 1, BARS do
    local goal = target(i, t)
    if goal > shown[i] then
      shown[i] = goal
    else
      shown[i] = math.max(goal, shown[i] - FALL)
    end
  end
  draw(shown)
  sys.sleep(40)
end
term.fullscreen(false)
