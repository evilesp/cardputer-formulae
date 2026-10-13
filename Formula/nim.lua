#!lua
-- nim: three piles of sticks (3, 5 and 7 at the start). Choose a pile with w a s d, then type how
-- many sticks to take from it with the digits 1 to 7. Whoever takes the last stick wins.
-- The bot plays the perfect strategy (nim-sum), so it wins whenever it can win. n starts a new game,
-- ctrl-q quits. Needs the graphics and the ui package.
-- Run it with --selftest to check the rules and the bot.

local START = { 3, 5, 7 }
local piles, sel, over, status
local wins, losses = 0, 0

local function total(p)
  return p[1] + p[2] + p[3]
end

-- the nim-sum: zero when the player to move is in a lost position
local function nimSum(p)
  return p[1] ~ p[2] ~ p[3]
end

-- takes n sticks from pile i; returns false when that is not a legal move
local function take(p, i, n)
  if i < 1 or i > 3 or n < 1 or n > p[i] then return false end
  p[i] = p[i] - n
  return true
end

-- the bot's move as pile and count: a winning move when there is one, else a random legal move.
-- Returns nil when no sticks are left.
local function botMove(p)
  if total(p) == 0 then return nil end
  local s = nimSum(p)
  if s ~= 0 then
    for i = 1, 3 do
      local target = p[i] ~ s
      if target < p[i] then return i, p[i] - target end
    end
  end
  local i
  repeat i = math.random(3) until p[i] > 0
  return i, math.random(p[i])
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(nimSum({ 3, 5, 7 }) == 1, "the nim-sum of 3, 5 and 7 is 1")
  check(nimSum({ 2, 2, 0 }) == 0, "two equal piles have nim-sum 0")
  check(total({ 3, 5, 7 }) == 15, "the total of the piles")
  local p = { 3, 5, 7 }
  check(take(p, 1, 3) and p[1] == 0, "a pile can be emptied")
  p = { 1, 1, 1 }
  check(not take(p, 1, 2), "more sticks than a pile holds cannot be taken")
  check(not take(p, 1, 0), "taking no sticks is not a move")
  check(not take(p, 4, 1), "there are only three piles")
  check(p[1] == 1, "an illegal move leaves the piles as they were")
  check(botMove({ 0, 0, 0 }) == nil, "the bot has no move without sticks")
  p = { 3, 5, 7 }
  local bi, bn = botMove(p)
  check(bi ~= nil and take(p, bi, bn), "the bot makes a legal move")
  check(nimSum(p) == 0, "the bot leaves nim-sum 0 when it can")
  p = { 3, 4, 5 }
  bi, bn = botMove(p)
  check(take(p, bi, bn) and nimSum(p) == 0, "the bot finds the winning move on 3, 4, 5")
  p = { 1, 2, 3 }
  bi, bn = botMove(p)
  check(bi ~= nil and take(p, bi, bn), "the bot moves from a lost position too")
  -- from 3, 5, 7 with the bot to move the bot must win every game against random play
  math.randomseed(7)
  local lost = 0
  for _ = 1, 200 do
    local g = { 3, 5, 7 }
    local turn = "bot"
    while total(g) > 0 do
      if turn == "bot" then
        local i, n = botMove(g)
        take(g, i, n)
      else
        local i
        repeat i = math.random(3) until g[i] > 0
        take(g, i, math.random(g[i]))
      end
      if total(g) == 0 and turn == "player" then lost = lost + 1 end
      turn = turn == "bot" and "player" or "bot"
    end
  end
  check(lost == 0, "the bot never loses from 3, 5, 7 against random moves")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("nim needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("nim: " .. tostring(uiErr))
  return
end

local function newGame()
  piles = { START[1], START[2], START[3] }
  sel = 1
  over = false
  status = "your move"
end

-- ends the game when nobody has sticks left; whoever took the last stick wins
local function checkEnd(who)
  if total(piles) ~= 0 then return false end
  over = true
  if who == "player" then
    wins = wins + 1
    status = "you win!"
  else
    losses = losses + 1
    status = "bot wins!"
  end
  return true
end

local function draw()
  gfx.clear(0x0a0c14)
  for i = 1, 3 do
    local y = 22 + (i - 1) * 34
    if i == sel then gfx.rect(54, y - 5, 58, 30, 0xf0d060) end
    ui.label(8, y + 6, "pile " .. i, i == sel and 0xf0d060 or 0x8a94aa)
    for s = 1, piles[i] do
      gfx.fill(60 + (s - 1) * 7, y, 4, 20, 0xe0c080)
    end
  end
  ui.label(124, 12, "NIM", 0xe8ecf4)
  ui.label(124, 24, "last stick wins", 0x8a94aa)
  ui.label(124, 40, "wins " .. wins, 0x8a94aa)
  ui.label(124, 50, "losses " .. losses, 0x8a94aa)
  ui.label(124, 66, status, 0x60ff90)
  ui.label(124, 90, "w s a d pick pile", 0x8a94aa)
  ui.label(124, 100, "1 to 7 take sticks", 0x8a94aa)
  ui.label(124, 116, "n new  ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("nim: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  newGame()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "n" then
        newGame()
      elseif (k == "w" or k == "a") and sel > 1 then
        sel = sel - 1
      elseif (k == "s" or k == "d") and sel < 3 then
        sel = sel + 1
      elseif k:match("^[1-7]$") and not over then
        local n = tonumber(k)
        if take(piles, sel, n) then
          status = "you took " .. n
          if not checkEnd("player") then
            local bi, bn = botMove(piles)
            take(piles, bi, bn)
            status = "bot took " .. bn
            checkEnd("bot")
          end
        else
          status = "pile " .. sel .. " has " .. piles[sel]
        end
      end
      k = key.poll()
    end
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("nim: " .. tostring(problem)) end
