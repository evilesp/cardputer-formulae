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

-- one colour between a and b (t from 0 to 1); no closure inside: it runs hundreds of times a frame
local function mix(a, b, t)
  if t <= 0 then return a elseif t >= 1 then return b end
  local ar, ag, ab = (a >> 16) & 255, (a >> 8) & 255, a & 255
  return (math.floor(ar + (((b >> 16) & 255) - ar) * t + 0.5) << 16) | (math.floor(ag + (((b >> 8) & 255) - ag) * t + 0.5) << 8)
    | math.floor(ab + ((b & 255) - ab) * t + 0.5)
end

local function noise(n)
  local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
  return x - math.floor(x)
end

-- made once: the pines. The stars, the hills and the sparkles are worked out from their number each frame (lists of them
-- did not fit in the memory of the Cardputer next to the snow).
local trees = {}
for i = 1, 12 do
  local x = i * 20 - 12 + math.floor(noise(i) * 10)
  if x < 86 or x > 146 then trees[#trees + 1] = { x = x, h = 16 + math.floor(noise(i + 5) * 22) } end  -- none in front of the cabin
end
table.sort(trees, function(a, b) return a.h < b.h end)
local function hill(x, far)
  if far then return math.floor(GROUND - 22 - 8 * math.sin(x * 0.02 + 0.5) - 4 * math.sin(x * 0.07)) end
  return math.floor(GROUND - 10 - 5 * math.sin(x * 0.035 + 2))
end
local MAX_FLAKES = 150
local pile = {}
for x = 0, W - 1 do pile[x] = 0 end

-- a pine with snow on each of its layers; depth (0 .. 1) is how much snow has fallen on it
local function pine(x, h, depth)
  local layers = 4
  for layer = 0, layers - 1 do
    local top = GROUND - h + layer * (h // 5)
    local half = 4 + layer * 4 + h // 12
    local bottom = top + h // 4 + 3
    gfx.triangle(x, top - 6, x - half, bottom, x + half, bottom, layer % 2 == 0 and 0x0c2a1c or 0x0f3222)
    -- the snow on the branches: a white cap and a line along the lower edge
    local cap = math.floor(2 + depth * 4)
    gfx.triangle(x, top - 6, x - cap, top - 6 + cap + 1, x + cap, top - 6 + cap + 1, 0xe4ecf8)
    if depth > 0.15 then gfx.hline(x - half + 2, x + half - 2, bottom - 1, mix(0x0c2a1c, 0xdce6f4, depth)) end
  end
  gfx.fill(x - 1, GROUND - 4, 3, 5, 0x2a1c14)
end

local ok, problem = pcall(function()
  -- the flakes in flat lists: x, y, layer and the phase of their swaying
  local FX, FY, FL, FP = {}, {}, {}, {}
  for i = 1, MAX_FLAKES do
    local f = newFlake(i % 3 + 1)
    FX[i], FY[i], FL[i], FP[i] = f.x, f.y, f.layer, f.ph
  end
  local count, wind, baseWind, shown, t = 90, 0.15, 0.15, sys.millis(), 0
  local smoke = {}
  local depth = 0
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == "a" or k == "left" then baseWind = math.max(-1.2, baseWind - 0.2)
      elseif k == "d" or k == "right" then baseWind = math.min(1.2, baseWind + 0.2)
      elseif k == "w" or k == "up" then count = math.min(MAX_FLAKES, count + 20)
      elseif k == "s" or k == "down" then count = math.max(10, count - 20)
      elseif k == " " then wind = baseWind >= 0 and 1.6 or -1.6 end
      k = key.poll()
    end
    t = t + 1
    -- the wind blows in gusts around the wind you set
    local gust = math.sin(t * 0.013) * 0.25 + math.sin(t * 0.031) * 0.15
    wind = wind + ((baseWind + gust) - wind) * 0.02
    depth = math.min(1, depth + 0.0004)
    -- the sky, cold and deep blue, a little lighter low down
    for y = 0, GROUND, 4 do gfx.fill(0, y, W, 4, mix(0x050a1c, 0x24345a, (y / GROUND) ^ 1.3)) end
    for i = 1, 55 do
      gfx.pixel(math.floor(noise(i * 1.3) * W), math.floor(noise(i * 2.1) * 60), mix(0x1a2240, 0xe8ecff, 0.4 + 0.6 * math.abs(math.sin(t * 0.03 + i))))
    end
    -- the moon with its halo
    for r = 30, 18, -4 do gfx.disc(196, 28, r, mix(mix(0x0a1228, 0x1c2a4a, 0.5), 0x6a7a9a, (30 - r) / 40)) end
    gfx.disc(196, 28, 15, 0xeef0dc)
    gfx.disc(190, 24, 3, 0xd4d8c0)
    gfx.disc(201, 33, 2, 0xd4d8c0)
    gfx.disc(198, 21, 1, 0xd4d8c0)
    -- the hills far away, white in the moonlight
    for x = 0, W - 1 do
      gfx.vline(x, hill(x, true), GROUND, 0x8a98b8)
      gfx.vline(x, hill(x, false), GROUND, 0xb0bcd4)
    end
    -- the ground: snow in the blue of the night, with sparkles and the pile that grows
    gfx.fill(0, GROUND, W, H - GROUND, 0xc8d4e8)
    gfx.fill(0, GROUND + 10, W, H - GROUND - 10, 0xb8c6de)
    for x = 0, W - 1 do
      if pile[x] > 0.5 then gfx.vline(x, GROUND - math.floor(pile[x]), GROUND, 0xd8e2f2) end
    end
    for i = 1, 30 do
      if math.sin(t * 0.08 + i * 2.7) > 0.85 then
        gfx.pixel(math.floor(noise(i * 3.3) * W), GROUND + 2 + math.floor(noise(i * 4.7) * (H - GROUND - 3)), 0xffffff)
      end
    end
    for _, tr in ipairs(trees) do pine(tr.x, tr.h, depth) end
    -- the cabin of logs, the snow on its roof, the warm window and its light on the snow
    local cx, cy = 98, GROUND - 22
    local spill = mix(0xc8d4e8, 0xffd890, 0.3)  -- the light of the window on the snow
    gfx.triangle(106, GROUND + 1, 116, GROUND + 1, 122, GROUND + 14, spill)
    gfx.triangle(106, GROUND + 1, 122, GROUND + 14, 100, GROUND + 14, spill)
    gfx.fill(cx, cy, 36, 22, 0x4a2c18)
    for ly = cy + 3, GROUND - 1, 4 do gfx.hline(cx, cx + 35, ly, 0x3a2010) end
    gfx.fill(106, GROUND - 17, 10, 9, 0xffc868)
    gfx.vline(110, GROUND - 17, GROUND - 9, 0x6a4020)
    gfx.hline(106, 115, GROUND - 13, 0x6a4020)
    gfx.fill(122, GROUND - 15, 8, 15, 0x2a160a)
    gfx.fill(126, cy - 18, 5, 12, 0x5a3a2a)  -- the chimney
    gfx.triangle(cx - 5, cy + 1, cx + 41, cy + 1, cx + 18, cy - 15, 0x2a1810)
    local snowRoof = math.floor(2 + depth * 4)
    gfx.triangle(cx - 6, cy + 1, cx + 42, cy + 1, cx + 18, cy - 15 - snowRoof // 2, 0xe8eef8)
    gfx.triangle(cx - 1, cy + 1, cx + 37, cy + 1, cx + 18, cy - 13 + snowRoof, 0x2a1810)
    gfx.fill(125, cy - 19, 7, 2 + snowRoof // 2, 0xe8eef8)
    -- the smoke from the chimney: puffs that rise, grow, drift with the wind and fade
    if t % 6 == 0 then smoke[#smoke + 1] = { x = 128, y = cy - 20, r = 2, life = 1 } end
    local alive = {}
    for _, p in ipairs(smoke) do
      p.y, p.x, p.r, p.life = p.y - 0.5, p.x + wind * 0.6 + math.sin(t * 0.05 + p.y * 0.1) * 0.2, p.r + 0.06, p.life - 0.012
      if p.life > 0 then
        gfx.disc(math.floor(p.x), math.floor(p.y), math.floor(p.r), mix(0x2a3450, 0xa8b0c4, p.life * 0.8))
        alive[#alive + 1] = p
      end
    end
    smoke = alive
    -- the flakes: far ones small and grey, near ones big and bright like stars
    for i = 1, count do
      local layer = FL[i]
      local y = FY[i] + SPEED[layer]
      local x = FX[i] + wind * SPEED[layer] + math.sin(t * 0.04 + FP[i]) * 0.25
      if y >= GROUND - 2 then
        local px = math.max(0, math.min(W - 1, math.floor(x)))
        pile[px] = math.min(8, pile[px] + 0.1)
        if px > 0 and pile[px - 1] < pile[px] - 1 then pile[px - 1] = pile[px - 1] + 0.08 end
        if px < W - 1 and pile[px + 1] < pile[px] - 1 then pile[px + 1] = pile[px + 1] + 0.08 end
        FX[i], FY[i] = math.random(-20, W + 20), -3
      else
        if x < -3 then x = W + 3 elseif x > W + 3 then x = -3 end
        FX[i], FY[i] = x, y
        local ix, iy = math.floor(x), math.floor(y)
        if layer == 3 then
          gfx.fill(ix - 1, iy, 3, 1, 0xffffff)
          gfx.fill(ix, iy - 1, 1, 3, 0xffffff)
        else
          gfx.fill(ix, iy, SIZE[layer], SIZE[layer], SHADE[layer])
        end
      end
    end
    if sys.millis() - shown < 1800 then gfx.text(4, 4, "a d w s space q", 0xffffff, 1) end
    gfx.flush()
    sys.sleep(5)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("snowfall: " .. tostring(problem)) end
