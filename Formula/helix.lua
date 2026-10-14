#!lua
-- helix: a double helix (DNA) turning on the screen. Two strands wind round a vertical axis, the front one is brighter,
-- and rungs join them. w and s turn it faster or slower, a and d make the coil longer or tighter, space changes the
-- colours, p pauses, q quits. Needs the graphics (firmware v0.1.0.13). Run it with --selftest to check the maths.

local W, H = 240, 135
local CX = W / 2
local RADIUS = 44          -- how far each strand is from the axis, in pixels
local RUNG_EVERY = 9      -- a rung every this many pixels down the screen
local STEP = 3            -- sample the strands every this many pixels (speed of the drawing)
local WAVE_MIN, WAVE_MAX = 30, 140

local THEMES = {
  { name = "classic", bg = 0x060a14, a = 0x20d0c0, b = 0xf050c0, rung = 0x7080a8 },
  { name = "fire",    bg = 0x120604, a = 0xff8020, b = 0xffe060, rung = 0x90402a },
  { name = "ice",     bg = 0x040c18, a = 0x80e0ff, b = 0xe0f8ff, rung = 0x4070a0 },
  { name = "mono",    bg = 0x0a0a0a, a = 0xe0e0e0, b = 0x909090, rung = 0x505050 },
}

-- a colour scaled by a brightness from 0 to 1 (the depth shading of a strand)
local function shade(colour, level)
  if level >= 1 then return colour end
  if level <= 0 then return 0 end
  local r, g, b = (colour >> 16) & 255, (colour >> 8) & 255, colour & 255
  return (math.floor(r * level) << 16) | (math.floor(g * level) << 8) | math.floor(b * level)
end

-- the brightness of a point at depth d (from -1 at the back to 1 at the front): never fully dark
local function depthLevel(d)
  return 0.35 + 0.65 * (d + 1) / 2
end

-- the x position and depth of strand A at height y; strand B is the same turned by half a turn
local function strandAt(theta, wave, y)
  local angle = theta + y * (2 * math.pi / wave)
  return CX + RADIUS * math.cos(angle), math.sin(angle)
end

local function clampWave(w)
  if w < WAVE_MIN then return WAVE_MIN end
  if w > WAVE_MAX then return WAVE_MAX end
  return w
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(shade(0xffffff, 1) == 0xffffff, "a full brightness keeps the colour")
  check(shade(0xffffff, 0) == 0, "zero brightness is black")
  check(shade(0x804020, 0.5) == 0x402010, "half brightness halves each channel")
  check(depthLevel(1) == 1 and math.abs(depthLevel(-1) - 0.35) < 1e-9, "depth shading runs from 0.35 to 1")
  local x0, d0 = strandAt(0, 60, 0)
  check(math.abs(x0 - (CX + RADIUS)) < 1e-9 and math.abs(d0) < 1e-9, "strand A starts at the right, level with the axis")
  local x1, d1 = strandAt(0, 60, 15)
  check(math.abs(x1 - CX) < 1e-9 and math.abs(d1 - 1) < 1e-9, "a quarter of a wave later A is at the front")
  local x2, _ = strandAt(0, 60, 60)
  check(math.abs(x2 - (CX + RADIUS)) < 1e-6, "one wavelength later A is back where it started")
  check(clampWave(5) == WAVE_MIN and clampWave(900) == WAVE_MAX and clampWave(60) == 60, "the coil length stays in its range")
  check(#THEMES == 4 and THEMES[1].name == "classic", "themes")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("helix needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("helix: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local theta, speed, wave, paused, theme = 0, 0.06, 60, false, 1
  local shown = sys.millis()
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " then theme = theme % #THEMES + 1 shown = sys.millis()
      elseif k == "p" then paused = not paused shown = sys.millis()
      elseif k == "w" or k == "up" then speed = math.min(0.4, speed + 0.02) shown = sys.millis()
      elseif k == "s" or k == "down" then speed = math.max(0.0, speed - 0.02) shown = sys.millis()
      elseif k == "a" or k == "left" then wave = clampWave(wave + 6) shown = sys.millis()
      elseif k == "d" or k == "right" then wave = clampWave(wave - 6) shown = sys.millis() end
      k = key.poll()
    end
    local t = THEMES[theme]
    gfx.clear(t.bg)
    for y = 0, H - 1, STEP do
      local xa, da = strandAt(theta, wave, y)
      local xb, db = strandAt(theta + math.pi, wave, y)
      if y % RUNG_EVERY < STEP then
        gfx.line(math.floor(xa + 0.5), y, math.floor(xb + 0.5), y, shade(t.rung, 0.6))
      end
      -- the back strand first, so the front one covers it
      if da >= db then
        gfx.disc(math.floor(xb + 0.5), y, 3, shade(t.b, depthLevel(db)))
        gfx.disc(math.floor(xa + 0.5), y, 3, shade(t.a, depthLevel(da)))
      else
        gfx.disc(math.floor(xa + 0.5), y, 3, shade(t.a, depthLevel(da)))
        gfx.disc(math.floor(xb + 0.5), y, 3, shade(t.b, depthLevel(db)))
      end
    end
    if not paused then theta = theta + speed end
    if sys.millis() - shown < 1800 then
      gfx.text(4, 4, t.name .. (paused and "  paused" or "") .. "  space w s a d q", 0xffffff, 1)
    end
    gfx.flush()
    sys.sleep(20)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("helix: " .. tostring(problem)) end
