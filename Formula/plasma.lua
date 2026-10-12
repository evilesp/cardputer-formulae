#!lua
-- plasma: the classic demoscene plasma, four moving sine waves coloured by a palette. space changes the palette (rainbow,
-- fire, ocean, neon, ice), w and s change the speed, q quits. Needs the graphics (firmware v0.1.0.13).
-- Run it with --selftest to check the palette.

local W, H = 240, 135
local CELL = 6
local COLS, ROWS = W // CELL, (H + CELL - 1) // CELL

-- colour from hue 0..1, saturation 0..1, value 0..1
local function hsv(h, s, v)
  h = (h % 1) * 6
  local i = math.floor(h)
  local f = h - i
  local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
  local r, g, b
  if i == 0 then r, g, b = v, t, p
  elseif i == 1 then r, g, b = q, v, p
  elseif i == 2 then r, g, b = p, v, t
  elseif i == 3 then r, g, b = p, q, v
  elseif i == 4 then r, g, b = t, p, v
  else r, g, b = v, p, q end
  return (math.floor(r * 255 + 0.5) << 16) | (math.floor(g * 255 + 0.5) << 8) | math.floor(b * 255 + 0.5)
end

-- the palettes: 128 colours each, made once; index 0..127 is the plasma value
local PALETTES = {
  { name = "rainbow", make = function(x) return hsv(x, 0.85, 1) end },
  { name = "fire", make = function(x)
      local r = math.min(1, x * 2.2)
      local g = math.max(0, math.min(1, (x - 0.35) * 2))
      local b = math.max(0, math.min(1, (x - 0.8) * 4))
      return (math.floor(r * 255) << 16) | (math.floor(g * 255) << 8) | math.floor(b * 255)
    end },
  { name = "ocean", make = function(x) return hsv(0.5 + 0.18 * math.sin(x * math.pi * 2), 0.8, 0.35 + 0.65 * x) end },
  { name = "neon", make = function(x) return hsv(0.75 + 0.25 * math.sin(x * math.pi * 4), 1, 0.4 + 0.6 * math.abs(math.sin(x * math.pi * 2))) end },
  { name = "ice", make = function(x) return hsv(0.55 + 0.1 * x, 0.6 - 0.5 * x * x, 0.3 + 0.7 * x) end },
}
local function buildPalette(p)
  local t = {}
  for i = 0, 127 do t[i] = p.make(i / 127) end
  return t
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(hsv(0, 1, 1) == 0xFF0000 and hsv(1 / 3, 1, 1) == 0x00FF00 and hsv(2 / 3, 1, 1) == 0x0000FF, "primary colours")
  check(hsv(0.5, 0, 1) == 0xFFFFFF and hsv(0.3, 1, 0) == 0, "white and black")
  for _, p in ipairs(PALETTES) do
    local t = buildPalette(p)
    local ok = true
    for i = 0, 127 do
      if type(t[i]) ~= "number" or t[i] < 0 or t[i] > 0xFFFFFF then ok = false end
    end
    check(ok, p.name .. " palette has valid colours")
  end
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("plasma needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end

-- the distance from the centre of each cell, made once (a square root per cell per frame would be slow)
local DIST = {}
for r = 0, ROWS - 1 do
  DIST[r] = {}
  for c = 0, COLS - 1 do
    local dx, dy = c - COLS / 2, r - ROWS / 2
    DIST[r][c] = math.sqrt(dx * dx + dy * dy)
  end
end

local w = gfx.open()
if not w then
  print("plasma: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local pal, pi = buildPalette(PALETTES[1]), 1
  local speed, t, shown = 1.0, 0, sys.millis()
  local last = sys.millis()
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " then
        pi = pi % #PALETTES + 1
        pal = buildPalette(PALETTES[pi])
        shown = sys.millis()
      elseif k == "w" or k == "up" then speed = math.min(4, speed + 0.25)
      elseif k == "s" or k == "down" then speed = math.max(0.25, speed - 0.25) end
      k = key.poll()
    end
    local now = sys.millis()
    t = t + (now - last) / 1000 * speed
    last = now
    local sin = math.sin
    for r = 0, ROWS - 1 do
      local y = r * 0.25
      local row = DIST[r]
      for c = 0, COLS - 1 do
        local v = sin(c * 0.3 + t) + sin(y + t * 1.3) + sin((c + r) * 0.2 + t * 0.7) + sin(row[c] * 0.35 - t * 1.1)
        gfx.fill(c * CELL, r * CELL, CELL, CELL, pal[math.floor((v + 4) / 8 * 127)])
      end
    end
    if now - shown < 1800 then gfx.text(4, 4, PALETTES[pi].name .. "  space w s q", 0xffffff, 1) end
    gfx.flush()
    sys.sleep(10)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("plasma: " .. tostring(problem)) end
