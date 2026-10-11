#!lua
-- screensaver: three pictures for a screen that is left on: stars (1), rain (2) and a lava lamp (3). Keys 1, 2 and 3
-- switch between them, ctrl-q quits. Needs the graphics and the ui package. Run it with --selftest to check the code.

local function starsStep(stars, dt, w, h)
  for _, s in ipairs(stars) do
    s.z = s.z - dt * 0.6
    if s.z <= 0.02 then
      s.x, s.y, s.z = math.random() * 2 - 1, math.random() * 2 - 1, 1
    end
  end
end

-- where a star is on the screen, from its position in front of the viewer (x, y in -1..1, z the depth)
local function starScreen(s, w, h)
  local px = w / 2 + s.x / s.z * (w / 2)
  local py = h / 2 + s.y / s.z * (h / 2)
  return px, py
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local px, py = starScreen({ x = 0, y = 0, z = 1 }, 240, 135)
  check(px == 120 and py == 67.5, "a star straight ahead is in the middle")
  px, py = starScreen({ x = 1, y = 0, z = 1 }, 240, 135)
  check(px == 240, "a star at the right edge is at the right edge")
  px = starScreen({ x = 0.25, y = 0, z = 0.5 }, 240, 135)
  check(px == 180, "a star near the viewer is farther from the middle")
  local stars = { { x = 0, y = 0, z = 0.01 } }
  starsStep(stars, 0.1, 240, 135)
  check(stars[1].z == 1, "a star that has passed the viewer starts again")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("screensaver needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not driver then
  print("screensaver: this firmware has no driver module")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("screensaver: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local stars, drops, blobs = {}, {}, {}
for i = 1, 90 do stars[i] = { x = math.random() * 2 - 1, y = math.random() * 2 - 1, z = math.random() } end
for i = 1, 60 do drops[i] = { x = math.random(W), y = math.random(H), v = 60 + math.random(90) } end
for i = 1, 5 do blobs[i] = { x = math.random(W), y = math.random(H), r = 10 + math.random(10), vx = math.random() * 20 - 10, vy = -10 - math.random(20) } end

local mode = 1
local t = 0

local function draw(dt)
  t = t + dt
  gfx.clear(0x05060a)
  if mode == 1 then
    starsStep(stars, dt, W, H)
    for _, s in ipairs(stars) do
      local x, y = starScreen(s, W, H)
      local b = math.floor(255 * (1 - s.z))
      gfx.pixel(math.floor(x), math.floor(y), (b << 16) | (b << 8) | 255)
    end
  elseif mode == 2 then
    for _, d in ipairs(drops) do
      d.y = d.y + d.v * dt
      if d.y > H then d.y, d.x = 0, math.random(W) end
      gfx.line(d.x, math.floor(d.y), d.x - 2, math.floor(d.y) - 6, 0x4a7ac8)
    end
  else
    for _, b in ipairs(blobs) do
      b.x = b.x + b.vx * dt
      b.y = b.y + b.vy * dt
      if b.y < -b.r then b.y = H + b.r end
      if b.x < -b.r then b.x = W + b.r elseif b.x > W + b.r then b.x = -b.r end
      gfx.circle(math.floor(b.x), math.floor(b.y), b.r, 0xd03030, true)
      gfx.circle(math.floor(b.x), math.floor(b.y), math.floor(b.r * 0.6), 0xff7040, true)
    end
  end
  gfx.flush()
end

local function handle(k)
  if k == "ctrl-q" then return false end
  if k == "1" or k == "2" or k == "3" then mode = tonumber(k) end
  return true
end

local w, h = ui.open()
if not w then
  print("screensaver: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local last = sys.millis()
  while true do
    local now = sys.millis()
    local dt = math.min((now - last) / 1000, 0.1)
    last = now
    local k = key.poll()
    while k do
      if not handle(k) then return end
      k = key.poll()
    end
    draw(dt)
    sys.sleep(25)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("screensaver: " .. tostring(problem)) end
