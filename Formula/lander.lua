#!lua
-- lander: land the lunar module on the flat pad between the hills. Gravity pulls it down all the time: w fires the
-- main engine (a short burst), a and d fire the side jets. Each burst uses fuel. Land on the pad slowly and upright
-- to score: the fuel left counts too. Land anywhere else, or too fast, and it crashes. n goes to the next level
-- after a landing, r starts again after a crash, q quits.
-- Needs the graphics (firmware v0.1.0.13). Run it with --selftest to check the physics.

local W, H = 240, 135
local STEP = 4            -- the terrain has a point every 4 pixels
local NPTS = W // STEP + 1
local GROUND_BASE = 8     -- the lowest the terrain goes above the bottom of the screen
local G = 0.035           -- gravity, pixels per frame each frame
local MAIN = 0.12         -- the main engine, its push per frame
local SIDE = 0.05         -- a side jet, its push per frame
local BURST = 5          -- frames one key press keeps an engine firing
local FUEL_START = 120
local SAFE_DOWN = 0.9     -- the fastest landing downwards
local SAFE_SIDE = 0.45    -- the fastest landing sideways
local PAD_CELLS = 4       -- the flat pad is this many terrain points wide

-- the height above the bottom of the screen of the terrain at point i (1 to NPTS)
local function groundPx(hgt, x)
  local i = x // STEP
  if i >= NPTS - 1 then i = NPTS - 2 end
  local f = (x - i * STEP) / STEP
  return hgt[i + 1] + (hgt[i + 2] - hgt[i + 1]) * f
end

-- a new hilly terrain with a flat pad somewhere; returns the heights and the first and last pixel of the pad
local function makeTerrain()
  local hgt = {}
  local h = 22
  for i = 1, NPTS do
    h = math.max(GROUND_BASE, math.min(44, h + math.random(-4, 4)))
    hgt[i] = h
  end
  local p = math.random(6, NPTS - PAD_CELLS - 6)
  for i = p, p + PAD_CELLS - 1 do hgt[i] = hgt[p] end
  return hgt, (p - 1) * STEP, (p + PAD_CELLS - 2) * STEP
end

-- a fresh lander above the middle of the screen
local function newLander(level)
  return { x = 120, y = 14, vx = (math.random() - 0.5) * 0.4, vy = 0, fuel = FUEL_START,
           main = 0, side = 0, sideDir = 0, level = level, score = 0 }
end

-- one frame of flight: gravity, then the engines that are still firing, then the movement
local function stepLander(s)
  s.vy = s.vy + G
  if s.main > 0 and s.fuel > 0 then
    s.vy = s.vy - MAIN
    s.main = s.main - 1
    s.fuel = s.fuel - 1
  else
    s.main = 0
  end
  if s.side > 0 and s.fuel > 0 then
    s.vx = s.vx + SIDE * s.sideDir
    s.side = s.side - 1
    s.fuel = s.fuel - 1
  else
    s.side = 0
  end
  s.x = s.x + s.vx
  s.y = s.y + s.vy
  if s.x < 2 then s.x, s.vx = 2, 0 end
  if s.x > W - 3 then s.x, s.vx = W - 3, 0 end
end

-- "land", "crash" or nil while the lander is still in the air; hits the ground when its feet reach it
local function touchdown(s, hgt, padFrom, padTo)
  -- the screen y grows downwards: the feet are 4 pixels below the top of the lander
  if s.y + 4 < H - 1 - groundPx(hgt, s.x) then return nil end
  if s.x < padFrom or s.x > padTo then return "crash" end
  if math.abs(s.vy) > SAFE_DOWN or math.abs(s.vx) > SAFE_SIDE then return "crash" end
  return "land"
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local s = { x = 100, y = 10, vx = 0, vy = 0, fuel = 50, main = 0, side = 0, sideDir = 0 }
  for _ = 1, 10 do stepLander(s) end
  check(math.abs(s.vy - 10 * G) < 1e-9 and math.abs(s.y - (10 + 0.035 * 55)) < 1e-9, "free fall adds gravity every frame")
  s = { x = 100, y = 10, vx = 0, vy = 0, fuel = 50, main = 0, side = 0, sideDir = 0 }
  s.main = BURST
  stepLander(s)
  check(math.abs(s.vy - (G - MAIN)) < 1e-9 and s.main == BURST - 1 and s.fuel == 49, "the main engine pushes up and uses fuel")
  for _ = 1, 20 do stepLander(s) end
  check(s.main == 0 and s.fuel == 45, "the burst stops after its frames and uses only those")
  s = { x = 100, y = 10, vx = 0, vy = 0, fuel = 0, main = BURST, side = BURST, sideDir = 1 }
  stepLander(s)
  check(s.vy == G and s.vx == 0, "no fuel, no thrust")
  s = { x = 1, y = 10, vx = -1, vy = 0, fuel = 50, main = 0, side = 0, sideDir = 0 }
  stepLander(s)
  check(s.x == 2 and s.vx == 0, "the lander stays inside the left wall")
  local hgt, padFrom, padTo = makeTerrain()
  local flat = true
  for i = 1, PAD_CELLS do if hgt[(padFrom // STEP) + i] ~= hgt[(padFrom // STEP) + 1] then flat = false end end
  check(flat, "the pad is flat")
  local inRange = true
  for i = 1, NPTS do if hgt[i] < GROUND_BASE or hgt[i] > 44 then inRange = false end end
  check(inRange, "the hills stay between the base and 44 pixels")
  local good = { x = padFrom + 4, y = 0, vx = 0.1, vy = 0.2 }
  good.y = H - 1 - groundPx(hgt, good.x) - 4
  check(touchdown(good, hgt, padFrom, padTo) == "land", "a soft landing on the pad")
  local fast = { x = padFrom + 4, y = 0, vx = 0, vy = 3 }
  fast.y = H - 1 - groundPx(hgt, fast.x) - 4
  check(touchdown(fast, hgt, padFrom, padTo) == "crash", "too fast crashes")
  local off = { x = 2, y = 0, vx = 0, vy = 0.1 }
  off.y = H - 1 - groundPx(hgt, off.x) - 4
  check(touchdown(off, hgt, padFrom, padTo) == "crash", "off the pad crashes")
  local high = { x = padFrom + 4, y = 10, vx = 0, vy = 0.1 }
  check(touchdown(high, hgt, padFrom, padTo) == nil, "in the air is no landing yet")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("lander needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("lander: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local level = 1
  local hgt, padFrom, padTo = makeTerrain()
  local s = newLander(level)
  local status = "steer with a d, fire the engine with w"
  local over = false

  local function nextLevel()
    level = level + 1
    hgt, padFrom, padTo = makeTerrain()
    local score = s.score
    s = newLander(level)
    s.score = score
    status = "level " .. level .. "  steer with a d, fire the engine with w"
  end

  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if not over then
        if k == "w" or k == "up" then
          if s.fuel > 0 then s.main = BURST end
        elseif k == "a" or k == "left" then
          if s.fuel > 0 then s.side, s.sideDir = BURST, 1 end
        elseif k == "d" or k == "right" then
          if s.fuel > 0 then s.side, s.sideDir = BURST, -1 end
        end
      elseif k == "n" and status == "landed" then
        nextLevel()
        over = false
      elseif k == "r" and status == "crashed" then
        level = 1
        s = newLander(1)
        hgt, padFrom, padTo = makeTerrain()
        status = "steer with a d, fire the engine with w"
        over = false
      end
      k = key.poll()
    end
    if not over then
      stepLander(s)
      local result = touchdown(s, hgt, padFrom, padTo)
      if result == "land" then
        s.score = s.score + 10 * s.level + s.fuel
        status = "landed"
        over = true
      elseif result == "crash" then
        status = "crashed"
        over = true
      end
    end

    gfx.clear(0x05070d)
    for i = 1, NPTS - 1 do
      local x1, x2 = (i - 1) * STEP, i * STEP
      gfx.line(x1, H - 1 - hgt[i], x2, H - 1 - hgt[i + 1], 0x6a7a90)
    end
    gfx.fill(padFrom, H - 2 - hgt[padFrom // STEP + 1], padTo - padFrom + 1, 2, 0xffe060)
    local cx, top = math.floor(s.x + 0.5), math.floor(s.y + 0.5)
    if s.main > 0 and s.fuel > 0 then
      gfx.line(cx, top + 6, cx - 2, top + 10, 0xff8a20)
      gfx.line(cx, top + 6, cx + 2, top + 10, 0xff8a20)
    end
    if s.side > 0 and s.fuel > 0 then
      local fx = s.sideDir == 1 and cx + 4 or cx - 4
      gfx.line(cx, top + 2, fx, top + 3, 0x40c0ff)
    end
    gfx.triangle(cx, top, cx - 4, top + 5, cx + 4, top + 5, 0xe8ecf4)
    gfx.fill(cx - 4, top + 5, 9, 1, 0xe8ecf4)
    gfx.fill(0, 0, W, 12, 0x000000)
    gfx.text(2, 2, "level " .. level .. "  fuel " .. s.fuel .. "  score " .. s.score, 0x9aa8c0, 1)
    gfx.fill(0, 122, W, 13, 0x000000)
    local hint = "w engine  a d sides  q quit"
    if status == "landed" then hint = "landed! n next level  q quit"
    elseif status == "crashed" then hint = "crashed. r again  q quit" end
    gfx.text(2, 124, hint, 0x9aa8c0, 1)
    gfx.flush()
    sys.sleep(40)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("lander: " .. tostring(problem)) end
