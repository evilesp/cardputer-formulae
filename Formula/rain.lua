#!lua
-- rain: a rainy night in the city. Rain falls in three layers (far drops thin and slow, near ones long and bright), splashes
-- on the street, and the lit windows and the street lamp shine back from the wet road. Now and then a car drives by with its
-- headlights cutting through the rain, and a storm sends forked lightning with a rumble of thunder. w and s make the rain
-- heavier or lighter, a and d change the wind, space calls lightning, m turns the sound off and on, q quits.
-- Needs the graphics (firmware v0.1.0.13); the thunder needs audio.beep (firmware v0.1.0.18). Run it with --selftest.

local W, H = 240, 135
local STREET = 104   -- where the street begins
local LAYERS = { { speed = 4, len = 3, col = 0x3a4866, wind = 0.6 }, { speed = 6.5, len = 6, col = 0x6a7ea6, wind = 0.8 },
                 { speed = 10, len = 11, col = 0xb0c4ea, wind = 1 } }

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

local function newDrop(layer, top)
  return { x = math.random(-40, W + 40), y = top and math.random(-H, 0) or math.random(-H, H), layer = layer }
end

-- the drops of the show are kept in three flat lists (x, y, layer): a table per drop took about 130 bytes, and the rain
-- with its city did not fit in the memory of the Cardputer
local MAX_DROPS = 160

-- moves a drop; true when it reached the street (near drops fall further down the street, they are closer to you)
local function fall(d, wind)
  local L = LAYERS[d.layer]
  d.y = d.y + L.speed
  d.x = d.x + wind * L.speed * 0.3 * L.wind
  local ground = STREET + (d.layer - 1) * 12
  return d.y >= ground
end

-- a forked bolt from the sky down to (x, y): a list of line segments, with a branch or two
local function bolt(x, y, seed)
  local segs, cx, cy, i = {}, x + (noise(seed) - 0.5) * 60, 0, 0
  while cy < y do
    i = i + 1
    local nx = cx + (noise(seed + i) - 0.5) * 18 + (x - cx) * 0.15
    local ny = math.min(y, cy + 6 + noise(seed + i * 3) * 8)
    segs[#segs + 1] = { cx, cy, nx, ny, 1 }
    if noise(seed + i * 7) > 0.8 then  -- a branch
      local bx, by = nx, ny
      for j = 1, 3 do
        local ex, ey = bx + (noise(seed + i * 11 + j) - 0.3) * 14, by + 5 + noise(seed + j) * 6
        segs[#segs + 1] = { bx, by, ex, ey, 0 }
        bx, by = ex, ey
      end
    end
    cx, cy = nx, ny
  end
  return segs
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local d = { x = 10, y = STREET - 1, layer = 1 }
  check(fall(d, 0), "a far drop lands on the street")
  local n = { x = 10, y = STREET - 1, layer = 3 }
  check(not fall(n, 0), "a near drop falls further down")
  local w = { x = 10, y = 0, layer = 2 }
  fall(w, 2)
  check(w.x > 10, "the wind pushes the drops")
  local segs = bolt(100, 60, 5)
  local reached = false
  for _, s in ipairs(segs) do if s[5] == 1 and math.abs(s[4] - 60) < 1e-9 then reached = true end end
  check(#segs > 4 and reached, "the bolt reaches its target")
  check(mix(0, 0xffffff, 0.5) == 0x808080, "mixing")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("rain needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end

-- the buildings, made once: x, width, height and colour. Their windows are worked out when they are drawn (no list of them).
local buildings = {}
do
  local x = -6
  local i = 0
  while x < W do
    i = i + 1
    local w = 22 + math.floor(noise(i) * 18)
    local h = 30 + math.floor(noise(i + 20) * 46)
    buildings[#buildings + 1] = { x = x, w = w, h = h, col = mix(0x0c1220, 0x161e30, noise(i + 40)) }
    x = x + w + 1
  end
end
-- calls f(x, y, colour, n) for each lit window of building b at the time t
local function eachWindow(b, i, t, f)
  local n = 0
  for wy = STREET - b.h + 5, STREET - 10, 8 do
    for wx = b.x + 4, b.x + b.w - 7, 7 do
      if noise(wx * 0.37 + wy * 0.91) > 0.55 then
        n = n + 1
        if noise(n * 3.7 + i + (t // 400)) > 0.12 then f(wx, wy, noise(wx + wy) > 0.5 and 0xf0c060 or 0xd8e0f0, n) end
      end
    end
  end
end
local LAMP_X = 172

if not gfx.open() then
  print("rain: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local count, wind, sound = 100, 0.3, true
  local DX, DY, DL = {}, {}, {}
  for i = 1, MAX_DROPS do
    local d = newDrop(i % 3 + 1, false)
    DX[i], DY[i], DL[i] = d.x, d.y, d.layer
  end
  local SPX, SPY, SPA, SPL, nSplash = {}, {}, {}, {}, 0  -- the splashes, also flat
  for i = 1, 40 do SPX[i], SPY[i], SPA[i], SPL[i] = 0, 0, 0, 0 end
  local flash, boltSegs, boltLife, nextFlash = 0, nil, 0, sys.millis() + 7000
  local thunderAt, thunderStep = nil, 0
  local car, nextCar = nil, sys.millis() + 3000
  local shown, t = sys.millis(), 0
  local function strike()
    flash = 1
    boltSegs = bolt(30 + math.random() * 180, 40 + math.random() * 30, math.random() * 1000)
    boltLife = 1
    thunderAt, thunderStep = sys.millis() + 300 + math.random(0, 700), 0
  end
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " then strike()
      elseif k == "m" then sound = not sound
      elseif k == "w" or k == "up" then count = math.min(MAX_DROPS, count + 30)
      elseif k == "s" or k == "down" then count = math.max(20, count - 30)
      elseif k == "a" or k == "left" then wind = math.max(-1.6, wind - 0.3)
      elseif k == "d" or k == "right" then wind = math.min(1.6, wind + 0.3) end
      k = key.poll()
    end
    t = t + 1
    local now = sys.millis()
    if now > nextFlash then
      strike()
      nextFlash = now + 8000 + math.random(0, 12000)
    end
    -- the thunder: a few low notes falling in pitch after the flash
    if thunderAt and now >= thunderAt then
      if sound and audio and audio.beep then pcall(audio.beep, 70 - thunderStep * 6 + math.random(0, 12), 140) end
      thunderStep = thunderStep + 1
      thunderAt = thunderStep < 5 and now + 120 or nil
    end
    local lit = flash
    flash = flash > 0.03 and flash * (flash > 0.6 and 0.7 or 0.85) or 0
    if flash < 0.5 and flash > 0.3 and math.random() < 0.15 then flash = 0.8 end  -- the flicker of a strike
    -- the sky: low clouds lit by the city, white for a moment in a flash
    for y = 0, STREET, 6 do
      gfx.fill(0, y, W, 6, mix(mix(0x080b14, 0x1e2232, y / STREET), 0xc8d4ff, lit * (0.9 - y / STREET * 0.4)))
    end
    if boltSegs and boltLife > 0 then
      for _, sg in ipairs(boltSegs) do
        local c = sg[5] == 1 and mix(0x8aa0ff, 0xffffff, boltLife) or mix(0x5060a0, 0xc8d0ff, boltLife)
        gfx.line(math.floor(sg[1]), math.floor(sg[2]), math.floor(sg[3]), math.floor(sg[4]), c)
        if sg[5] == 1 then gfx.line(math.floor(sg[1]) + 1, math.floor(sg[2]), math.floor(sg[3]) + 1, math.floor(sg[4]), c) end
      end
      boltLife = boltLife - 0.12
    end
    -- the buildings and their windows, which go on and off now and then
    for i, b in ipairs(buildings) do
      gfx.fill(b.x, STREET - b.h, b.w, b.h, mix(b.col, 0x6a78a0, lit * 0.5))
      eachWindow(b, i, t, function(x, y, c) gfx.fill(x, y, 3, 4, c) end)
    end
    -- the street, wet and dark, with the lights mirrored in it as shaking streaks
    gfx.fill(0, STREET, W, H - STREET, mix(0x0c1018, 0x50607c, lit * 0.6))
    for i, b in ipairs(buildings) do
      eachWindow(b, i, t, function(x, y, c, n)
        if n % 2 == 0 then
          local ry = STREET + (STREET - y) // 3
          if ry < H then
            local wob = math.floor(math.sin(t * 0.4 + n) * 1.5)
            gfx.vline(x + 1 + wob, ry, math.min(H - 1, ry + 3), mix(0x0c1018, c, 0.35))
          end
        end
      end)
    end
    -- the street lamp, its cone of light in the rain and its long reflection
    gfx.vline(LAMP_X, 54, STREET + 2, 0x2a3040)
    gfx.fill(LAMP_X - 8, 52, 12, 3, 0x2a3040)
    -- the lamp lights the drops in its cone (see the drops) and a pool of light on the street
    for r = 9, 4, -2 do gfx.disc(LAMP_X - 4, 56, r, mix(0x1a1e2a, 0x8a7a50, (9 - r) / 10)) end
    gfx.disc(LAMP_X - 4, 56, 3, 0xfff0b8)
    for i = 0, 3 do gfx.hline(LAMP_X - 26 + i * 4, LAMP_X + 18 - i * 4, STREET + 1 + i, mix(0x0c1018, 0x6a5a30, 0.6 - i * 0.12)) end
    for y = STREET + 2, H - 1, 2 do
      local wob = math.floor(math.sin(y * 0.9 + t * 0.3) * 3)
      local half = 2 + (y - STREET) // 6
      gfx.hline(LAMP_X - 4 - half + wob, LAMP_X - 4 + half + wob, y, mix(0x0c1018, 0xc8a050, 0.55 - (y - STREET) / 60))
    end
    -- a car driving by with its headlights
    if not car and now > nextCar then
      car = { x = -50, v = 2.5 + math.random() * 1.5 }
      nextCar = now + 9000 + math.random(0, 9000)
    end
    if car then
      car.x = car.x + car.v
      local cx, cy = math.floor(car.x), STREET + 14
      gfx.triangle(cx + 30, cy - 4, cx + 110, cy - 20, cx + 110, cy + 10, 0x26261e)  -- the beam in the rain
      gfx.fill(cx, cy - 8, 32, 8, 0x1a1e28)
      gfx.fill(cx + 6, cy - 13, 18, 6, 0x141820)
      gfx.fill(cx + 8, cy - 12, 6, 4, 0x3a4458)
      gfx.fill(cx + 16, cy - 12, 6, 4, 0x3a4458)
      gfx.fill(cx + 29, cy - 6, 3, 2, 0xfff4c8)
      gfx.fill(cx, cy - 6, 2, 2, 0xff3020)
      gfx.disc(cx + 7, cy, 3, 0x050505)
      gfx.disc(cx + 25, cy, 3, 0x050505)
      gfx.hline(cx + 2, cx + 30, cy + 4, 0x2a2a30)
      if car.x > W + 10 then car = nil end
    end
    -- the drops: far ones first
    for i = 1, count do
      local layer = DL[i]
      local L = LAYERS[layer]
      local x = DX[i] + wind * L.speed * 0.3 * L.wind
      local y = DY[i] + L.speed
      if y >= STREET + (layer - 1) * 12 then
        if nSplash < 40 then
          nSplash = nSplash + 1
          SPX[nSplash], SPY[nSplash], SPA[nSplash], SPL[nSplash] = math.floor(x), math.floor(y), 0, layer
        end
        DX[i], DY[i] = math.random(-40, W + 40), -10
      else
        DX[i], DY[i] = x, y
        local inLamp = layer > 1 and y > 56 and math.abs(x - (LAMP_X - 4)) < (y - 56) * 0.5
        local inBeam = car and x > car.x + 30 and x < car.x + 110 and math.abs(y - (STREET + 10)) < (x - car.x - 30) * 0.2 + 4
        local colour = (inLamp or inBeam) and 0xfff0c0 or mix(L.col, 0xffffff, lit * 0.7)
        gfx.line(math.floor(x), math.floor(y), math.floor(x - wind * L.len * 0.3), math.floor(y - L.len), colour)
      end
    end
    -- the splashes: a little crown of two dots that spreads and fades
    local j = 1
    while j <= nSplash do
      SPA[j] = SPA[j] + 1
      local age = SPA[j]
      if age < 5 then
        local spread, sx, sy = age * SPL[j], SPX[j], SPY[j]
        local c = mix(0x9ab0d8, 0x0c1018, age / 5)
        gfx.pixel(sx - spread, sy - 2 + age // 2, c)
        gfx.pixel(sx + spread, sy - 2 + age // 2, c)
        if SPL[j] == 3 then gfx.hline(sx - spread, sx + spread, sy + 1, mix(0x40506c, 0x0c1018, age / 5)) end
        j = j + 1
      else
        SPX[j], SPY[j], SPA[j], SPL[j] = SPX[nSplash], SPY[nSplash], SPA[nSplash], SPL[nSplash]
        nSplash = nSplash - 1
      end
    end
    if now - shown < 1800 then gfx.text(4, 4, "space m w s a d q", 0xffffff, 1) end
    gfx.flush()
    sys.sleep(5)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("rain: " .. tostring(problem)) end
