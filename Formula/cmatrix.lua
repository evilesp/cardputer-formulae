#!lua
-- cmatrix: the falling green characters of cmatrix 2.0. White head, trail fading from bright to dark green (true colour), characters from ! to ~ as in the
-- original. q quits (in -s mode any key does). While it runs: 0-9 change the speed, a toggles async, ! @ # $ % ^ & pick a colour.
local USAGE = [[
Usage: cmatrix -[abBcfhlsVx] [-u delay] [-C color]
 -a: Asynchronous scroll
 -b: Bold characters on
 -B: All bold characters (overrides -b)
 -c: Use Japanese characters as seen in the original matrix. Requires appropriate fonts
 -f: Force the linux $TERM type to be on
 -l: Linux mode (uses matrix.fnt)
 -L: Lock mode (can be closed from another terminal)
 -o: Use old-style scrolling
 -h: Print usage and exit
 -n: No bold characters (overrides -b, default)
 -s: "Screensaver" mode, exits on first keystroke
 -x: X window mode, use if your xterm is using mtx.pcf
 -V: Print version information and exit
 -u delay (0 - 10, default 4): Screen update delay
 -C [color]: Use this color for matrix (default green)
 -r: rainbow mode
 -m: lambda mode
 -k: Characters change while scrolling. (Works without -o opt.)
 -t [tty]: Set tty to use]]

local COLORS = { green = "green", red = "red", blue = "blue", white = "white", yellow = "yellow", cyan = "cyan",
  magenta = "magenta", black = "dim" }
local RAINBOW = { "red", "yellow", "green", "cyan", "blue", "magenta" }
local KEYCOLOR = { ["!"] = "red", ["@"] = "green", ["#"] = "yellow", ["$"] = "blue", ["%"] = "magenta",
  ["^"] = "cyan", ["&"] = "white" }

local o = { color = "green", delay = 4 }
local i = 1
while arg[i] do
  local a = arg[i]
  if a:sub(1, 1) ~= "-" or a == "-" then break end
  local j = 2
  while j <= #a do
    local f = a:sub(j, j)
    if f == "h" or f == "?" then print(USAGE) return end
    if f == "V" then
      print("cmatrix version 2.0 (compiled 00:00:00, Jan  1 2026)")
      print("Email: abb@gmail.com")
      print("Web: http://www.asty.org/cmatrix")
      return
    end
    if f == "u" or f == "C" or f == "t" then  -- these take a value: "-u5" or "-u 5"
      local v = a:sub(j + 1)
      if v == "" then i = i + 1; v = arg[i] end
      if f == "u" then o.delay = tonumber(v) or 4 end
      if f == "C" then
        if not COLORS[v or ""] then
          print("Invalid color selection\nValid colors are green, red, blue, white, yellow, cyan, magenta and black.")
          if os and os.exit then os.exit(1) end
          return
        end
        o.color = COLORS[v]
      end
      break
    elseif f:find("[abBcfLlmnorsxk]") then
      o[f] = true
    else
      print("cmatrix: invalid option -- '" .. f .. "'")
      print(USAGE)
      if os and os.exit then os.exit(1) end
      return
    end
    j = j + 1
  end
  i = i + 1
end
if o.delay < 0 or o.delay > 10 then
  print(" Invalid update value\n")
  print(USAGE)
  if os and os.exit then os.exit(1) end
  return
end

-- the trail goes from bright to dark: LEVELS shades of each colour, made with term.rgb (true colour, nearest palette entry)
local BASE = { green = {0, 255, 70}, red = {255, 40, 40}, blue = {60, 100, 255}, white = {255, 255, 255},
  yellow = {255, 235, 0}, cyan = {0, 240, 255}, magenta = {255, 0, 220}, dim = {150, 150, 150} }
local RAMPS = {}
local LEVELS = 8
for name, c in pairs(BASE) do
  RAMPS[name] = {}
  for l = 0, LEVELS - 1 do
    local f = 1 - 0.85 * l / (LEVELS - 1)  -- 1 near the head, 0.15 at the tail
    RAMPS[name][l] = term.rgb(math.floor(c[1] * f), math.floor(c[2] * f), math.floor(c[3] * f))
  end
end

local COLS, ROWS = term.size()
local async = o.a or false
local delay = o.delay

-- original: rand() % 93 + 33, that is the characters ! to ~ (-c would give katakana, which this screen cannot show)
local function rc() return string.char(math.random(33, 126)) end

local cols = {}
for x = 0, COLS - 1 do
  cols[x] = { head = -math.random(0, ROWS), len = math.random(3, ROWS - 1), speed = 1, tick = 0, cells = {},
    col = RAINBOW[math.random(#RAINBOW)] }
end

local function restart(c)
  c.head = -math.random(0, ROWS // 2)
  c.len = math.random(3, ROWS - 1)
  c.speed = async and math.random(1, 3) or 1
  c.col = RAINBOW[math.random(#RAINBOW)]
  c.cells = {}
end

local function step(c)
  c.tick = c.tick + 1
  if c.tick < c.speed then return end
  c.tick = 0
  c.head = c.head + 1
  if c.head >= 0 and c.head < ROWS then c.cells[c.head] = rc() end
  c.cells[c.head - c.len] = nil
  if c.head - c.len >= ROWS then restart(c) end
end

term.fullscreen(true)
term.clear()
local quit = false
while not quit do
  local k = key.poll()
  while k do
    if o.s or k == "q" then quit = true
    elseif k:find("^%d$") then delay = tonumber(k)
    elseif k == "a" then async = not async
    elseif KEYCOLOR[k] then o.color = KEYCOLOR[k]; o.r = false end
    k = key.poll()
  end
  if quit then break end

  term.clear()
  for x = 0, COLS - 1 do
    local c = cols[x]
    step(c)
    local base = o.r and c.col or o.color
    for y, ch in pairs(c.cells) do
      if y >= 0 and y < ROWS then
        if o.k then ch = rc(); c.cells[y] = ch end
        local color
        if y == c.head then color = term.rgb(255, 255, 255)
        else
          local l = math.min(LEVELS - 1, (c.head - y) * LEVELS // math.max(c.len, 1))
          color = RAMPS[base][l]
        end
        term.put(x, y, ch, color)
      end
    end
  end
  term.flush()
  sys.sleep(math.max(delay * 10, 1))
end
term.fullscreen(false)
