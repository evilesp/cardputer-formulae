#!lua
-- cava: bars that dance to the sound, like the audio visualizer of the same name. Each bar is the loudness of
-- one 50 ms moment, the newest on the right. The sound comes from the microphone through audio.record (firmware
-- v0.1.0.6(beta) or newer). Without it, or with "cava demo", the bars move on their own. q quits.
-- The bars show loudness over time, not the frequencies: the microphone is read as one level.

local COLS, ROWS = term.size()
local BARS = 20                   -- one bar every second column
local BAR_TOP = 1                 -- the title is on row 0
local BAR_BOTTOM = ROWS - 2       -- the source is on the last row
local HEIGHT = BAR_BOTTOM - BAR_TOP + 1
local MOMENT = 0.05               -- seconds of microphone per bar

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- 0..1 from the root mean square of the samples: -60 dB is silent, -10 dB is full
local function loudness(rms)
  if rms <= 0 then return 0 end
  return clamp((20 * math.log(rms, 10) + 60) / 50, 0, 1)
end

local function draw(levels, source)
  term.clear()
  term.text(0, 0, "cava", "cyan")
  local cells = {}
  for y = BAR_TOP, BAR_BOTTOM do
    cells[y] = {}
    for x = 1, COLS do cells[y][x] = " " end
  end
  for i = 1, BARS do
    local h = math.floor(levels[i] * HEIGHT + 0.5)
    for y = BAR_BOTTOM - h + 1, BAR_BOTTOM do
      if y >= BAR_TOP then cells[y][2 * i - 1] = "#" end
    end
  end
  for y = BAR_TOP, BAR_BOTTOM do
    term.text(0, y, table.concat(cells[y]), "white")
  end
  term.text(0, ROWS - 1, source .. "   q quit", "dim")
  term.flush()
end

local demo = arg[1] == "demo" or audio == nil
local source = demo and "demo" or "microphone"
local levels = {}
for i = 1, BARS do levels[i] = 0 end
local walk = 0.5                  -- the level of the demo, moving at random
local quit = false

term.fullscreen(true)
while not quit do
  local k = key.poll()
  while k do
    if k == "q" then quit = true end
    k = key.poll()
  end
  if quit then break end

  local level
  if not demo then
    local stats = audio.record("null", "", MOMENT, 16000)
    if stats then
      level = loudness(stats.rms)
    else
      demo, source = true, "demo"   -- no microphone: the bars move on their own from now on
    end
  end
  if demo then
    walk = clamp(walk + (math.random() - 0.5) * 0.6, 0.05, 1)
    level = walk
  end

  table.remove(levels, 1)
  levels[BARS] = level
  draw(levels, source)
  if demo then sys.sleep(40) end
end
term.fullscreen(false)
