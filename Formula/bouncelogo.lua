#!lua
-- bouncelogo: the old DVD screensaver. A small CARDPUTER box flies across the screen and bounces off the edges,
-- changing colour at every bounce. Each time it hits two edges at once (a corner) the corner counter goes up.
-- w and s change the speed, space picks a new colour, c clears the counter, p pauses, q quits.
-- Needs the graphics (firmware v0.1.0.13). Run it with --selftest to check the bouncing.

local W, H = 240, 135
local LW, LH = 60, 18                   -- the size of the box
local BG = 0x04060c
local COLORS = { 0x30e060, 0xff4040, 0x4080ff, 0xffd040, 0xff40ff, 0x40e0e0, 0xffffff }
local SPEEDS = { 0.5, 0.8, 1.2, 1.7, 2.3, 3.0 }

-- move the box one step; it turns back at the edges. Returns whether it hit a vertical edge and a horizontal edge
local function move(b, w, h)
  b.x = b.x + b.vx
  b.y = b.y + b.vy
  local hitX, hitY = false, false
  if b.x < 0 then
    b.x, b.vx, hitX = -b.x, -b.vx, true
  elseif b.x > w - LW then
    b.x, b.vx, hitX = 2 * (w - LW) - b.x, -b.vx, true
  end
  if b.y < 0 then
    b.y, b.vy, hitY = -b.y, -b.vy, true
  elseif b.y > h - LH then
    b.y, b.vy, hitY = 2 * (h - LH) - b.y, -b.vy, true
  end
  return hitX, hitY
end

-- the speed is the length of the step, the direction keeps its sign
local function setSpeed(b, s)
  local sx = b.vx >= 0 and 1 or -1
  local sy = b.vy >= 0 and 1 or -1
  b.vx = sx * s
  b.vy = sy * s
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local b = { x = 10, y = 10, vx = 2, vy = 1 }
  local hx, hy = move(b, W, H)
  check(not hx and not hy and b.x == 12 and b.y == 11, "a free step moves the box")
  b = { x = W - LW - 1, y = 10, vx = 2, vy = 1 }
  hx, hy = move(b, W, H)
  check(hx and not hy and b.vx == -2 and b.x == W - LW - 1, "the right edge turns the box back")
  b = { x = 1, y = 1, vx = -2, vy = -2 }
  hx, hy = move(b, W, H)
  check(hx and hy and b.vx == 2 and b.vy == 2, "the top left corner turns both ways")
  b = { x = 0.5, y = 10, vx = -1, vy = 0 }
  move(b, W, H)
  check(b.x >= 0 and b.x <= 1, "the box never goes past the left edge")
  b = { x = W - LW, y = H - LH, vx = 1, vy = 1 }
  hx, hy = move(b, W, H)
  check(hx and hy, "the bottom right corner counts as a corner")
  setSpeed(b, 3)
  check(b.vx == -3 and b.vy == -3, "speed keeps the directions")
  local bad = false
  local c = { x = 30, y = 20, vx = 2.3, vy = -1.7 }
  for _ = 1, 2000 do
    move(c, W, H)
    if c.x < -1e-9 or c.x > W - LW + 1e-9 or c.y < -1e-9 or c.y > H - LH + 1e-9 then bad = true end
  end
  check(not bad, "the box stays on the screen for a long time")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("bouncelogo needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
if not gfx.open() then
  print("bouncelogo: cannot take the screen")
  return
end
local ok, problem = pcall(function()
  local b = { x = 20, y = 15, vx = SPEEDS[3], vy = SPEEDS[3], col = COLORS[1] }
  local speed, corners, colour = 3, 0, 1
  local paused, shown = false, sys.millis()

  while true do
    local k = key.poll()
    while k do
      if k == "q" or k == "ctrl-q" then return end
      shown = sys.millis()
      if k == "p" then paused = not paused
      elseif k == "w" or k == "up" then speed = math.min(#SPEEDS, speed + 1); setSpeed(b, SPEEDS[speed])
      elseif k == "s" or k == "down" then speed = math.max(1, speed - 1); setSpeed(b, SPEEDS[speed])
      elseif k == " " then colour = colour % #COLORS + 1; b.col = COLORS[colour]
      elseif k == "c" then corners = 0 end
      k = key.poll()
    end
    if not paused then
      local hitX, hitY = move(b, W, H)
      if hitX or hitY then
        colour = colour % #COLORS + 1
        b.col = COLORS[colour]
      end
      if hitX and hitY then corners = corners + 1 end
    end
    gfx.clear(BG)
    gfx.fill(math.floor(b.x), math.floor(b.y), LW, LH, b.col)
    gfx.text(math.floor(b.x) + 4, math.floor(b.y) + 5, "CARDPUTER", BG, 1)
    gfx.text(4, H - 10, "corners " .. corners, 0x808080, 1)
    if sys.millis() - shown < 1800 then
      gfx.text(4, 2, "space colour w s speed q quits", 0xffffff, 1)
    end
    gfx.flush()
    sys.sleep(20)
  end
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("bouncelogo: " .. tostring(problem)) end
