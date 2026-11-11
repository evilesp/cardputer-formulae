#!lua
-- pipes: pipes.sh, the animated pipes screensaver (pipeseroni). Pipes crawl from the middle, going straight or turning,
-- and the screen is cleared after LIMIT characters. The screen shows one byte per cell, so the box-drawing types
-- 0 1 2 3 8 9 (default 0) are drawn with the ASCII type 4 instead. q quits, space clears, p pauses.
local VERSION = "1.3.0"
local USAGE = [[
Usage: pipes.sh [OPTION]...
Animated pipes terminal screensaver.

 -p [1-]                number of pipes (D=1).
 -t [0-9]               type of pipes, can be used more than once (D=0).
 -t c[16 chars]         custom type of pipes.
 -c [0-7]               color of pipes, can be used more than once (D=1 2 3 4 5 6 7 0).
 -C                     no color.
 -f [20-100]            framerate (D=75).
 -s [5-15]              probability of a straight fitting (D=13).
 -r LIMIT               reset after x characters (D=2000).
 -R                     random starting point.
 -B                     no bold.
 -K                     turn at the edge instead of wrapping.
 -h                     help (this screen).
 -v                     print version number.]]

-- the 16 characters of a type: index 4 * (direction before) + (direction after) + 1; directions 0 up, 1 right, 2 down, 3 left
local SETS = { [4] = "|+ ++-+  +|++ +-", [5] = "|/ \\/-\\  \\|/\\ /-", [6] = ".o oo.o  o.oo o.", [7] = "-\\ /\\|/  /-\\/ \\|" }
local PALETTE = { [0] = "dim", "red", "green", "yellow", "blue", "magenta", "cyan", "white" }

local function fail(msg)
  if msg then print(msg) end
  print(USAGE)
  if os and os.exit then os.exit(1) end
end

-- a pipe turns left or right by this much; returns the new direction
local function turn(d, r) return (d + (r == 0 and 1 or 3)) % 4 end

local o = { p = 1, f = 75, s = 13, r = 2000, types = {}, colors = {}, R = false, K = false, C = false }
local function parse(args)
  local i = 1
  while args[i] do
    local a = args[i]
    if a:sub(1, 1) ~= "-" or #a < 2 then return fail("pipes.sh: illegal option -- " .. a) end
    local j = 2
    while j <= #a do
      local f = a:sub(j, j)
      if f == "h" then print(USAGE) return false end
      if f == "v" then print(VERSION) return false end
      if f == "C" or f == "R" or f == "K" or f == "B" then
        o[f] = true
      elseif f:find("[ptcfsr]") then
        local v = a:sub(j + 1)
        if v == "" then i = i + 1; v = args[i] end
        if not v then return fail("pipes.sh: option requires an argument -- " .. f) end
        if f == "t" then
          if v:sub(1, 1) == "c" and #v == 17 then o.types[#o.types + 1] = v:sub(2)
          elseif v:match("^%d$") then o.types[#o.types + 1] = SETS[tonumber(v)] or SETS[4]
          else return fail() end
        elseif f == "c" then
          local n = tonumber(v)
          if not n or n < 0 or n > 7 then return fail() end
          o.colors[#o.colors + 1] = PALETTE[n // 1]
        else
          local n = tonumber(v)
          if not n then return fail() end
          o[f] = n // 1
        end
        break
      else
        return fail("pipes.sh: illegal option -- " .. f)
      end
      j = j + 1
    end
    i = i + 1
  end
  if o.p < 1 or o.f < 20 or o.f > 100 or o.s < 5 or o.s > 15 or o.r < 0 then return fail() end
  if #o.types == 0 then o.types[1] = SETS[4] end
  if #o.colors == 0 then for k = 1, 8 do o.colors[k] = PALETTE[k % 8] end end
  return true
end

if arg[1] == "--selftest" then
  local bad = 0
  for k, set in pairs(SETS) do
    if #set ~= 16 then bad = bad + 1 end
    for d = 0, 3 do if set:sub(d * 5 + 1, d * 5 + 1) == " " then bad = bad + 1 end end  -- straight fittings exist
  end
  if turn(0, 0) ~= 1 or turn(0, 1) ~= 3 or turn(3, 0) ~= 0 then bad = bad + 1 end
  print(bad == 0 and "selftest ok" or "selftest failed")
  return
end
if not parse(arg) then return end

local COLS, ROWS = term.size()
local DX = { [0] = 0, 1, 0, -1 }
local DY = { [0] = -1, 0, 1, 0 }

local function newPipe()
  local p = { d = math.random(0, 3), set = o.types[math.random(#o.types)],
    color = o.C and "white" or o.colors[math.random(#o.colors)] }
  if o.R then p.x, p.y = math.random(0, COLS - 1), math.random(0, ROWS - 1)
  else p.x, p.y = COLS // 2, ROWS // 2 end
  return p
end

local pipes = {}
for i = 1, o.p do pipes[i] = newPipe() end
local count = 0

local function step(p)
  local last = p.d
  local nd = last
  if math.random(0, 14) >= o.s then nd = turn(last, math.random(0, 1)) end
  local nx, ny = p.x + DX[nd], p.y + DY[nd]
  if o.K and (nx < 0 or nx >= COLS or ny < 0 or ny >= ROWS) then  -- at the edge: turn away instead of wrapping
    nd = turn(last, math.random(0, 1))
    nx, ny = p.x + DX[nd], p.y + DY[nd]
    if nx < 0 or nx >= COLS or ny < 0 or ny >= ROWS then nd = (nd + 2) % 4; nx, ny = p.x + DX[nd], p.y + DY[nd] end
  end
  p.x, p.y, p.d = (nx + COLS) % COLS, (ny + ROWS) % ROWS, nd
  local ch = p.set:sub(last * 4 + nd + 1, last * 4 + nd + 1)
  if ch == " " then ch = p.set:sub(1, 1) end  -- a U-turn has no fitting: never happens, kept for custom sets
  term.put(p.x, p.y, ch, p.color)
  count = count + 1
end

term.fullscreen(true)
term.clear()
local quit, pause = false, false
local delay = math.max(1, 1000 // o.f)
while not quit do
  local k = key.poll()
  while k do
    if k == "q" or k == "ctrl-c" then quit = true
    elseif k == "p" then pause = not pause
    elseif k == " " then term.clear() end
    k = key.poll()
  end
  if quit then break end
  if not pause then
    for _, p in ipairs(pipes) do step(p) end
    if o.r > 0 and count >= o.r then
      term.clear()
      count = 0
      for i = 1, o.p do pipes[i] = newPipe() end
    end
    term.flush()
  end
  sys.sleep(delay)
end
term.fullscreen(false)
