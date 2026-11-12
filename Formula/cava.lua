#!lua
-- cava: bars that dance like the audio visualizer of the same name: two columns wide, one apart, no labels, built of the
-- block characters (heights in eighths of a cell), the colour a gradient from green at the bottom through yellow to red. It is only a picture: nothing is read from the
-- microphone or the speaker. The bars on the left are higher on average, as in a spectrum, and each bar falls back with
-- gravity after a peak. q quits (so does Ctrl+C).
local USAGE = "\nUsage : cava [options]\nVisualize audio input in terminal. \n\nOptions:\n\t-p          path to config file\n\t-v          print version\n\nFeatures : ncurses\n\n"
for _, a in ipairs(arg) do
  if a == "-v" then print("cava 0.10.4") return end
  if a == "-h" or a == "--help" then print(USAGE) return end
end

local COLS, ROWS = term.size()
local BARS = (COLS + 1) // 3      -- a bar is 2 columns wide with 1 column between bars
local BAR_TOP = 0
local BAR_BOTTOM = ROWS - 1
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

-- the colour of a row: a gradient from green at the bottom through yellow to red at the top (true colour, nearest palette entry)
local GRAD = {}
for y = BAR_TOP, BAR_BOTTOM do
  local f = (BAR_BOTTOM - y) / math.max(1, HEIGHT - 1)  -- 0 at the bottom, 1 at the top
  local r, g
  if f < 0.5 then r, g = f * 2 * 255, 255 else r, g = 255, (1 - (f - 0.5) * 2) * 255 end
  GRAD[y] = term.rgb(math.floor(r), math.floor(g), 40)
end
local PART = { "\u{2581}", "\u{2582}", "\u{2583}", "\u{2584}", "\u{2585}", "\u{2586}", "\u{2587}" }  -- 1/8 .. 7/8 of a cell

local function draw(shown)
  term.clear()
  for i = 1, BARS do
    -- the height in eighths of a cell, as the real cava does with its block characters
    local eighths = math.floor(shown[i] * HEIGHT * 8 + 0.5)
    local full, part = eighths // 8, eighths % 8
    for k = 0, full - 1 do
      local y = BAR_BOTTOM - k
      term.put(3 * i - 3, y, "\u{2588}", GRAD[y])
      term.put(3 * i - 2, y, "\u{2588}", GRAD[y])
    end
    if part > 0 and full < HEIGHT then
      local y = BAR_BOTTOM - full
      term.put(3 * i - 3, y, PART[part], GRAD[y])
      term.put(3 * i - 2, y, PART[part], GRAD[y])
    end
  end
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
