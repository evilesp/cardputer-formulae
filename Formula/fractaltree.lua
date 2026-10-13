#!lua
-- fractaltree: a fractal tree grows from the ground one level of forks at a time, then sways in the wind, and its
-- twigs turn green towards the tips. a d change the spread of the forks (10 to 70 degrees), w s the wind, space plants
-- a new tree, p pauses, q quits. Needs the graphics (firmware v0.1.0.13). Run it with --selftest to check the maths.

local W, H = 240, 135
local BASE_X, BASE_Y = 120, 121
local LEVELS = 8               -- levels of branches: the trunk and seven rounds of forks
local RATIO = 0.72             -- each branch is this much shorter than the one it grows from
local GROW_STEP = 0.03         -- levels per frame while the tree grows
local HOLD = 150               -- frames a full tree stays on the screen before a new one is planted
local SPREAD_MIN, SPREAD_MAX, SPREAD_STEP = 10, 70, 4
local TRUNK_COL, LEAF_COL = 0x6b4a2b, 0x3fbf4f
local GROUND_COL, TEXT_COL = 0x3a6b2a, 0x9aa8c0

local grow = 0                 -- how far the tree has grown, 0 to LEVELS
local spread = 30              -- degrees between the two branches of a fork
local wind = 0.5               -- 0 to 1, how far the branches sway
local trunk = 26               -- length of the trunk in pixels
local sway = {}                -- the bend added at each level this frame, set up once and updated each frame
local colours = {}             -- the colour of each level, set up once

-- the share of a branch on this level that is drawn: 0 before it starts, 1 when it is full
local function partial(level, g)
  if g >= level + 1 then return 1 end
  if g > level then return g - level end
  return 0
end

-- one colour between two colours: t 0 gives a, t 1 gives b
local function lerpColour(a, b, t)
  local out = 0
  for shift = 16, 0, -8 do
    local p = (a >> shift) & 255
    local q = (b >> shift) & 255
    out = (out << 8) | math.floor(p + (q - p) * t + 0.5)
  end
  return out
end

-- the bend of each level, a small swing that moves along the tree as the time goes on
local function updateSway(time)
  for level = 0, LEVELS - 1 do
    sway[level] = wind * 0.04 * math.sin(time + level * 0.7)
  end
end

local function setup()
  for level = 0, LEVELS - 1 do
    colours[level] = lerpColour(TRUNK_COL, LEAF_COL, level / (LEVELS - 1))
    sway[level] = 0
  end
end

-- draws a branch from (x, y) at the angle ang, then its two forks; nothing is made in the loop, it only draws
local function branch(x, y, ang, level)
  local f = partial(level, grow)
  if f <= 0 then return end
  local len = trunk * RATIO ^ level * f
  local x1, y1 = x + math.cos(ang) * len, y + math.sin(ang) * len
  local c = colours[level]
  gfx.line(x, y, x1, y1, c)
  if level < 2 then gfx.line(x + 1, y, x1 + 1, y1, c) end -- the trunk and the first forks are two pixels thick
  if level == LEVELS - 1 then
    if f >= 1 then gfx.disc(math.floor(x1 + 0.5), math.floor(y1 + 0.5), 2, LEAF_COL) end
    return
  end
  local half = math.rad(spread) / 2
  branch(x1, y1, ang - half + sway[level], level + 1)
  branch(x1, y1, ang + half + sway[level], level + 1)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(partial(0, 0) == 0 and partial(0, 0.5) == 0.5 and partial(0, 1) == 1, "the trunk grows from 0 to 1")
  check(partial(2, 1.5) == 0 and partial(1, 1.5) == 0.5 and partial(1, 3) == 1, "a level starts once the level below is full")
  check(partial(3, 0.3) == 0 and partial(LEVELS - 1, LEVELS) == 1, "the tips are the last to grow")
  check(RATIO > 0 and RATIO < 1, "each branch is shorter than the one it grows from")
  check(trunk * RATIO ^ (LEVELS - 1) > 1, "the smallest twig is still longer than a pixel")
  check(lerpColour(0x000000, 0xffffff, 0.5) == 0x808080, "colour halfway between black and white")
  setup()
  check(colours[0] == TRUNK_COL and colours[LEVELS - 1] == LEAF_COL, "trunk brown, tips green")
  local g, r = (colours[LEVELS - 1] >> 8) & 255, (colours[LEVELS - 1] >> 16) & 255
  check(g > r, "the tips are greener than red")
  wind = 0
  updateSway(1.3)
  local still = true
  for level = 0, LEVELS - 1 do if sway[level] ~= 0 then still = false end end
  check(still, "no wind, no sway")
  wind = 1
  updateSway(0.4)
  local small = true
  for level = 0, LEVELS - 1 do if math.abs(sway[level]) > 0.04 + 1e-9 then small = false end end
  check(small, "the sway of one level stays under 0.04 radians")
  wind = 0.5
  check(SPREAD_MIN <= 30 and 30 <= SPREAD_MAX and (SPREAD_MAX - SPREAD_MIN) % SPREAD_STEP == 0, "the spread starts inside its range")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("fractaltree needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("fractaltree: cannot take the screen")
  return
end

local ok, problem = pcall(function()
  local time, paused, hold = 0, false, 0

  local function plant()
    grow = 0
    hold = 0
    trunk = math.random(22, 30)
  end

  setup()
  plant()
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " then plant()
      elseif k == "p" then paused = not paused
      elseif k == "a" or k == "left" then spread = math.max(SPREAD_MIN, spread - SPREAD_STEP)
      elseif k == "d" or k == "right" then spread = math.min(SPREAD_MAX, spread + SPREAD_STEP)
      elseif k == "w" or k == "up" then wind = math.min(1, wind + 0.1)
      elseif k == "s" or k == "down" then wind = math.max(0, wind - 0.1) end
      k = key.poll()
    end
    if not paused then
      time = time + 0.05
      if grow < LEVELS then
        grow = math.min(LEVELS, grow + GROW_STEP)
      else
        hold = hold + 1
        if hold >= HOLD then plant() end
      end
    end
    updateSway(time)
    gfx.clear(0x000000)
    gfx.hline(0, BASE_Y + 1, W, GROUND_COL)
    branch(BASE_X, BASE_Y, -math.pi / 2, 0)
    gfx.fill(0, 122, W, 13, 0x000000)
    gfx.text(2, 124, "a d spread " .. spread .. "  w s wind " .. math.floor(wind * 10 + 0.5) .. "  space new", TEXT_COL, 1)
    gfx.flush()
    sys.sleep(30)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("fractaltree: " .. tostring(problem)) end
