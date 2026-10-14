#!lua
-- rps: rock, paper, scissors against the computer. Press r (rock), p (paper) or s (scissors).
-- Rock beats scissors, scissors beats paper, paper beats rock. The computer picks at random,
-- so no pattern can be learnt. The first to three round wins takes the match; n or enter starts
-- a new match, q or ctrl-q quits. Needs the graphics and the ui package.
-- Run it with --selftest to check the rules and the computer's choices.

local ROCK, PAPER, SCISSORS = 1, 2, 3
local NAMES = { "rock", "paper", "scissors" }
local WIN_AT = 3

-- true when choice a beats choice b; the three choices form a loop, so one step round beats the other
local function beats(a, b)
  return (a - b) % 3 == 1
end

-- 0 for a draw, 1 when the player wins the round, 2 when the computer wins it
local function outcome(player, bot)
  if player == bot then return 0 end
  if beats(player, bot) then return 1 end
  return 2
end

local function botChoice()
  return math.random(3)
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(beats(ROCK, SCISSORS), "rock beats scissors")
  check(beats(SCISSORS, PAPER), "scissors beat paper")
  check(beats(PAPER, ROCK), "paper beats rock")
  check(not beats(SCISSORS, ROCK), "scissors do not beat rock")
  check(not beats(ROCK, PAPER), "rock does not beat paper")
  check(not beats(PAPER, SCISSORS), "paper does not beat scissors")
  check(outcome(ROCK, ROCK) == 0, "the same choice is a draw")
  check(outcome(PAPER, ROCK) == 1, "paper wins against rock for the player")
  check(outcome(ROCK, PAPER) == 2, "rock loses to paper for the player")
  check(outcome(SCISSORS, SCISSORS) == 0, "scissors against scissors is a draw")
  math.randomseed(3)
  local seen = { 0, 0, 0 }
  for _ = 1, 300 do
    local c = botChoice()
    check(c >= 1 and c <= 3, "the computer picks rock, paper or scissors")
    seen[c] = seen[c] + 1
  end
  check(seen[1] > 60 and seen[2] > 60 and seen[3] > 60, "every choice of the computer comes up")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("rps needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("rps: " .. tostring(uiErr))
  return
end

local playerChoice, botPick, status
local playerWins, botWins, draws
local matchOver, lastResult

local function newMatch()
  playerWins, botWins, draws = 0, 0, 0
  playerChoice, botPick = nil, nil
  matchOver = false
  status = "pick rock, paper or scissors"
end

-- draws one of the three choices centred on cx, cy
local function drawShape(cx, cy, choice, color)
  if choice == ROCK then
    gfx.circle(cx, cy, 14, color, true)
  elseif choice == PAPER then
    gfx.fill(cx - 14, cy - 18, 28, 36, color)
    gfx.rect(cx - 14, cy - 18, 28, 36, 0x0a0c14)
  elseif choice == SCISSORS then
    gfx.line(cx - 14, cy - 14, cx + 14, cy + 14, color)
    gfx.line(cx - 13, cy - 14, cx + 15, cy + 14, color)
    gfx.line(cx + 14, cy - 14, cx - 14, cy + 14, color)
    gfx.line(cx + 15, cy - 14, cx - 13, cy + 14, color)
  end
end

local function draw()
  gfx.clear(0x0a0c14)
  ui.label(8, 4, "ROCK PAPER SCISSORS", 0xe8ecf4)
  ui.label(30, 22, "you", 0x40c0ff)
  ui.label(170, 22, "bot", 0xf0a060)
  if playerChoice then
    drawShape(40, 60, playerChoice, 0x40c0ff)
    ui.label(22, 84, NAMES[playerChoice], 0x8a94aa)
  else
    ui.label(36, 56, "?", 0x8a94aa)
  end
  if botPick then
    drawShape(170, 60, botPick, 0xf0a060)
    ui.label(150, 84, NAMES[botPick], 0x8a94aa)
  else
    ui.label(166, 56, "?", 0x8a94aa)
  end
  ui.label(8, 100, status, lastResult == 1 and 0x60ff90 or (lastResult == 2 and 0xff7070 or 0xe8ecf4))
  ui.label(8, 110, "you " .. playerWins .. "  bot " .. botWins .. "  draws " .. draws, 0x8a94aa)
  ui.label(8, 120, "r rock  p paper  s scissors", 0x8a94aa)
  ui.label(8, 129, "n new match  q quit", 0x8a94aa)
  gfx.flush()
end

-- plays one round with the player's choice and then decides the match when someone has enough wins
local function play(choice)
  playerChoice = choice
  botPick = botChoice()
  lastResult = outcome(choice, botPick)
  if lastResult == 1 then
    playerWins = playerWins + 1
    status = "you win the round"
  elseif lastResult == 2 then
    botWins = botWins + 1
    status = "the bot wins the round"
  else
    draws = draws + 1
    status = "a draw"
  end
  if playerWins >= WIN_AT then
    matchOver, status = true, "you win the match! n for a new one"
  elseif botWins >= WIN_AT then
    matchOver, status = true, "the bot wins the match, n for a new one"
  end
end

local w, h = ui.open()
if not w then
  print("rps: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  newMatch()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" or k == "q" then return end
      if k == "n" or (k == "enter" and matchOver) then
        newMatch()
        lastResult, playerChoice, botPick = nil, nil, nil
      elseif not matchOver then
        if k == "r" then play(ROCK)
        elseif k == "p" then play(PAPER)
        elseif k == "s" then play(SCISSORS)
        end
      end
      k = key.poll()
    end
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("rps: " .. tostring(problem)) end
