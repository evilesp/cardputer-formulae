#!lua
-- snowfall: snow falling on a quiet winter night, with a big moon, pine trees, a lit cabin and snow that slowly piles up
-- on the ground. a and d blow the wind, w and s make it snow harder or softer, space brings a gust, q quits.
-- Needs the graphics (firmware v0.1.0.13). Run it with --selftest to check the snow.

local W, H = 240, 135
local GROUND = 112

local function newFlake(layer)
  return { x = math.random(-20, W + 20), y = math.random(-H, 0), layer = layer, ph = math.random() * 6.28 }
end

-- the speed and the size of a flake of each layer (1 far, 3 near)
local SPEED = { 0.35, 0.7, 1.2 }
local SIZE = { 1, 1, 2 }
local SHADE = { 0x8090b0, 0xc0cce0, 0xffffff }

-- moves a flake; true when it landed
local function drift(f, wind, t)
  f.y = f.y + SPEED[f.layer]
  f.x = f.x + wind * SPEED[f.layer] + math.sin(t * 0.04 + f.ph) * 0.25
  return f.y >= GROUND - 2
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local f = { x = 100, y = 0, layer = 3, ph = 0 }
  drift(f, 0, 0)
  check(f.y == SPEED[3], "a near flake falls faster than a far one")
  local g = { x = 100, y = 0, layer = 1, ph = 0 }
  drift(g, 1, 0)
  check(g.x > 100.3, "the wind pushes a flake right")
  local low = { x = 0, y = GROUND - 1, layer = 2, ph = 0 }
  check(drift(low, 0, 0), "a flake lands on the ground")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("snowfall needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("snowfall: cannot take the screen")
  return
end

-- the pine trees, made once: x, height
local trees = {}
for i = 1, 11 do trees[i] = { x = i * 22 - 10 + math.random(-6, 6), h = 26 + math.random(0, 22) } end
local pile = {}
for x = 0, W - 1 do pile[x] = 0 end

local function pine(x, h)
  for layer = 0, 3 do
    local top = GROUND - h + layer * (h // 4)
    local half = 5 + layer * 4
    gfx.triangle(x, top - 8, x - half, top + h // 4 + 2, x + half, top + h // 4 + 2, 0x0c2018)
    gfx.triangle(x, top - 8, x - half // 2, top - 2 + layer, x + half // 2, top - 2 + layer, 0xc8d4e4)
  end
  gfx.fill(x - 1, GROUND - 5, 3, 6, 0x2a1c14)
end

local ok, problem = pcall(function()
  local flakes = {}
  for i = 1, 160 do flakes[i] = newFlake(i % 3 + 1) end
  local count, wind, shown, t = 80, 0.15, sys.millis(), 0
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == "a" or k == "left" then wind = math.max(-1.2, wind - 0.2)
      elseif k == "d" or k == "right" then wind = math.min(1.2, wind + 0.2)
      elseif k == "w" or k == "up" then count = math.min(160, count + 20)
      elseif k == "s" or k == "down" then count = math.max(10, count - 20)
      elseif k == " " then wind = wind >= 0 and 1.2 or -1.2 end
      k = key.poll()
    end
    t = t + 1
    wind = wind * 0.997
    -- the sky, the moon and the stars
    for y = 0, GROUND, 8 do
      local f = y / GROUND
      gfx.fill(0, y, W, 8, ((math.floor(8 + 22 * f) << 16) | (math.floor(12 + 30 * f) << 8) | math.floor(32 + 40 * f)))
    end
    for i = 1, 40 do gfx.pixel((i * 53) % W, (i * 29) % 70, 0x8090b8) end
    gfx.disc(196, 28, 17, 0x2a3350)
    gfx.disc(196, 28, 15, 0xe8ecc8)
    gfx.disc(190, 24, 3, 0xcfd4b0)
    gfx.disc(201, 33, 2, 0xcfd4b0)
    -- the ground with its pile of snow
    gfx.fill(0, GROUND, W, H - GROUND, 0xdfe6f2)
    for x = 0, W - 1, 1 do
      if pile[x] > 0 then gfx.vline(x, GROUND - math.floor(pile[x]), GROUND, 0xdfe6f2) end
    end
    for _, tr in ipairs(trees) do pine(tr.x, tr.h) end
    -- the cabin with a warm window and a plume of smoke
    gfx.fill(98, GROUND - 22, 36, 22, 0x3a2418)
    gfx.triangle(94, GROUND - 22, 138, GROUND - 22, 116, GROUND - 38, 0x1a1218)
    gfx.triangle(94, GROUND - 22, 138, GROUND - 22, 116, GROUND - 38, 0xe8eef8)
    gfx.fill(98, GROUND - 22, 36, 3, 0x2a1810)
    gfx.fill(106, GROUND - 17, 9, 9, 0xffc060)
    gfx.rect(106, GROUND - 17, 9, 9, 0x6a4020)
    gfx.fill(122, GROUND - 14, 7, 14, 0x24140c)
    for i = 0, 5 do gfx.disc(126 + math.floor(math.sin(t * 0.05 + i) * 2) + i * wind * 2, GROUND - 44 - i * 5, 2 + i // 2, 0x9098a8) end
    -- the flakes
    for i = 1, count do
      local f = flakes[i]
      if drift(f, wind, t) then
        local x = math.max(0, math.min(W - 1, math.floor(f.x)))
        pile[x] = math.min(7, pile[x] + 0.12)
        if x > 0 and pile[x - 1] < pile[x] - 1 then pile[x - 1] = pile[x - 1] + 0.1 end
        if x < W - 1 and pile[x + 1] < pile[x] - 1 then pile[x + 1] = pile[x + 1] + 0.1 end
        flakes[i] = newFlake(f.layer)
        flakes[i].y = -3
      else
        local s = SIZE[f.layer]
        if f.x < -3 then f.x = W + 3 elseif f.x > W + 3 then f.x = -3 end
        gfx.fill(math.floor(f.x), math.floor(f.y), s, s, SHADE[f.layer])
      end
    end
    if sys.millis() - shown < 1800 then gfx.text(4, 4, "a d w s space q", 0xffffff, 1) end
    gfx.flush()
    sys.sleep(5)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("snowfall: " .. tostring(problem)) end
