#!lua
-- memory: find the pairs. Cards lie face down; turn two over with space, and if the pictures are the same they stay, if not they
-- turn back. Move with w a s d. Choose a small, medium or big table; the fewer tries and the less time, the better, and the best
-- result of each size is kept. n deals again, ctrl-q quits. Needs the graphics and the ui package.
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
local function newGame()
  local sz = SIZES[size]
  state = { cards = deal(sz.cols * sz.rows // 2), tries = 0, left = sz.cols * sz.rows }
  cursor, startT, hideAt, finished = 1, sys.millis(), nil, nil
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
      gfx.rect(x, y, cw, ch, 0x2c8a50)
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
    if i == cursor and not finished then gfx.rect(x - 2, y - 2, cw + 4, ch + 4, 0xffe060) end
  end
  local secs = ((finished or sys.millis()) - startT) // 1000
  ui.label(4, 3, string.format("MEMORY  %s", sz.name), 0xe8ecf4)
  ui.label(W - 90, 3, string.format("tries %d  %d:%02d", state.tries, secs // 60, secs % 60), 0x8a94aa)
  if finished then
    ui.center(H - 14, "done! n deal again", 0x60ff90, 1)
  else
    ui.label(4, H - 10, "w a s d move  space turn  n new", 0x8a94aa)
    if best[size] then ui.label(W - 78, H - 10, "best " .. best[size] .. " tries", 0x8a94aa) end
  end
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("memory: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  size = ui.choose("Memory: table", { SIZES[1].name, SIZES[2].name, SIZES[3].name })
  if not size then return end
  newGame()
  while true do
    draw()
    if hideAt and sys.millis() >= hideAt then
      hide(state)
      hideAt = nil
    end
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
      elseif (k == " " or k == "enter") and not finished then
        local r = flip(state, cursor)
        if r == "miss" then hideAt = sys.millis() + 900
        elseif r == "match" and state.left == 0 then
          finished = sys.millis()
          if not best[size] or state.tries < best[size] then
            best[size] = state.tries
            saveBest()
          end
        end
      end
      k = key.poll()
    end
    sys.sleep(30)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("memory: " .. tostring(problem)) end
