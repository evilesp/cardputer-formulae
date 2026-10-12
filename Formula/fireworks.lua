#!lua
-- fireworks: a firework show over a city by the water. Rockets whistle up with a trail of sparks and burst with a flash and a
-- bang into many kinds of shells: peony, chrysanthemum with trails, golden willow that hangs and falls slowly, rings, double
-- rings, palms, crossettes that split again, glitter that twinkles, hearts and crackling stars. The smoke stays in the sky
-- for a while and the water mirrors it all. space launches a rocket (more come by themselves), w and s change how often,
-- a and d move the launch place, m turns the sound off and on, q quits.
-- Needs the graphics (firmware v0.1.0.13); the whistle and the bangs need audio.beep (firmware v0.1.0.18). Run it with --selftest.

local W, H = 240, 135
local SEA = 106
local GRAVITY = 0.045
local MAX_SPARKS = 300

local function mix(a, b, t)
  if t <= 0 then return a elseif t >= 1 then return b end
  local function ch(sh) return math.floor(((a >> sh) & 255) + (((b >> sh) & 255) - ((a >> sh) & 255)) * t + 0.5) end
  return (ch(16) << 16) | (ch(8) << 8) | ch(0)
end

local function hue(h, v)
  h = (h % 1) * 6
  local i, f = math.floor(h), h - math.floor(h)
  local r, g, b
  if i == 0 then r, g, b = 1, f, 0 elseif i == 1 then r, g, b = 1 - f, 1, 0 elseif i == 2 then r, g, b = 0, 1, f
  elseif i == 3 then r, g, b = 0, 1 - f, 1 elseif i == 4 then r, g, b = f, 0, 1 else r, g, b = 1, 0, 1 - f end
  v = math.max(0, math.min(1, v))
  -- a little white mixed in: the colours of fireworks are bright, not deep
  r, g, b = r * 0.8 + 0.2, g * 0.8 + 0.2, b * 0.8 + 0.2
  return (math.floor(r * v * 255) << 16) | (math.floor(g * v * 255) << 8) | math.floor(b * v * 255)
end

local GOLD = 0xffc860
local KINDS = { "peony", "chrysanthemum", "willow", "ring", "doublering", "palm", "crossette", "glitter", "heart", "crackle" }

-- the stars of a shell bursting at (x, y): a list of sparks { x, y, vx, vy, life, decay, colour, trail, twinkle, split, crackle }
local function shell(kind, x, y, h)
  local out = {}
  local function spark(vx, vy, colour, opts)
    local s = { x = x, y = y, px = x, py = y, vx = vx, vy = vy, life = 1, decay = 0.012, colour = colour }
    if opts then for k, v in pairs(opts) do s[k] = v end end
    out[#out + 1] = s
  end
  local main, second = hue(h, 1), hue(h + 0.45, 1)
  if kind == "peony" or kind == "crackle" or kind == "glitter" then
    for i = 1, 46 do
      local a, sp = math.random() * 6.283, 0.8 + math.random() * 1.6
      spark(math.cos(a) * sp, math.sin(a) * sp, kind == "glitter" and GOLD or main,
            { twinkle = kind == "glitter", crackle = kind == "crackle", decay = kind == "glitter" and 0.009 or 0.013 })
    end
  elseif kind == "chrysanthemum" then
    for i = 1, 40 do
      local a, sp = i / 40 * 6.283, 1.7 + math.random() * 0.4
      spark(math.cos(a) * sp, math.sin(a) * sp, main, { trail = true, decay = 0.011 })
    end
  elseif kind == "willow" then
    for i = 1, 36 do
      local a, sp = i / 36 * 6.283, 1.2 + math.random() * 0.5
      spark(math.cos(a) * sp, math.sin(a) * sp, GOLD, { trail = true, decay = 0.006, drag = 0.965, heavy = true })
    end
  elseif kind == "ring" or kind == "doublering" then
    for i = 1, 36 do
      local a = i / 36 * 6.283
      spark(math.cos(a) * 2.0, math.sin(a) * 1.3, main, { decay = 0.014 })
      if kind == "doublering" then spark(math.cos(a) * 1.2, math.sin(a) * 0.8, second, { decay = 0.016 }) end
    end
  elseif kind == "palm" then
    for i = 1, 8 do
      local a = i / 8 * 6.283 - 1.57
      for j = 0, 3 do
        spark(math.cos(a) * (1.5 + j * 0.25), math.sin(a) * (1.5 + j * 0.25) - 0.4, j == 0 and 0xffffff or GOLD, { trail = j == 0, decay = 0.009 })
      end
    end
  elseif kind == "crossette" then
    for i = 1, 10 do
      local a = i / 10 * 6.283
      spark(math.cos(a) * 1.6, math.sin(a) * 1.6, main, { split = true, trail = true, decay = 0.012 })
    end
  elseif kind == "heart" then
    for i = 1, 40 do
      local a = i / 40 * 6.283
      local px = 16 * math.sin(a) ^ 3
      local py = -(13 * math.cos(a) - 5 * math.cos(2 * a) - 2 * math.cos(3 * a) - math.cos(4 * a))
      spark(px * 0.12, py * 0.12, hue(0.95, 1), { decay = 0.012, drag = 0.97 })
    end
  end
  return out
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  for _, k in ipairs(KINDS) do
    local s = shell(k, 100, 40, 0.3)
    local least = k == "crossette" and 10 or 30  -- a crossette has few stars, each splits into four later
    check(#s >= least and #s <= 80, k .. " has between " .. least .. " and 80 stars (" .. #s .. ")")
  end
  local ring = shell("ring", 0, 0, 0)
  check(math.abs(ring[1].vx ^ 2 / 4 + ring[1].vy ^ 2 / 1.69 - 1) < 1e-9, "a ring is an ellipse seen from the side")
  local w = shell("willow", 0, 0, 0)
  check(w[1].colour == GOLD and w[1].decay < 0.01, "a willow is gold and slow")
  local c = shell("crossette", 0, 0, 0)
  check(c[1].split, "crossette stars split")
  check(hue(0, 1) == 0xff3333 and hue(0, -1) == 0, "colours are bright and limited")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("fireworks needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end

-- the skyline, made once
local skyline = {}
do
  local x, i = 0, 0
  while x < W do
    i = i + 1
    local w = 10 + math.random(0, 14)
    skyline[#skyline + 1] = { x = x, w = w, h = 12 + math.random(0, 30), spire = i % 5 == 0 }
    x = x + w
  end
end

if not gfx.open() then
  print("fireworks: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local rockets, sparks, flashes, smoke = {}, {}, {}, {}
  local sounds = {}  -- { at, freq, ms }: the bangs and the crackles, played in order
  local launchX, rate, sound = W / 2, 1.0, audio ~= nil and audio.beep ~= nil
  local nextAuto, shown, glow = sys.millis() + 500, sys.millis(), 0
  local function beepLater(delay, freq, ms) sounds[#sounds + 1] = { at = sys.millis() + delay, freq = freq, ms = ms } end
  local function launch()
    local x = math.max(30, math.min(W - 30, launchX + math.random(-60, 60)))
    rockets[#rockets + 1] = { x = x, y = SEA, vy = -(3.0 + math.random() * 1.2), vx = (math.random() - 0.5) * 0.4, h = math.random(),
                              kind = KINDS[math.random(#KINDS)], whistle = 900 + math.random(0, 300) }
  end
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " then launch()
      elseif k == "m" then sound = not sound
      elseif k == "w" or k == "up" then rate = math.min(3, rate + 0.5)
      elseif k == "s" or k == "down" then rate = math.max(0.3, rate - 0.5)
      elseif k == "a" or k == "left" then launchX = math.max(40, launchX - 25)
      elseif k == "d" or k == "right" then launchX = math.min(W - 40, launchX + 25) end
      k = key.poll()
    end
    local now = sys.millis()
    if now >= nextAuto then
      launch()
      if math.random() < 0.25 then launch() end  -- sometimes two at once
      nextAuto = now + (900 + math.random(0, 1600)) / rate
    end
    -- the sounds: a bang is a low note, a crackle a few short high ones
    if sound and #sounds > 0 and now >= sounds[1].at then
      local s = table.remove(sounds, 1)
      pcall(audio.beep, s.freq, s.ms)
    end
    glow = glow * 0.88
    -- the sky lit a little by the bursts, the sea and the city
    local sky = mix(0x02030c, 0x2a2440, glow)
    for y = 0, SEA, 6 do gfx.fill(0, y, W, 6, mix(sky, mix(0x0c1028, 0x3a3050, glow), y / SEA)) end
    -- the smoke of earlier shells drifts and fades
    local keepSmoke = {}
    for _, p in ipairs(smoke) do
      p.life, p.r, p.x = p.life - 0.006, p.r + 0.08, p.x + 0.1
      if p.life > 0 then
        gfx.disc(math.floor(p.x), math.floor(p.y), math.floor(p.r), mix(sky, mix(0x2a2a3c, p.tint, 0.15), p.life * (0.18 + glow * 0.5)))
        keepSmoke[#keepSmoke + 1] = p
      end
    end
    smoke = keepSmoke
    gfx.fill(0, SEA, W, H - SEA, mix(0x040814, 0x1a1830, glow))
    for _, b in ipairs(skyline) do
      gfx.fill(b.x, SEA - b.h, b.w - 1, b.h, mix(0x0a0d18, 0x2a2840, glow))
      if b.spire then gfx.triangle(b.x + b.w // 2, SEA - b.h - 10, b.x + 2, SEA - b.h, b.x + b.w - 3, SEA - b.h, mix(0x0a0d18, 0x2a2840, glow)) end
      for wy = SEA - b.h + 3, SEA - 4, 6 do
        for wx = b.x + 2, b.x + b.w - 5, 5 do
          if (wx * 3 + wy * 5) % 7 < 3 then gfx.fill(wx, wy, 2, 2, 0xa88c40) end
        end
      end
    end
    -- the rockets climbing with a trail of sparks and a whistle
    local live = {}
    for i, r in ipairs(rockets) do
      r.y, r.x, r.vy = r.y + r.vy, r.x + r.vx, r.vy + 0.035
      if sound and i == #rockets then
        r.whistle = r.whistle + 40
        if #sounds == 0 and math.floor(r.y) % 3 == 0 then pcall(audio.beep, math.min(3200, r.whistle), 40) end
      end
      if r.vy >= -0.4 or r.y < 18 then
        for _, p in ipairs(shell(r.kind, r.x, r.y, r.h)) do
          if #sparks < MAX_SPARKS then sparks[#sparks + 1] = p end
        end
        flashes[#flashes + 1] = { x = r.x, y = r.y, life = 1, colour = hue(r.h, 1) }
        smoke[#smoke + 1] = { x = r.x, y = r.y + 4, r = 10, life = 1, tint = hue(r.h, 1) }
        glow = math.min(1, glow + 0.55)
        beepLater(0, 85 + math.random(0, 25), 160)
        if r.kind == "crackle" or r.kind == "glitter" then
          for c = 1, 5 do beepLater(500 + c * 90, 2200 + math.random(0, 1500), 25) end
        end
      else
        gfx.line(math.floor(r.x), math.floor(r.y), math.floor(r.x - r.vx * 4), math.floor(r.y - r.vy * 4), 0xffe0a0)
        gfx.pixel(math.floor(r.x + (math.random() - 0.5) * 3), math.floor(r.y + 4 + math.random() * 4), 0xffa040)
        live[#live + 1] = r
      end
    end
    rockets = live
    -- the flash of each burst: a bright disc that shrinks in a few frames
    local keepFlash = {}
    for _, f in ipairs(flashes) do
      f.life = f.life - 0.25
      if f.life > 0 then
        gfx.disc(math.floor(f.x), math.floor(f.y), math.floor(2 + f.life * 9), mix(sky, f.colour, f.life * 0.6))
        gfx.disc(math.floor(f.x), math.floor(f.y), math.floor(1 + f.life * 4), mix(f.colour, 0xffffff, f.life))
        keepFlash[#keepFlash + 1] = f
      end
    end
    flashes = keepFlash
    -- the stars of the shells
    local keep, born = {}, {}
    for _, p in ipairs(sparks) do
      p.px, p.py = p.x, p.y
      local drag = p.drag or 0.975
      p.vx, p.vy = p.vx * drag, p.vy * drag + (p.heavy and GRAVITY * 1.2 or GRAVITY)
      p.x, p.y = p.x + p.vx, p.y + p.vy
      p.life = p.life - p.decay
      if p.split and p.life < 0.55 then  -- a crossette star splits into four
        p.split = nil
        for a = 0, 3 do
          local ang = a * 1.571 + 0.785
          born[#born + 1] = { x = p.x, y = p.y, px = p.x, py = p.y, vx = math.cos(ang) * 1.1, vy = math.sin(ang) * 1.1, life = 0.6,
                              decay = 0.018, colour = mix(p.colour, 0xffffff, 0.4) }
        end
        p.life = 0
      end
      if p.life > 0 and p.y < SEA then
        local fade = p.life < 0.35 and p.life / 0.35 or 1
        local colour = mix(sky, p.life < 0.3 and mix(p.colour, 0xff9040, 0.5) or p.colour, fade)
        local draw = not p.twinkle or math.random() < 0.6
        if draw then
          local x, y = math.floor(p.x), math.floor(p.y)
          if p.trail then gfx.line(math.floor(p.px - p.vx * 3), math.floor(p.py - p.vy * 3), x, y, mix(sky, colour, 0.55)) end
          gfx.fill(x, y, p.life > 0.5 and 2 or 1, p.life > 0.5 and 2 or 1, colour)
          if p.life > 0.2 then gfx.pixel(x, SEA + (SEA - y) // 3, mix(0x040814, colour, 0.4)) end  -- in the water
        end
        if p.crackle and p.life < 0.25 and math.random() < 0.3 then gfx.fill(math.floor(p.x) - 1, math.floor(p.y) - 1, 3, 3, 0xffffff) end
        keep[#keep + 1] = p
      end
    end
    for _, b in ipairs(born) do
      if #keep < MAX_SPARKS then keep[#keep + 1] = b end
    end
    sparks = keep
    if now - shown < 1800 then gfx.text(4, 4, "space m w s a d q", 0xffffff, 1) end
    gfx.flush()
    sys.sleep(5)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("fireworks: " .. tostring(problem)) end
