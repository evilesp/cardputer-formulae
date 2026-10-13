#!lua
-- blackjack: the card game against the dealer, with a bank of 100 chips. w and s change the bet by 10, space deals.
-- h takes a card, s stands, d doubles the bet (one card more, only on the first two cards). The dealer draws to 17
-- and stands on all 17s. A natural (ace and ten-value card) pays 3 to 2. When the bank is empty, r starts again with
-- 100 chips. Between hands space deals the next one. ctrl-q quits. Needs the graphics and the ui package.
-- Run it with --selftest to check the values and the payouts.

local START_BANK, STEP = 100, 10

-- a card is a number from 1 to 52: the rank is 1 (ace) to 13 (king), the suit is 1 to 4
local function rankOf(c) return (c - 1) % 13 + 1 end
local function suitOf(c) return (c - 1) // 13 + 1 end

-- the value of a hand: aces count 11 while that does not bust the hand, otherwise 1
local function handValue(cards)
  local total, aces = 0, 0
  for _, c in ipairs(cards) do
    local r = rankOf(c)
    if r == 1 then aces = aces + 1 total = total + 1
    elseif r >= 11 then total = total + 10
    else total = total + r end
  end
  if aces > 0 and total + 10 <= 21 then total = total + 10 end
  return total
end

-- a natural is two cards that make 21
local function isNatural(cards)
  return #cards == 2 and handValue(cards) == 21
end

-- the dealer takes another card below 17 and stands on every 17 (a soft 17 too)
local function dealerDraws(total)
  return total < 17
end

-- the result of a hand: the text and the chips returned to the bank (the stake back plus the winnings)
local function settle(player, dealer, stake)
  local pv, dv = handValue(player), handValue(dealer)
  local pn, dn = isNatural(player), isNatural(dealer)
  if pn and dn then return "push", stake end
  if pn then return "blackjack pays 3 to 2", stake * 5 // 2 end
  if dn then return "dealer blackjack", 0 end
  if pv > 21 then return "bust", 0 end
  if dv > 21 then return "dealer busts, you win", stake * 2 end
  if pv > dv then return "you win", stake * 2 end
  if pv < dv then return "dealer wins", 0 end
  return "push", stake
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  -- card numbers: 1 ace of spades, 13 king of spades, 14 two of hearts, 52 king of clubs
  check(rankOf(1) == 1 and rankOf(13) == 13 and rankOf(14) == 1 and rankOf(52) == 13, "ranks")
  check(suitOf(1) == 1 and suitOf(14) == 2 and suitOf(52) == 4, "suits")
  check(handValue({ 1, 13 }) == 21 and isNatural({ 1, 13 }), "ace and king is a natural")
  check(handValue({ 1, 1, 9 }) == 21 and not isNatural({ 1, 1, 9 }), "two aces and a nine are 21, not a natural")
  check(handValue({ 1, 1, 1, 1, 9 }) == 13, "four aces and a nine are 13")
  check(handValue({ 1, 6 }) == 17, "soft 17")
  check(handValue({ 11, 12, 13 }) == 30, "face cards count ten")
  check(dealerDraws(16) and not dealerDraws(17) and not dealerDraws(21), "the dealer draws below 17 only")
  local t, back = settle({ 1, 13 }, { 10, 9 }, 10)
  check(t == "blackjack pays 3 to 2" and back == 25, "blackjack pays 3 to 2")
  t, back = settle({ 1, 13 }, { 1, 12 }, 10)
  check(t == "push" and back == 10, "two naturals push")
  t, back = settle({ 10, 6 }, { 1, 13 }, 10)
  check(t == "dealer blackjack" and back == 0, "dealer natural beats 16")
  t, back = settle({ 10, 6, 9 }, { 10, 7 }, 10)
  check(t == "bust" and back == 0, "a bust loses even when the dealer busts later")
  t, back = settle({ 10, 9 }, { 10, 6, 9 }, 20)
  check(t == "dealer busts, you win" and back == 40, "dealer bust pays the doubled stake")
  t, back = settle({ 10, 9 }, { 10, 8 }, 10)
  check(t == "you win" and back == 20, "higher hand wins")
  t, back = settle({ 10, 7 }, { 10, 8 }, 10)
  check(t == "dealer wins" and back == 0, "lower hand loses")
  t, back = settle({ 10, 8 }, { 10, 8 }, 10)
  check(t == "push" and back == 10, "equal hands push")
  local deck = {}
  for i = 1, 52 do deck[i] = i end
  math.randomseed(3)
  for i = 52, 2, -1 do
    local j = math.random(i)
    deck[i], deck[j] = deck[j], deck[i]
  end
  local seen, distinct = {}, 0
  for _, c in ipairs(deck) do
    if not seen[c] then
      seen[c] = true
      distinct = distinct + 1
    end
  end
  check(#deck == 52 and distinct == 52, "a shuffle keeps every card once")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("blackjack needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("blackjack: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local RED, BLACK = 0xc03030, 0x101010
local SUITS = { "S", "H", "D", "C" }
local RANKS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }

-- the deck is one table of 52 cards, shuffled in place and cut when it runs low, so the game makes no new tables per frame
local deck, pos = {}, 53
for i = 1, 52 do deck[i] = i end

local function shuffle()
  for i = 52, 2, -1 do
    local j = math.random(i)
    deck[i], deck[j] = deck[j], deck[i]
  end
  pos = 1
end

local function draw1()
  if pos > 40 then shuffle() end
  local c = deck[pos]
  pos = pos + 1
  return c
end

-- one card face: the rank at the top, the suit under it; a hidden card shows the back
local CW, CH = 24, 32
local function drawCard(x, y, c)
  if not c then
    gfx.rect(x, y, CW, CH, 0x8a94aa)
    gfx.fill(x + 2, y + 2, CW - 4, CH - 4, 0x2a4f9a)
    return
  end
  local colour = (suitOf(c) == 2 or suitOf(c) == 3) and RED or BLACK
  gfx.fill(x, y, CW, CH, 0xf0ece0)
  gfx.rect(x, y, CW, CH, 0x8a94aa)
  ui.center(y + 5, RANKS[rankOf(c)], colour, 1, x, x + CW)
  ui.center(y + 18, SUITS[suitOf(c)], colour, 1, x, x + CW)
end

local bank, bet = START_BANK, STEP
local phase = "bet"        -- "bet", "play" or "result"
local player, dealer = {}, {}
local stake = 0            -- the chips in this hand: the bet, doubled by d
local message = "space deals"
local net = 0              -- the change of the bank in the last hand

local function maxBet()
  return math.max(STEP, bank // STEP * STEP)
end

local function finish()
  local text, back = settle(player, dealer, stake)
  bank = bank + back
  net = back - stake
  message = text
  phase = "result"
end

-- the dealer plays out the hand from the cards in view, then the hand is settled
local function dealerPlay()
  while dealerDraws(handValue(dealer)) do dealer[#dealer + 1] = draw1() end
  finish()
end

local function deal()
  stake = bet
  bank = bank - stake
  player, dealer = { draw1(), draw1() }, { draw1(), draw1() }
  net = 0
  if isNatural(player) or isNatural(dealer) then
    finish()
  else
    phase = "play"
    message = "h hit, s stand, d double"
  end
end

local function draw()
  gfx.clear(0x0a4a2a)
  ui.label(4, 2, "BLACKJACK", 0xe8ecf4)
  ui.label(110, 2, "bank " .. bank .. "  bet " .. (phase == "bet" and bet or stake), 0xe8ecf4)
  local showAll = phase == "result"
  local dtext = ""
  if #dealer > 0 then dtext = showAll and tostring(handValue(dealer)) or "?" end
  ui.label(4, 14, "dealer " .. dtext, 0xd0e8d8)
  for i, c in ipairs(dealer) do
    local shown = c
    if i == 2 and not showAll then shown = nil end
    drawCard(8 + (i - 1) * (CW + 6), 24, shown)
  end
  ui.center(60, message, 0xf4e8a0, 1, 0, W)
  if #player > 0 then ui.label(4, 70, "you " .. handValue(player), 0xd0e8d8) end
  for i, c in ipairs(player) do drawCard(8 + (i - 1) * (CW + 6), 80, c) end
  if phase == "result" and net ~= 0 then
    ui.label(160, 96, (net > 0 and "+" or "") .. net, net > 0 and 0x60e090 or 0xff7070, 2)
  end
  if phase == "bet" then
    if bank < STEP then
      ui.label(4, 122, "no chips: r starts again with " .. START_BANK, 0xf4e8a0)
    else
      ui.label(4, 122, "w s bet  space deals  ctrl-q quits", 0x8a94aa)
    end
  elseif phase == "play" then
    ui.label(4, 122, "h hit  s stand  d double  ctrl-q quits", 0x8a94aa)
  else
    ui.label(4, 122, "space next hand  ctrl-q quits", 0x8a94aa)
  end
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("blackjack: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  shuffle()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if #k == 1 then k = k:lower() end
      if phase == "bet" then
        if (k == "w" or k == "up") and bank >= STEP then bet = math.min(maxBet(), bet + STEP)
        elseif (k == "s" or k == "down") and bank >= STEP then bet = math.max(STEP, bet - STEP)
        elseif (k == " " or k == "enter") and bank >= STEP then
          bet = math.min(bet, maxBet())
          deal()
        elseif k == "r" and bank < STEP then bank, bet = START_BANK, STEP
        end
      elseif phase == "play" then
        if k == "h" or k == "up" then
          player[#player + 1] = draw1()
          if handValue(player) > 21 then finish()
          elseif handValue(player) == 21 then dealerPlay() end
        elseif k == "s" or k == "down" then dealerPlay()
        elseif k == "d" and #player == 2 and bank >= stake then
          bank = bank - stake
          stake = stake * 2
          player[#player + 1] = draw1()
          if handValue(player) > 21 then finish() else dealerPlay() end
        end
      elseif phase == "result" then
        if k == " " or k == "enter" then
          phase = "bet"
          message = "space deals"
        end
      end
      k = key.poll()
    end
    sys.sleep(30)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("blackjack: " .. tostring(problem)) end
