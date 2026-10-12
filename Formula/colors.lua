#!lua
-- colors: a colour picker for your own screens and LEDs. Three sliders (red, green, blue, or hue, saturation, value) change a
-- swatch; the text shows the colour as #RRGGBB, as 0xRRGGBB for gfx, as RGB565 (the 16-bit colour of the display) and as RGB and HSV
-- numbers, with the complementary colour and five shades. w and s choose a slider, a and d change it by 1, z and x by 16,
-- m switches between RGB and HSV, v types a colour (#FF8800, 0xFF8800, 255,136,0), r picks a random one, ctrl-q quits.
-- Needs the graphics and the ui package. Run it with --selftest to check the conversions.

local function hsvToRgb(h, s, v)  -- h 0..360, s and v 0..100
  s, v = s / 100, v / 100
  h = (h % 360) / 60
  local i = math.floor(h)
  local f = h - i
  local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
  local r, g, b
  if i == 0 then r, g, b = v, t, p elseif i == 1 then r, g, b = q, v, p elseif i == 2 then r, g, b = p, v, t
  elseif i == 3 then r, g, b = p, q, v elseif i == 4 then r, g, b = t, p, v else r, g, b = v, p, q end
  return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
end

local function rgbToHsv(r, g, b)
  r, g, b = r / 255, g / 255, b / 255
  local mx, mn = math.max(r, g, b), math.min(r, g, b)
  local d = mx - mn
  local h = 0
  if d > 0 then
    if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
    h = h * 60
  end
  return math.floor(h + 0.5) % 360, math.floor((mx == 0 and 0 or d / mx) * 100 + 0.5), math.floor(mx * 100 + 0.5)
end

-- the 16-bit colour of the display: 5 bits red, 6 green, 5 blue
local function rgb565(r, g, b)
  return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
end

-- a colour from text: #RRGGBB, 0xRRGGBB, RRGGBB (6 hex digits), #RGB, or r,g,b; nil when it is not one
local function parseColour(text)
  local s = text:gsub("%s+", "")
  local r, g, b = s:match("^(%d+),(%d+),(%d+)$")
  if r then
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if r > 255 or g > 255 or b > 255 then return nil end
    return r, g, b
  end
  local hex = s:match("^#(%x+)$") or s:match("^0[xX](%x+)$") or (s:match("^%x%x%x%x%x%x$") and s)
  if hex and #hex == 6 then
    local v = tonumber(hex, 16)
    return (v >> 16) & 255, (v >> 8) & 255, v & 255
  end
  if hex and #hex == 3 and s:sub(1, 1) == "#" then
    return tonumber(hex:sub(1, 1), 16) * 17, tonumber(hex:sub(2, 2), 16) * 17, tonumber(hex:sub(3, 3), 16) * 17
  end
  return nil
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local r, g, b = hsvToRgb(0, 100, 100)
  check(r == 255 and g == 0 and b == 0, "red")
  r, g, b = hsvToRgb(120, 100, 100)
  check(r == 0 and g == 255 and b == 0, "green")
  r, g, b = hsvToRgb(240, 50, 100)
  check(r == 128 and g == 128 and b == 255, "a light blue")
  local h, s, v = rgbToHsv(255, 136, 0)
  check(h == 32 and s == 100 and v == 100, "orange to HSV (" .. h .. "," .. s .. "," .. v .. ")")
  for _, c in ipairs({ { 12, 200, 99 }, { 255, 255, 255 }, { 0, 0, 0 }, { 80, 80, 200 } }) do
    local hh, ss, vv = rgbToHsv(c[1], c[2], c[3])
    local r2, g2, b2 = hsvToRgb(hh, ss, vv)
    check(math.abs(r2 - c[1]) <= 3 and math.abs(g2 - c[2]) <= 3 and math.abs(b2 - c[3]) <= 3, "HSV round trip of " .. c[1] .. "," .. c[2] .. "," .. c[3])
  end
  check(rgb565(255, 255, 255) == 0xFFFF and rgb565(255, 0, 0) == 0xF800 and rgb565(0, 255, 0) == 0x07E0 and rgb565(0, 0, 255) == 0x001F, "RGB565")
  r, g, b = parseColour("#FF8800")
  check(r == 255 and g == 136 and b == 0, "#RRGGBB")
  r, g, b = parseColour("0x00ff10")
  check(r == 0 and g == 255 and b == 16, "0xRRGGBB")
  r, g, b = parseColour("#fa0")
  check(r == 255 and g == 170 and b == 0, "#RGB")
  r, g, b = parseColour("10, 20, 30")
  check(r == 10 and g == 20 and b == 30, "r,g,b")
  check(parseColour("256,0,0") == nil and parseColour("#12") == nil and parseColour("blue") == nil, "bad colours")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("colors needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("colors: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local r, g, b = 255, 136, 0
local hsvMode, sel = false, 1

local function packed(rr, gg, bb) return (rr << 16) | (gg << 8) | bb end

local function draw()
  gfx.clear(0x0a0e18)
  local h, s, v = rgbToHsv(r, g, b)
  local values = hsvMode and { h, s, v } or { r, g, b }
  local maxes = hsvMode and { 360, 100, 100 } or { 255, 255, 255 }
  local names = hsvMode and { "H", "S", "V" } or { "R", "G", "B" }
  local bar = hsvMode and { 0x8a94aa, 0x8a94aa, 0x8a94aa } or { 0xe05050, 0x50d070, 0x5080e0 }
  ui.label(4, 3, "COLOR PICKER  " .. (hsvMode and "HSV" or "RGB"), 0xe8ecf4)
  gfx.fill(150, 14, 86, 44, packed(r, g, b))
  gfx.rect(149, 13, 88, 46, 0x8a94aa)
  for i = 1, 3 do
    local y = 16 + (i - 1) * 14
    ui.label(4, y + 1, names[i], i == sel and 0xffe060 or 0x8a94aa)
    gfx.fill(16, y, 100, 9, 0x1c2233)
    gfx.fill(16, y, math.floor(values[i] / maxes[i] * 100), 9, bar[i])
    if i == sel then gfx.rect(15, y - 1, 102, 11, 0xffe060) end
    ui.label(122, y + 1, tostring(values[i]), 0xe8ecf4)
  end
  ui.label(4, 62, string.format("#%02X%02X%02X", r, g, b), 0x60e090, 2)
  ui.label(4, 82, string.format("gfx 0x%02X%02X%02X   565 0x%04X", r, g, b, rgb565(r, g, b)), 0xe8ecf4)
  ui.label(4, 93, string.format("rgb %d,%d,%d   hsv %d,%d,%d", r, g, b, h, s, v), 0x8a94aa)
  -- the complementary colour and five shades from dark to light
  local cr, cg, cb = hsvToRgb((h + 180) % 360, s, v)
  ui.label(4, 106, "opposite", 0x8a94aa)
  gfx.fill(50, 105, 14, 9, packed(cr, cg, cb))
  for i = 0, 4 do
    local f = 0.35 + i * 0.2
    local sr, sg, sb = math.min(255, math.floor(r * f)), math.min(255, math.floor(g * f)), math.min(255, math.floor(b * f))
    gfx.fill(76 + i * 16, 105, 14, 9, packed(sr, sg, sb))
  end
  ui.label(4, H - 10, "w s a d z x  m mode  v type  r random", 0x8a94aa)
  gfx.flush()
end

local function change(delta)
  if hsvMode then
    local h, s, v = rgbToHsv(r, g, b)
    if sel == 1 then h = (h + delta) % 360 elseif sel == 2 then s = math.max(0, math.min(100, s + delta)) else v = math.max(0, math.min(100, v + delta)) end
    r, g, b = hsvToRgb(h, s, v)
  else
    local c = { r, g, b }
    c[sel] = math.max(0, math.min(255, c[sel] + delta))
    r, g, b = c[1], c[2], c[3]
  end
end

local w, h = ui.open()
if not w then
  print("colors: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if #k == 1 then k = k:lower() end
      if k == "w" or k == "up" then sel = sel > 1 and sel - 1 or 3
      elseif k == "s" or k == "down" then sel = sel < 3 and sel + 1 or 1
      elseif k == "a" or k == "left" then change(-1)
      elseif k == "d" or k == "right" then change(1)
      elseif k == "z" then change(hsvMode and sel == 1 and -15 or -16)
      elseif k == "x" then change(hsvMode and sel == 1 and 15 or 16)
      elseif k == "m" then hsvMode = not hsvMode
      elseif k == "r" then r, g, b = math.random(0, 255), math.random(0, 255), math.random(0, 255)
      elseif k == "v" then
        local text = ui.prompt("colour (#FF8800, 255,136,0)", "", 16)
        if text then
          local nr, ng, nb = parseColour(text)
          if nr then r, g, b = nr, ng, nb else ui.message("Not a colour", { "try #FF8800, 0xFF8800, 255,136,0" }) end
        end
      end
      k = key.poll()
    end
    sys.sleep(30)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("colors: " .. tostring(problem)) end
