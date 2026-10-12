#!lua
-- parrotDancing: the party parrot, as "curl parrot.live" shows it in a Linux terminal: a parrot drawn with shaded
-- letters (. , : ; c l o d k) that circles its head to the beat, the whole bird in a new colour every step. The frames are
-- worked out here from simple shapes (no copied art). q quits.
-- usage: parrotDancing [-s SPEED]     SPEED 1 (slow) to 5 (fast), 3 when left out
-- Run it with --selftest to check the frames.

local STEPS = 10                      -- frames of one circle of the head
local RAMP = { ".", ",", ":", ";", "c", "l", "o", "d", "k" }  -- from the edge of a shape to its middle
local RAINBOW = { "red", "yellow", "green", "cyan", "blue", "magenta" }
local ASPECT = 0.62                   -- a letter is narrower than it is high: one column is this many rows wide

-- the distance from a point to an ellipse's edge, negative inside (good enough near the edge, which is what shades)
local function ellipse(px, py, cx, cy, rx, ry)
  local dx, dy = (px - cx) / rx, (py - cy) / ry
  return (math.sqrt(dx * dx + dy * dy) - 1) * math.min(rx, ry)
end

-- the parrot standing, feet at y = 0 and the head up (negative y): the distance to its outline, and which part is there.
-- Parts: "body" shaded with the ramp, "wing" one shade lighter, "beak", "eye".
local function parrotAt(x, y)
  local body = ellipse(x, y, 0, -5.2, 5.4, 5.0)
  local head = ellipse(x, y, 1.6, -10.4, 3.6, 3.4)
  local tail = ellipse(x, y, -4.8, -1.4, 3.2, 1.3)
  local d = math.min(body, head, tail)
  local beak = ellipse(x, y, 5.3, -9.9, 1.7, 1.1)
  if beak < 0 then return beak, "beak" end
  if ellipse(x, y, 2.9, -11.0, 0.65, 0.65) < 0 then return -1, "eye" end
  if d >= 0.4 then return d, nil end
  local wing = ellipse(x, y, -1.2, -5.6, 3.4, 2.8)
  if wing < -0.3 then return d, "wing", -wing end
  return d, "body"
end

-- the feet: two short legs under the body, each a column of "||"
local function footAt(x, y)
  return y > -0.6 and y <= 0.4 and ((x > -1.9 and x < -0.9) or (x > 1.0 and x < 2.0))
end

-- one frame as rows of text, cols x rows. The head goes round a circle: the higher a point, the more it moves (the feet
-- stay on the ground), and the bird leans with the beat.
local function makeFrame(step, cols, rows)
  local angle = step / STEPS * 2 * math.pi
  local swayX, swayY = math.cos(angle) * 3.4, math.sin(angle) * 1.3
  local scale = (rows - 1) / 14.5  -- the bird is 14.5 rows from the feet to the top of the head
  local midCol = cols / 2
  local lines = {}
  for r = 0, rows - 1 do
    local out = {}
    for c = 0, cols - 1 do
      local y = (r - (rows - 1)) / scale             -- 0 at the bottom row, negative up
      local h = math.min(1, math.max(0, -y / 14))    -- 0 at the feet, 1 at the head
      local x = (c - midCol) * ASPECT / scale - swayX * h
      y = y - swayY * h * h
      local ch = " "
      if r == rows - 1 then ch = "." end            -- the ground
      local d, part, wingDepth = parrotAt(x, y)
      if part == "eye" then
        ch = "0"
      elseif part == "beak" then
        ch = d < -0.5 and "x" or ";"
      elseif part then
        local depth = -d
        local i = math.floor(depth / 0.2) + 2
        if part == "wing" then i = math.floor(wingDepth * 2.5) % 2 == 0 and 6 or 4 end  -- rows of feathers
        if i < 1 then i = 1 elseif i > #RAMP then i = #RAMP end
        ch = RAMP[i]
      elseif d < 0.4 then
        ch = "."                                     -- the soft fringe round the bird
      elseif footAt(x, y) then
        ch = "|"
      end
      out[#out + 1] = ch
    end
    lines[#lines + 1] = table.concat(out)
  end
  return lines
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local a, b = makeFrame(0, 40, 15), makeFrame(5, 40, 15)
  check(#a == 15 and #a[1] == 40 and #a[15] == 40, "a frame fills 40 x 15")
  check(table.concat(a, "\n") ~= table.concat(b, "\n"), "the frames move")
  local text = table.concat(a)
  check(text:find("k", 1, true) and text:find("0", 1, true) and text:find("x", 1, true), "body, eye and beak are drawn")
  local _, part = parrotAt(0, -5)
  check(part ~= nil, "the middle of the body is the parrot")
  check(select(2, parrotAt(20, -20)) == nil, "far away is empty")
  if failed == 0 then print("selftest ok") end
  return
end

local speed = 3
if arg[1] == "-s" and tonumber(arg[2] or "") then
  speed = math.max(1, math.min(5, math.floor(tonumber(arg[2]))))
elseif arg[1] then
  print("usage: parrotDancing [-s SPEED]   (1 slow to 5 fast)")
  return
end
local STEP_MS = ({ 140, 105, 80, 60, 45 })[speed]

local COLS, ROWS = term.size()
local H = ROWS - 1  -- the last row says how to quit
-- every frame is worked out once: drawing is then only text
local frames = {}
for s = 0, STEPS - 1 do frames[s + 1] = makeFrame(s, COLS, H) end

term.fullscreen(true)
local step, quit = 0, false
while not quit do
  local k = key.poll()
  while k do
    if k == "q" or k == "ctrl-q" then quit = true end
    k = key.poll()
  end
  if quit then break end
  term.clear()
  local colour = RAINBOW[step % #RAINBOW + 1]
  for r, line in ipairs(frames[step % STEPS + 1]) do term.text(0, r - 1, line, colour) end
  term.text(0, ROWS - 1, "parrotDancing   q quit", "dim")
  term.flush()
  step = step + 1
  sys.sleep(STEP_MS)
end
term.fullscreen(false)
