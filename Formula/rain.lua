#!lua
-- rain: rain falling on a dark city street at night, with ripples in the puddles, the glow of a street lamp and sometimes
-- lightning. w and s make the rain heavier or lighter, a and d change the wind, space calls a flash of lightning (it also
-- comes by itself), q quits. Needs the graphics (firmware v0.1.0.13).
-- Run it with --selftest to check the drops.

local W, H = 240, 135
local GROUND = 112

local function newDrop(wind)
  return { x = math.random(-30, W + 30), y = math.random(-H, 0), v = 5 + math.random() * 4, len = 4 + math.random(0, 5) }
end

-- moves a drop; true when it has reached the ground
local function fall(d, wind)
  d.y = d.y + d.v
  d.x = d.x + wind * d.v * 0.25
  return d.y >= GROUND + math.random(0, 18)
end

local function mix(a, b, t)
  t = math.max(0, math.min(1, t))
  local function ch(sh) return math.floor(((a >> sh) & 255) + (((b >> sh) & 255) - ((a >> sh) & 255)) * t + 0.5) end
  return (ch(16) << 16) | (ch(8) << 8) | ch(0)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local d = { x = 10, y = GROUND - 1, v = 6, len = 5 }
  check(fall(d, 0) or d.y > GROUND - 1, "a drop moves down")
  local d2 = { x = 10, y = 0, v = 6, len = 5 }
  fall(d2, 2)
  check(d2.x > 10, "the wind pushes a drop to the right")
  check(mix(0, 0xffffff, 0.5) == 0x808080, "mixing")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("rain needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("rain: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local count, wind, flash, nextFlash = 60, 0.3, 0, sys.millis() + 9000
  local drops, ripples = {}, {}
  for i = 1, 140 do drops[i] = newDrop(wind) end
  local shown = sys.millis()
  local t = 0
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " then flash = 1 elseif k == "w" or k == "up" then count = math.min(140, count + 20)
      elseif k == "s" or k == "down" then count = math.max(10, count - 20)
      elseif k == "a" or k == "left" then wind = math.max(-1.5, wind - 0.3)
      elseif k == "d" or k == "right" then wind = math.min(1.5, wind + 0.3) end
      k = key.poll()
    end
    t = t + 1
    if sys.millis() > nextFlash then
      flash = 1
      nextFlash = sys.millis() + 6000 + math.random(0, 10000)
    end
    local lit = flash > 0 and flash or 0
    flash = flash > 0.05 and flash * 0.82 or 0
    -- the sky and the street, brighter for a moment when it flashes
    gfx.clear(mix(0x070a12, 0xb8c8ff, lit))
    for y = 0, GROUND, 8 do gfx.fill(0, y, W, 8, mix(mix(0x070a12, 0x121c30, y / GROUND), 0xb8c8ff, lit * 0.7)) end
    -- buildings with lit windows
    for b = 0, 7 do
      local bx, bw, bh = b * 32 - 4, 28, 36 + (b * 37) % 34
      gfx.fill(bx, GROUND - bh, bw, bh, mix(0x0b0f1a, 0x6070a0, lit * 0.5))
      for wy = GROUND - bh + 5, GROUND - 8, 9 do
        for wx = bx + 4, bx + bw - 8, 8 do
          if (wx * 7 + wy * 13 + b) % 5 < 2 then gfx.fill(wx, wy, 4, 5, 0xf0c060) end
        end
      end
    end
    gfx.fill(0, GROUND, W, H - GROUND, mix(0x10141f, 0x8090c0, lit * 0.6))
    -- the street lamp and its glow on the wet street
    gfx.vline(196, 58, GROUND, 0x30384a)
    gfx.fill(190, 54, 14, 4, 0x30384a)
    for r = 22, 6, -4 do gfx.circle(197, 60, r, mix(0x10141f, 0x706030, (22 - r) / 26)) end
    gfx.disc(197, 60, 4, 0xfff0b0)
    for i = 0, 7 do gfx.hline(172 + i * 2, 222 - i * 2, GROUND + 3 + i * 3, mix(0x10141f, 0x6a5a28, 0.7 - i * 0.08)) end
    -- the drops
    for i = 1, count do
      local d = drops[i]
      if fall(d, wind) then
        if d.y < H and #ripples < 40 then ripples[#ripples + 1] = { x = math.floor(d.x), y = GROUND + 4 + math.random(0, 16), age = 0 } end
        drops[i] = newDrop(wind)
        drops[i].y = -5
      else
        gfx.line(math.floor(d.x), math.floor(d.y), math.floor(d.x - wind * d.len * 0.4), math.floor(d.y - d.len), mix(0x304060, 0xc0d4ff, 0.5 + lit * 0.5))
      end
    end
    local alive = {}
    for _, r in ipairs(ripples) do
      r.age = r.age + 1
      if r.age < 9 then
        local rad = r.age * 1.4
        gfx.hline(math.floor(r.x - rad), math.floor(r.x + rad), r.y, mix(0x4a5a80, 0x10141f, r.age / 9))
        alive[#alive + 1] = r
      end
    end
    ripples = alive
    if sys.millis() - shown < 1800 then gfx.text(4, 4, "space w s a d q", 0xffffff, 1) end
    gfx.flush()
    sys.sleep(5)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("rain: " .. tostring(problem)) end
