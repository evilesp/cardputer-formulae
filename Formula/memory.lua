#!lua
-- memory: find the pairs. Cards lie face down; turn two over with space, and if the pictures are the same they stay, if not they
-- turn back. Move with w a s d. Choose a small, medium or big table and who plays: you alone (the fewest tries are kept), you
-- against the bot, or two people taking turns. Whoever finds a pair goes again; the most pairs wins. The bot plays fair: it
-- notices only some of the cards it sees and forgets them after a while (easy forgets fast, hard remembers more), it does
-- not look under the cards. n deals again, ctrl-q quits. Needs the graphics and the ui package.
-- Run it with --selftest to check the deal and the rules.

local W, H = 240, 135
local SIZES = { { name = "small 4x3", cols = 4, rows = 3 }, { name = "medium 4x4", cols = 4, rows = 4 }, { name = "big 6x4", cols = 6, rows = 4 } }
local BEST_FILE = "/home/user/.memory_best"

-- the pictures: a name, a colour and how to draw one in a box (x, y, size)
local PICTURES = {
  { "sun", 0xffc830, function(x, y, s) gfx.disc(x + s // 2, y + s // 2, s // 3, 0xffc830)
      for i = 0, 7 do local a = i * math.pi / 4
        gfx.line(x + s // 2 + math.floor(math.cos(a) * s * 0.38), y + s // 2 + math.floor(math.sin(a) * s * 0.38),
                 x + s // 2 + math.floor(math.cos(a) * s * 0.5), y + s // 2 + math.floor(math.sin(a) * s * 0.5), 0xffc830) end end },
  { "moon", 0xe8ecc8, function(x, y, s) gfx.disc(x + s // 2, y + s // 2, s // 2 - 2, 0xe8ecc8); gfx.disc(x + s // 2 + s // 5, y + s // 2 - s // 8, s // 2 - 3, 0x1c2233) end },
  { "heart", 0xe84868, function(x, y, s) gfx.disc(x + s * 3 // 10, y + s * 3 // 8, s // 4, 0xe84868); gfx.disc(x + s * 7 // 10, y + s * 3 // 8, s // 4, 0xe84868)
      gfx.triangle(x + 1, y + s * 7 // 16, x + s - 1, y + s * 7 // 16, x + s // 2, y + s - 2, 0xe84868) end },
  { "square", 0x40b0ff, function(x, y, s) gfx.fill(x + 3, y + 3, s - 6, s - 6, 0x40b0ff) end },
  { "triangle", 0x60e080, function(x, y, s) gfx.triangle(x + s // 2, y + 2, x + 2, y + s - 3, x + s - 2, y + s - 3, 0x60e080) end },
  { "diamond", 0xc060f0, function(x, y, s) gfx.triangle(x + s // 2, y + 1, x + 2, y + s // 2, x + s - 2, y + s // 2, 0xc060f0)
      gfx.triangle(x + 2, y + s // 2, x + s - 2, y + s // 2, x + s // 2, y + s - 2, 0xc060f0) end },
  { "plus", 0xff8040, function(x, y, s) gfx.fill(x + s // 3, y + 2, s // 3, s - 4, 0xff8040); gfx.fill(x + 2, y + s // 3, s - 4, s // 3, 0xff8040) end },
  { "ring", 0x40e0e0, function(x, y, s) gfx.disc(x + s // 2, y + s // 2, s // 2 - 2, 0x40e0e0); gfx.disc(x + s // 2, y + s // 2, s // 4, 0x1c2233) end },
  { "cross", 0xf0f0f0, function(x, y, s) for d = -1, 1 do gfx.line(x + 3 + d, y + 3, x + s - 4 + d, y + s - 4, 0xf0f0f0); gfx.line(x + s - 4 + d, y + 3, x + 3 + d, y + s - 4, 0xf0f0f0) end end },
  { "bars", 0xf0e040, function(x, y, s) for i = 0, 2 do gfx.fill(x + 3 + i * (s // 3), y + 4 + (2 - i) * 3, s // 4, s - 8 - (2 - i) * 3, 0xf0e040) end end },
  { "dots", 0xff6090, function(x, y, s) for i = 0, 1 do for j = 0, 1 do gfx.disc(x + s // 4 + i * (s // 2), y + s // 4 + j * (s // 2), s // 6, 0xff6090) end end end },
  { "bolt", 0xffe840, function(x, y, s) gfx.triangle(x + s * 6 // 10, y + 1, x + s // 4, y + s * 11 // 20, x + s // 2, y + s * 11 // 20, 0xffe840)
      gfx.triangle(x + s // 2, y + s * 9 // 20, x + s * 3 // 4, y + s * 9 // 20, x + s * 4 // 10, y + s - 1, 0xffe840) end },
}

-- a deal: the list of cards, each picture twice, in random order
local function deal(pairs_)
  local order = {}
  for i = 1, #PICTURES do order[i] = i end
  for i = #order, 2, -1 do local j = math.random(i); order[i], order[j] = order[j], order[i] end
  local cards = {}
  for i = 1, pairs_ do
    cards[#cards + 1] = { pic = order[i], up = false, done = false }
    cards[#cards + 1] = { pic = order[i], up = false, done = false }
  end
  for i = #cards, 2, -1 do local j = math.random(i); cards[i], cards[j] = cards[j], cards[i] end
  return cards
end

-- turns a card up; returns "first", "match", "miss" or nil when the card cannot be turned
local function flip(state, i)
  local c = state.cards[i]
  if not c or c.up or c.done then return nil end
  if state.second then return nil end
  c.up = true
  if not state.first then
    state.first = i
    return "first"
  end
  state.tries = state.tries + 1
  if state.cards[state.first].pic == c.pic then
    c.done, state.cards[state.first].done = true, true
    state.first = nil
    state.left = state.left - 2
    return "match"
  end
  state.second = i
  return "miss"
end

-- after a miss the two cards turn back
local function hide(state)
  if state.second then
    state.cards[state.first].up = false
    state.cards[state.second].up = false
    state.first, state.second = nil, nil
  end
end

-- ---- the bot ----
-- notice: the chance that the bot takes in a card it sees; keep: for how many turns it remembers it
local BOT = { { name = "easy", notice = 0.35, keep = 3 }, { name = "normal", notice = 0.55, keep = 6 }, { name = "hard", notice = 0.75, keep = 10 } }

-- the bot sees a card turned up (by anyone)
local function botNotice(mem, level, i, pic, turn)
  if math.random() < BOT[level].notice then mem[i] = { pic = pic, turn = turn } end
end

-- the bot forgets what it saw too long ago, and cards that are done
local function botForget(mem, level, turn, cards)
  for i, m in pairs(mem) do
    if turn - m.turn > BOT[level].keep or cards[i].done then mem[i] = nil end
  end
end

local function faceDown(cards, except, unknownTo)
  local out = {}
  for i, c in ipairs(cards) do
    if not c.done and not c.up and i ~= except and not (unknownTo and unknownTo[i]) then out[#out + 1] = i end
  end
  return out
end

-- the bot's first card: one of a pair it remembers (it returns both), else a card it does not know, else any card
local function botFirst(mem, cards)
  local byPic = {}
  for i = 1, #cards do
    local m = mem[i]
    if m and not cards[i].done and not cards[i].up then
      if byPic[m.pic] then return byPic[m.pic], i end
      byPic[m.pic] = i
    end
  end
  local pool = faceDown(cards, nil, mem)
  if #pool == 0 then pool = faceDown(cards) end
  return pool[math.random(#pool)]
end

-- the bot's second card: the twin of the first if it remembers where it is, else a card it does not know
local function botSecond(mem, cards, first)
  local pic = cards[first].pic
  for i = 1, #cards do
    local m = mem[i]
    if m and i ~= first and m.pic == pic and not cards[i].done and not cards[i].up then return i end
  end
  local pool = faceDown(cards, first, mem)
  if #pool == 0 then pool = faceDown(cards, first) end
  return pool[math.random(#pool)]
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local cards = deal(12)
  local count = {}
  for _, c in ipairs(cards) do count[c.pic] = (count[c.pic] or 0) + 1 end
  local twice = #cards == 24
  for _, n in pairs(count) do if n ~= 2 then twice = false end end
  check(twice, "every picture is twice on the table")
  check(#PICTURES >= 12, "twelve pictures for the big table")
  local st = { cards = { { pic = 1 }, { pic = 2 }, { pic = 1 }, { pic = 2 } }, tries = 0, left = 4 }
  check(flip(st, 1) == "first" and flip(st, 1) == nil, "a card turned up cannot be turned again")
  check(flip(st, 2) == "miss" and flip(st, 3) == nil, "no third card while two are up")
  hide(st)
  check(not st.cards[1].up and not st.cards[2].up and st.tries == 1, "a miss turns the cards back and counts a try")
  check(flip(st, 1) == "first" and flip(st, 3) == "match" and st.left == 2, "a pair stays")
  check(flip(st, 1) == nil, "a pair that is done cannot be turned")
  -- the bot
  local cards2 = { { pic = 1 }, { pic = 2 }, { pic = 1 }, { pic = 3 }, { pic = 2 }, { pic = 3 } }
  local mem = { [1] = { pic = 1, turn = 1 }, [3] = { pic = 1, turn = 1 } }
  local a, b = botFirst(mem, cards2)
  check((a == 1 and b == 3) or (a == 3 and b == 1), "the bot turns a pair it remembers")
  mem = { [5] = { pic = 2, turn = 1 } }
  check(botSecond(mem, cards2, 2) == 5, "the bot finds the twin it remembers")
  local first = botFirst(mem, cards2)
  check(first ~= 5, "the bot opens a card it does not know first")
  botForget(mem, 2, 1 + BOT[2].keep + 1, cards2)
  check(next(mem) == nil, "the bot forgets after a while")
  -- whole games of the bot alone: easy needs more tries than hard, and every game ends
  local function play(level)
    local stx = { cards = deal(8), tries = 0, left = 16 }
    local m2, turn = {}, 0
    while stx.left > 0 and turn < 400 do
      turn = turn + 1
      botForget(m2, level, turn, stx.cards)
      local f, pairWith = botFirst(m2, stx.cards)
      flip(stx, f)
      botNotice(m2, level, f, stx.cards[f].pic, turn)
      local sec = pairWith or botSecond(m2, stx.cards, f)
      local r = flip(stx, sec)
      botNotice(m2, level, sec, stx.cards[sec].pic, turn)
      if r == "miss" then hide(stx) end
    end
    return stx.left == 0, stx.tries
  end
  local sumEasy, sumHard, allEnd = 0, 0, true
  for _ = 1, 40 do
    local e1, t1 = play(1)
    local e3, t3 = play(3)
    allEnd = allEnd and e1 and e3
    sumEasy, sumHard = sumEasy + t1, sumHard + t3
  end
  check(allEnd, "the bot always finishes a table")
  check(sumEasy > sumHard and sumHard / 40 > 9, "easy needs more tries than hard, and hard is not perfect (" .. sumEasy / 40 .. " / " .. sumHard / 40 .. ")")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("memory needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("memory: " .. tostring(uiErr))
  return
end

local best = {}
do
  local text = fs.read(BEST_FILE)
  if text then for i, n in text:gmatch("(%d)=(%d+)") do best[tonumber(i)] = tonumber(n) end end
end
local function saveBest()
  local t = {}
  for i, n in pairs(best) do t[#t + 1] = i .. "=" .. n end
  fs.write(BEST_FILE, table.concat(t, "\n") .. "\n")
end

local size, state, cursor, startT, hideAt, finished
local mode, level = 1, 2      -- mode 1 alone, 2 against the bot, 3 two players
local scores, turn, turnNo = { 0, 0 }, 1, 0
local mem, botStep, botAt, botFirstCard, botPair = {}, nil, 0, nil, nil
local NAMES = { "YOU", "BOT" }

local function newGame()
  local sz = SIZES[size]
  state = { cards = deal(sz.cols * sz.rows // 2), tries = 0, left = sz.cols * sz.rows }
  cursor, startT, hideAt, finished = 1, sys.millis(), nil, nil
  scores, turn, turnNo, mem, botStep = { 0, 0 }, 1, 1, {}, nil
  NAMES = mode == 3 and { "P1", "P2" } or { "YOU", "BOT" }
end

local function draw()
  local sz = SIZES[size]
  gfx.clear(0x0c1018)
  local cw, ch = 34, sz.rows == 3 and 30 or 22
  local ps = ch - 6  -- the size of a picture inside a card
  local gap = 4
  local ox = (W - (sz.cols * (cw + gap) - gap)) // 2
  local oy = 16
  for i, c in ipairs(state.cards) do
    local col, row = (i - 1) % sz.cols, (i - 1) // sz.cols
    local x, y = ox + col * (cw + gap), oy + row * (ch + gap)
    if c.done then
      gfx.fill(x, y, cw, ch, 0x1c2233)
      gfx.rect(x, y, cw, ch, c.by == 2 and 0xd06030 or 0x2c8a50)
      PICTURES[c.pic][3](x + (cw - ps) // 2, y + (ch - ps) // 2, ps)
    elseif c.up then
      gfx.fill(x, y, cw, ch, 0x1c2233)
      gfx.rect(x, y, cw, ch, 0x8a94aa)
      PICTURES[c.pic][3](x + (cw - ps) // 2, y + (ch - ps) // 2, ps)
    else
      gfx.fill(x, y, cw, ch, 0x2c4a9a)
      gfx.rect(x + 2, y + 2, cw - 4, ch - 4, 0x5a78c8)
      ui.center(y + ch // 2 - 3, "?", 0x9ab4f0, 1, x, x + cw)
    end
    if i == cursor and not finished and not (mode == 2 and turn == 2) then gfx.rect(x - 2, y - 2, cw + 4, ch + 4, 0xffe060) end
  end
  local secs = ((finished or sys.millis()) - startT) // 1000
  if mode == 1 then
    ui.label(4, 3, string.format("MEMORY  %s", sz.name), 0xe8ecf4)
    ui.label(W - 90, 3, string.format("tries %d  %d:%02d", state.tries, secs // 60, secs % 60), 0x8a94aa)
  else
    local c1 = turn == 1 and not finished and 0x60e090 or 0x8a94aa
    local c2 = turn == 2 and not finished and 0xff9050 or 0x8a94aa
    ui.label(4, 3, NAMES[1] .. " " .. scores[1], c1)
    ui.label(56, 3, ":", 0x8a94aa)
    ui.label(66, 3, scores[2] .. " " .. NAMES[2], c2)
    local who = mode == 2 and turn == 2 and ("bot " .. BOT[level].name .. " plays") or (NAMES[turn] .. " to play")
    if not finished then ui.label(W - 6 * #who - 4, 3, who, turn == 1 and 0x60e090 or 0xff9050) end
  end
  if finished then
    local text = "done! n deal again"
    if mode ~= 1 then
      if scores[1] == scores[2] then text = "a draw! n deal again"
      else text = NAMES[scores[1] > scores[2] and 1 or 2] .. " wins! n deal again" end
    end
    ui.center(H - 14, text, 0x60ff90, 1)
  else
    ui.label(4, H - 10, "w a s d move  space turn  n new", 0x8a94aa)
    if mode == 1 and best[size] then ui.label(W - 78, H - 10, "best " .. best[size] .. " tries", 0x8a94aa) end
  end
  gfx.flush()
end

-- a card is turned by the player whose turn it is
local function turnCard(i)
  local r = flip(state, i)
  if not r then return nil end
  if mode == 2 then botNotice(mem, level, i, state.cards[i].pic, turnNo) end
  if r == "match" then
    state.cards[i].by = turn
    for j, c in ipairs(state.cards) do
      if c.done and not c.by then c.by = turn end
    end
    scores[turn] = scores[turn] + 1
    if state.left == 0 then
      finished = sys.millis()
      if mode == 1 and (not best[size] or state.tries < best[size]) then
        best[size] = state.tries
        saveBest()
      end
    end
  elseif r == "miss" then
    hideAt = sys.millis() + (mode == 2 and turn == 2 and 1300 or 900)
  end
  return r
end

-- after a miss the cards turn back and the other player goes on
local function endTurn()
  hide(state)
  hideAt = nil
  turnNo = turnNo + 1
  if mode ~= 1 then turn = 3 - turn end
  if mode == 2 then botForget(mem, level, turnNo, state.cards) end
  if turn == 2 and mode == 2 then botStep, botAt = 1, sys.millis() + 600 end
end

-- one step of the bot's turn: the first card, then the second, a little apart so you can follow
local function botPlay()
  if finished or hideAt or sys.millis() < botAt then return end
  if botStep == 1 then
    botFirstCard, botPair = botFirst(mem, state.cards)
    turnCard(botFirstCard)
    botStep, botAt = 2, sys.millis() + 700
  elseif botStep == 2 then
    local second = botPair or botSecond(mem, state.cards, botFirstCard)
    local r = turnCard(second)
    if r == "match" and not finished then botStep, botAt = 1, sys.millis() + 800 else botStep = nil end
  end
end

local w, h = ui.open()
if not w then
  print("memory: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  size = ui.choose("Memory: table", { SIZES[1].name, SIZES[2].name, SIZES[3].name })
  if not size then return end
  local who = ui.choose("Memory: players", { "Alone", "Against the bot: easy", "Against the bot: normal", "Against the bot: hard", "Two players" })
  if not who then return end
  if who == 1 then mode = 1 elseif who == 5 then mode = 3 else mode, level = 2, who - 1 end
  newGame()
  while true do
    draw()
    if hideAt and sys.millis() >= hideAt then endTurn() end
    if mode == 2 and turn == 2 and botStep then botPlay() end
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if #k == 1 then k = k:lower() end
      local cols, n = SIZES[size].cols, #state.cards
      if k == "a" or k == "left" then if (cursor - 1) % cols > 0 then cursor = cursor - 1 end
      elseif k == "d" or k == "right" then if cursor % cols > 0 and cursor < n then cursor = cursor + 1 end
      elseif k == "w" or k == "up" then if cursor > cols then cursor = cursor - cols end
      elseif k == "s" or k == "down" then if cursor + cols <= n then cursor = cursor + cols end
      elseif k == "n" then newGame()
      elseif (k == " " or k == "enter") and not finished and not hideAt and not (mode == 2 and turn == 2) then
        turnCard(cursor)
      end
      k = key.poll()
    end
    sys.sleep(30)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("memory: " .. tostring(problem)) end
