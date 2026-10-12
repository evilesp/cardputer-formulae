#!lua
-- fire: the doom fire effect, a bed of embers with flames that rise, flicker and die. space changes the colour of the fire
-- (red, blue, green, purple), w and s make it hotter or colder, a and d blow the wind, q quits. Needs the graphics.
-- Run it with --selftest to check the palette and the spreading.

local W, H = 240, 135
local CELL = 5
local COLS, ROWS = W // CELL, H // CELL
local LEVELS = 40  -- heat 0 (black) to 39 (white)

local function mix(a, b, t)
  local function ch(sh) return math.floor(((a >> sh) & 255) + (((b >> sh) & 255) - ((a >> sh) & 255)) * t + 0.5) end
  return (ch(16) << 16) | (ch(8) << 8) | ch(0)
end

-- the palettes: black, the main colour, a bright colour, white
local STOPS = {
  { name = "red", 0x000000, 0xc01800, 0xffb020, 0xffffff },
  { name = "blue", 0x000000, 0x0830c0, 0x40c0ff, 0xffffff },
  { name = "green", 0x000000, 0x108020, 0x70ff40, 0xffffff },
  { name = "purple", 0x000000, 0x6010a0, 0xff40e0, 0xffffff },
}
local function palette(stops)
  local p = {}
  for i = 0, LEVELS - 1 do
    local x = i / (LEVELS - 1) * 3
    local seg = math.min(2, math.floor(x))
    p[i] = mix(stops[seg + 1], stops[seg + 2], x - seg)
  end
  return p
end

-- one step of the fire: every cell takes the heat of the cell under it, a little less, and a little to the side (the
-- wind). The cells are in a flat list, row by row from the top.
local function step(heat, cols, rows, decay, wind)
  for r = 1, rows - 1 do
    for c = 1, cols do
      local below = heat[r * cols + c]
      if below > 0 then
        local drift = math.random(0, 2) - 1 + wind
        local to = c + drift
        if to < 1 then to = 1 elseif to > cols then to = cols end
        local v = below - math.random(0, decay)
        heat[(r - 1) * cols + to] = v > 0 and v or 0
      else
        heat[(r - 1) * cols + c] = 0
      end
    end
  end
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(mix(0, 0xffffff, 0.5) == 0x808080 and mix(0xff0000, 0xff0000, 0.3) == 0xff0000, "colour mixing")
  local p = palette(STOPS[1])
  check(p[0] == 0 and p[LEVELS - 1] == 0xffffff, "the palette runs from black to white")
  local cols, rows = 5, 4
  local heat = {}
  for i = 1, cols * rows do heat[i] = 0 end
  for c = 1, cols do heat[(rows - 1) * cols + c] = LEVELS - 1 end
  for _ = 1, 3 do step(heat, cols, rows, 3, 0) end
  local top = 0
  for c = 1, cols do top = top + heat[c] end
  check(top > 0, "the heat climbs from the bottom row")
  for c = 1, cols do heat[(rows - 1) * cols + c] = 0 end
  for _ = 1, 40 do step(heat, cols, rows, 3, 0) end
  local total = 0
  for i = 1, cols * rows do total = total + heat[i] end
  check(total == 0, "the fire dies without fuel")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("fire needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("fire: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local heat = {}
  for i = 1, COLS * ROWS do heat[i] = 0 end
  local si, pal = 1, palette(STOPS[1])
  local decay, wind, fuel, shown = 5, 0, LEVELS - 1, sys.millis()
  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      if k == " " then
        si = si % #STOPS + 1
        pal = palette(STOPS[si])
        shown = sys.millis()
      elseif k == "w" or k == "up" then decay = math.max(1, decay - 1)
      elseif k == "s" or k == "down" then decay = math.min(8, decay + 1)
      elseif k == "a" or k == "left" then wind = math.max(-1, wind - 1)
      elseif k == "d" or k == "right" then wind = math.min(1, wind + 1) end
      k = key.poll()
    end
    for c = 1, COLS do heat[(ROWS - 1) * COLS + c] = fuel - math.random(0, 3) end
    step(heat, COLS, ROWS, decay, wind)
    gfx.clear(0)
    for r = 0, ROWS - 1 do
      for c = 1, COLS do
        local v = heat[r * COLS + c]
        if v > 0 then gfx.fill((c - 1) * CELL, r * CELL, CELL, CELL, pal[v]) end
      end
    end
    if sys.millis() - shown < 1800 then gfx.text(4, 4, STOPS[si].name .. "  space w s a d q", 0xffffff, 1) end
    gfx.flush()
    sys.sleep(10)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("fire: " .. tostring(problem)) end
