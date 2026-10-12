#!lua
-- fireworks: a firework show over a city by the water. Rockets whistle up with a trail of sparks and burst with a flash and a
-- bang into many kinds of shells: peony, chrysanthemum with trails, golden willow that hangs and falls slowly, rings, double
-- rings, palms, crossettes that split again, glitter that twinkles, hearts and crackling stars. The smoke stays in the sky
-- for a while and the water mirrors it all. space launches a rocket (more come by themselves), w and s change how often,
-- a and d move the launch place, m turns the sound off and on (a sign in the corner shows it), q quits.
-- Needs the graphics (firmware v0.1.0.13); the whistle and the bangs need audio.beep (firmware v0.1.0.18). Run it with --selftest.

local W, H = 240, 135
local SEA = 106
local GRAVITY = 0.045
local MAX_SPARKS = 160
-- The stars are kept in flat lists of numbers, not one table each: a table per star took about 400 bytes, and three hundred
-- of them filled the memory of the Cardputer. Colour, flags and the speed of fading share one number.
local TRAIL, TWINKLE, SPLIT, CRACKLE, HEAVY, SOFT = 1, 2, 4, 8, 16, 32
local DECAYS = { 0.006, 0.009, 0.010, 0.012, 0.013, 0.014, 0.016, 0.018 }
local function pack(colour, flags, decay) return colour | (flags << 24) | ((decay - 1) << 30) end
local function colourOf(cf) return cf & 0xFFFFFF end
local function flagsOf(cf) return (cf >> 24) & 63 end
local function decayOf(cf) return DECAYS[((cf >> 30) & 7) + 1] end

-- one colour between a and b (t from 0 to 1); no closure inside: it runs hundreds of times a frame
local function mix(a, b, t)
  if t <= 0 then return a elseif t >= 1 then return b end
  local ar, ag, ab = (a >> 16) & 255, (a >> 8) & 255, a & 255
  return (math.floor(ar + (((b >> 16) & 255) - ar) * t + 0.5) << 16) | (math.floor(ag + (((b >> 8) & 255) - ag) * t + 0.5) << 8)
    | math.floor(ab + ((b & 255) - ab) * t + 0.5)
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

-- the stars of a shell bursting at (x, y): emit(x, y, vx, vy, packed colour and flags) is called for each
local function shell(kind, x, y, h, emit)
  local main, second = hue(h, 1), hue(h + 0.45, 1)
  local n = 0
  local function star(vx, vy, colour, flags, decay)
    n = n + 1
    emit(x, y, vx, vy, pack(colour, flags or 0, decay or 5))
  end
  if kind == "peony" or kind == "crackle" or kind == "glitter" then
    for _ = 1, 40 do
      local a, sp = math.random() * 6.283, 0.8 + math.random() * 1.6
      if kind == "glitter" then star(math.cos(a) * sp, math.sin(a) * sp, GOLD, TWINKLE, 2)
      else star(math.cos(a) * sp, math.sin(a) * sp, main, kind == "crackle" and CRACKLE or 0, 5) end
    end
  elseif kind == "chrysanthemum" then
    for i = 1, 36 do
      local a, sp = i / 36 * 6.283, 1.7 + math.random() * 0.4
      star(math.cos(a) * sp, math.sin(a) * sp, main, TRAIL, 3)
    end
  elseif kind == "willow" then
    for i = 1, 32 do
      local a, sp = i / 32 * 6.283, 1.2 + math.random() * 0.5
      star(math.cos(a) * sp, math.sin(a) * sp, GOLD, TRAIL | HEAVY, 1)
    end
  elseif kind == "ring" or kind == "doublering" then
    for i = 1, (kind == "ring" and 36 or 28) do
      local a = i / (kind == "ring" and 36 or 28) * 6.283
      star(math.cos(a) * 2.0, math.sin(a) * 1.3, main, 0, 6)
      if kind == "doublering" then star(math.cos(a) * 1.2, math.sin(a) * 0.8, second, 0, 7) end
    end
  elseif kind == "palm" then
    for i = 1, 8 do
      local a = i / 8 * 6.283 - 1.57
      for j = 0, 3 do
        star(math.cos(a) * (1.5 + j * 0.25), math.sin(a) * (1.5 + j * 0.25) - 0.4, j == 0 and 0xffffff or GOLD, j == 0 and TRAIL or 0, 2)
      end
    end
  elseif kind == "crossette" then
    for i = 1, 10 do
      local a = i / 10 * 6.283
      star(math.cos(a) * 1.6, math.sin(a) * 1.6, main, SPLIT | TRAIL, 4)
    end
  elseif kind == "heart" then
    for i = 1, 36 do
      local a = i / 36 * 6.283
      local px = 16 * math.sin(a) ^ 3
      local py = -(13 * math.cos(a) - 5 * math.cos(2 * a) - 2 * math.cos(3 * a) - math.cos(4 * a))
      star(px * 0.12, py * 0.12, hue(0.95, 1), SOFT, 4)
    end
  end
  return n
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local got = {}
  local function collect(x, y, vx, vy, cf) got[#got + 1] = { vx = vx, vy = vy, cf = cf } end
  for _, k in ipairs(KINDS) do
    got = {}
    local n = shell(k, 100, 40, 0.3, collect)
    local least = k == "crossette" and 10 or 30  -- a crossette has few stars, each splits into four later
    check(n == #got and n >= least and n <= 60, k .. " has between " .. least .. " and 60 stars (" .. n .. ")")
  end
  got = {}
  shell("ring", 0, 0, 0, collect)
  check(math.abs(got[1].vx ^ 2 / 4 + got[1].vy ^ 2 / 1.69 - 1) < 1e-9, "a ring is an ellipse seen from the side")
  got = {}
  shell("willow", 0, 0, 0, collect)
  check(colourOf(got[1].cf) == GOLD and decayOf(got[1].cf) < 0.01 and flagsOf(got[1].cf) & HEAVY ~= 0, "a willow is gold, heavy and slow")
  got = {}
  shell("crossette", 0, 0, 0, collect)
  check(flagsOf(got[1].cf) & SPLIT ~= 0, "crossette stars split")
  local cf = pack(0x123456, TRAIL | CRACKLE, 8)
  check(colourOf(cf) == 0x123456 and flagsOf(cf) == TRAIL | CRACKLE and decayOf(cf) == 0.018, "colour, flags and fading in one number")
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
  local rockets, flashes, smoke = {}, {}, {}
  local SX, SY, SVX, SVY, SLIFE, SCF = {}, {}, {}, {}, {}, {}
  for i = 1, MAX_SPARKS do SX[i], SY[i], SVX[i], SVY[i], SLIFE[i], SCF[i] = 0, 0, 0, 0, 0, 0 end
  local nSparks = 0
  local function emit(x, y, vx, vy, cf, life)
    if nSparks >= MAX_SPARKS then return end
    nSparks = nSparks + 1
    SX[nSparks], SY[nSparks], SVX[nSparks], SVY[nSparks], SLIFE[nSparks], SCF[nSparks] = x, y, vx, vy, life or 1, cf
  end
  local sounds = {}  -- { at, freq, ms }: the bangs and the crackles, played in order
  local launchX, rate, sound = W / 2, 1.0, audio ~= nil and audio.beep ~= nil
  local nextAuto, shown, glow = sys.millis() + 500, sys.millis(), 0
  local soundShown = nil
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
      elseif k == "m" then
        sound = not sound
        soundShown = sys.millis()
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
        shell(r.kind, r.x, r.y, r.h, emit)
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
    -- the stars of the shells; a star that is gone takes the place of the last one
    local i = 1
    while i <= nSparks do
      local cf = SCF[i]
      local flags = flagsOf(cf)
      local drag = (flags & HEAVY ~= 0) and 0.965 or ((flags & SOFT ~= 0) and 0.97 or 0.975)
      local vx, vy = SVX[i] * drag, SVY[i] * drag + ((flags & HEAVY ~= 0) and GRAVITY * 1.2 or GRAVITY)
      local x, y = SX[i] + vx, SY[i] + vy
      local life = SLIFE[i] - decayOf(cf)
      if flags & SPLIT ~= 0 and life < 0.55 then  -- a crossette star splits into four
        local colour = mix(colourOf(cf), 0xffffff, 0.4)
        for a = 0, 3 do
          local ang = a * 1.571 + 0.785
          emit(x, y, math.cos(ang) * 1.1, math.sin(ang) * 1.1, pack(colour, 0, 8), 0.6)
        end
        life = 0
      end
      if life > 0 and y < SEA then
        SX[i], SY[i], SVX[i], SVY[i], SLIFE[i] = x, y, vx, vy, life
        local base = colourOf(cf)
        local fade = life < 0.35 and life / 0.35 or 1
        local colour = mix(sky, life < 0.3 and mix(base, 0xff9040, 0.5) or base, fade)
        if flags & TWINKLE == 0 or math.random() < 0.6 then
          local ix, iy = math.floor(x), math.floor(y)
          if flags & TRAIL ~= 0 then gfx.line(math.floor(x - vx * 4), math.floor(y - vy * 4), ix, iy, mix(sky, colour, 0.55)) end
          local size = life > 0.5 and 2 or 1
          gfx.fill(ix, iy, size, size, colour)
          if life > 0.2 then gfx.pixel(ix, SEA + (SEA - iy) // 3, mix(0x040814, colour, 0.4)) end  -- in the water
        end
        if flags & CRACKLE ~= 0 and life < 0.25 and math.random() < 0.3 then gfx.fill(math.floor(x) - 1, math.floor(y) - 1, 3, 3, 0xffffff) end
        i = i + 1
      else
        SX[i], SY[i], SVX[i], SVY[i], SLIFE[i], SCF[i] = SX[nSparks], SY[nSparks], SVX[nSparks], SVY[nSparks], SLIFE[nSparks], SCF[nSparks]
        nSparks = nSparks - 1
      end
    end
    if now - shown < 1800 then gfx.text(4, 4, "space m w s a d q", 0xffffff, 1) end
    -- the sound: on or off (m), shown for a moment after it changes and as a small sign in the corner
    if now - (soundShown or 0) < 1500 then gfx.text(4, 14, sound and "sound on (m mutes)" or "sound off (m turns it on)", 0xffe060, 1) end
    if audio and audio.beep then
      gfx.fill(W - 12, 3, 3, 5, 0x8a94aa)
      gfx.triangle(W - 9, 5, W - 6, 2, W - 6, 9, 0x8a94aa)
      if not sound then gfx.line(W - 13, 2, W - 3, 10, 0xff5050) end
    end
    gfx.flush()
    sys.sleep(5)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("fireworks: " .. tostring(problem)) end
