#!lua
-- hanoi: the Tower of Hanoi. Move the whole tower of disks from the left peg to the right peg, one disk at a time,
-- never a bigger disk on a smaller one. a, s and d are the left, middle and right peg: press the peg to take the
-- top disk from, then the peg to put it on (the same peg again puts it back). 3, 4, 5 and 6 choose the number of
-- disks and start again, r starts again, z shows the computer solve it in the fewest moves. The moves and the best
-- score for each number of disks are kept (only the numbers). ctrl-q quits.
-- Needs the graphics and the ui package. Run it with --selftest to check the rules and the solver.

local DEFAULT_DISKS = 4
local DEMO_DELAY = 400 -- milliseconds between the moves of the computer
local PEG_KEYS = { a = 1, s = 2, d = 3 }
local PEG_X = { 60, 120, 180 } -- the middle of each peg on the screen
local BASE = 96 -- the line the pegs stand on
local PEG_TOP = 30
local DISK_H = 9
local DISK_COLORS = { 0xe84b4b, 0xf0a040, 0xf0e050, 0x50d070, 0x50a8f0, 0xb070f0 } -- by size, 1 is the smallest

-- the top disk of a peg, or a huge number when the peg is empty (an empty peg takes any disk)
local function topOf(stack)
  return stack[#stack] or math.huge
end

-- true when the top disk of peg from may go onto peg to
local function legal(pegs, from, to)
  local disk = topOf(pegs[from])
  return disk ~= math.huge and disk < topOf(pegs[to])
end

-- move the top disk of peg from onto peg to (the caller has checked it is legal)
local function move(pegs, from, to)
  pegs[to][#pegs[to] + 1] = table.remove(pegs[from])
end

-- the peg that holds the smallest disk, which is always on top of its peg
local function smallestPeg(pegs)
  for p = 1, 3 do
    if topOf(pegs[p]) == 1 then return p end
  end
  return nil
end

-- the peg the smallest disk goes to next: round the pegs one way for an even number of disks, the other way for odd
local function nextPeg(p, disks)
  if disks % 2 == 0 then return p % 3 + 1 end
  return (p + 1) % 3 + 1
end

-- move number step (from 1) of the fewest-moves solution: the smallest disk moves on the odd steps, and on the
-- even steps the only legal move that leaves it alone is made. Returns the peg to take from and the peg to put on.
local function solverMove(pegs, disks, step)
  local small = smallestPeg(pegs)
  if step % 2 == 1 then
    return small, nextPeg(small, disks)
  end
  local a = small % 3 + 1
  local b = a % 3 + 1
  if topOf(pegs[a]) < topOf(pegs[b]) then return a, b end
  return b, a
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local p = { { 2 }, { 1 }, {} }
  check(not legal(p, 1, 2), "a bigger disk cannot go on a smaller one")
  check(legal(p, 2, 1), "a smaller disk can go on a bigger one")
  check(legal(p, 1, 3), "a disk can go on an empty peg")
  check(not legal(p, 3, 1), "an empty peg has no disk to move")
  for disks = 3, 6 do
    local q = { {}, {}, {} }
    for s = disks, 1, -1 do q[1][#q[1] + 1] = s end
    local total = (1 << disks) - 1
    local allLegal = true
    for step = 1, total do
      local from, to = solverMove(q, disks, step)
      if not from or not legal(q, from, to) then
        allLegal = false
        break
      end
      move(q, from, to)
    end
    check(allLegal, disks .. " disks: every move of the solver is legal")
    check(#q[1] == 0 and #q[2] == 0, disks .. " disks: the left and middle pegs are empty at the end")
    check(#q[3] == disks and q[3][1] == disks and q[3][disks] == 1, disks .. " disks: the whole tower is on the right peg")
  end
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("hanoi needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("hanoi: " .. tostring(uiErr))
  return
end

local W = 240
local disks = DEFAULT_DISKS
local pegs = { {}, {}, {} }
local hand = nil -- the peg the top disk was taken from, or nil
local moves = 0
local solved = false
local msg = ""
local best = {} -- the fewest moves for each number of disks
local demoOn = false
local demoStep = 0
local nextDemoAt = 0

-- start again with a tower of n disks on the left peg
local function reset(n)
  disks = n
  pegs = { {}, {}, {} }
  for s = n, 1, -1 do pegs[1][#pegs[1] + 1] = s end
  hand = nil
  moves = 0
  solved = false
  demoOn = false
  msg = "move the tower to the right peg"
end

local function drawDisk(cx, y, size)
  local width = 12 + size * (64 // disks)
  gfx.fill(cx - width // 2, y, width, DISK_H - 2, DISK_COLORS[size])
end

local function draw()
  gfx.clear(0x0a0e18)
  local bestText = best[disks] and ("  best " .. best[disks]) or ""
  ui.label(4, 2, "HANOI " .. disks .. " disks  moves " .. moves .. bestText, 0xe8ecf4)
  gfx.fill(16, BASE, W - 32, 3, 0x5a6480)
  for p = 1, 3 do
    gfx.fill(PEG_X[p] - 1, PEG_TOP, 3, BASE - PEG_TOP, 0x5a6480)
    local stack = pegs[p]
    for i = 1, #stack do
      -- the lifted disk is drawn above its peg
      local y = BASE - i * DISK_H
      if hand == p and i == #stack then y = 14 end
      drawDisk(PEG_X[p], y, stack[i])
    end
  end
  ui.label(4, 104, msg, 0xffd0a0)
  ui.label(4, 116, "a s d pegs  3-6 disks  z computer solves", 0x8a94aa)
  ui.label(4, 126, "r again  ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

-- one move of the computer's solution; the board is solved when the last move is made
local function demoTick()
  local total = (1 << disks) - 1
  if demoStep >= total then
    demoOn = false
    solved = true
    msg = "computer: solved in " .. total .. " moves, the fewest"
    return
  end
  demoStep = demoStep + 1
  local from, to = solverMove(pegs, disks, demoStep)
  move(pegs, from, to)
  moves = demoStep
  nextDemoAt = sys.millis() + DEMO_DELAY
end

local function startDemo()
  reset(disks)
  demoOn = true
  demoStep = 0
  nextDemoAt = sys.millis() + DEMO_DELAY
  msg = "the computer solves it, any key stops"
end

-- a press on a peg key: the first press takes the top disk, the second puts it down if the move is legal
local function pegPressed(peg)
  if hand == nil then
    if #pegs[peg] > 0 then
      hand = peg
      msg = "put it on a, s or d (same peg puts it back)"
    end
  elseif hand == peg then
    hand = nil
    msg = ""
  elseif legal(pegs, hand, peg) then
    move(pegs, hand, peg)
    hand = nil
    moves = moves + 1
    msg = ""
    if #pegs[3] == disks then
      solved = true
      if best[disks] == nil or moves < best[disks] then best[disks] = moves end
      msg = "solved in " .. moves .. " moves (the fewest is " .. ((1 << disks) - 1) .. ")"
    end
  else
    msg = "a bigger disk cannot go on a smaller one"
  end
end

local function keyPressed(k)
  if demoOn then
    demoOn = false
    msg = "the computer stopped, the board stays as it is"
    return
  end
  if k == "r" then
    reset(disks)
  elseif k == "z" then
    startDemo()
  elseif k == "3" or k == "4" or k == "5" or k == "6" then
    reset(tonumber(k))
  elseif solved then
    return
  elseif PEG_KEYS[k] then
    pegPressed(PEG_KEYS[k])
  end
end

local w, h = ui.open()
if not w then
  print("hanoi: " .. tostring(h))
  return
end
reset(DEFAULT_DISKS)
local ok, problem = pcall(function()
  while true do
    if demoOn and sys.millis() >= nextDemoAt then
      demoTick()
    end
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if #k == 1 then k = k:lower() end
      keyPressed(k)
      k = key.poll()
    end
    sys.sleep(20)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("hanoi: " .. tostring(problem)) end
