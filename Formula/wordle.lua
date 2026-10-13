#!lua
-- wordle: guess the hidden five-letter word in six tries. Type letters, enter sends the guess, backspace deletes.
-- Green = right letter in the right place, yellow = the letter is in the word somewhere else, grey = not in the word.
-- The keys on the right show the best mark each letter has had. After the game n starts a new word, ctrl-q quits.
-- Any five letters are accepted as a guess (there is no dictionary). Needs the graphics and the ui package.
-- Run it with --selftest to check the marks.

local LEN, TRIES = 5, 6
local WORDS = {
  "apple", "beach", "bread", "brick", "cable", "candy", "cloud", "dance", "dream", "eagle",
  "earth", "flame", "flute", "grape", "green", "happy", "heart", "house", "jolly", "knife",
  "lemon", "light", "magic", "mango", "music", "night", "ocean", "olive", "orbit", "paper",
  "piano", "plant", "queen", "river", "robot", "sugar", "table", "tiger", "water", "whale",
  "world", "yacht", "zebra", "pizza",
}
local MARK_RIGHT, MARK_WRONG_PLACE, MARK_ABSENT = 3, 2, 1
local MARK_COLOUR = { [MARK_RIGHT] = 0x3a9d4a, [MARK_WRONG_PLACE] = 0xc9a227, [MARK_ABSENT] = 0x3a4152 }
local KEY_ROWS = { "abcdefghijklm", "nopqrstuvwxyz" }

-- the mark of each letter of a guess against the answer: green, yellow or grey (a letter counts only as often as it is in the answer)
local function score(answer, guess)
  local marks, left = {}, {}
  for i = 1, LEN do
    local a = answer:sub(i, i)
    if guess:sub(i, i) == a then
      marks[i] = MARK_RIGHT
    else
      marks[i] = MARK_ABSENT
      left[a] = (left[a] or 0) + 1
    end
  end
  for i = 1, LEN do
    local g = guess:sub(i, i)
    if marks[i] == MARK_ABSENT and (left[g] or 0) > 0 then
      marks[i] = MARK_WRONG_PLACE
      left[g] = left[g] - 1
    end
  end
  return marks
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local function same(a, b)
    for i = 1, LEN do
      if a[i] ~= b[i] then return false end
    end
    return true
  end
  check(same(score("apple", "apple"), { 3, 3, 3, 3, 3 }), "the right word is all green")
  check(same(score("apple", "pizza"), { 2, 1, 1, 1, 2 }), "a letter elsewhere is yellow, a letter not in it grey")
  check(same(score("apple", "pappy"), { 2, 2, 3, 1, 1 }), "a repeated letter is yellow only as often as it is in the word")
  check(same(score("abcde", "bbxyz"), { 1, 3, 1, 1, 1 }), "a green letter is taken before a yellow one")
  check(same(score("crane", "zzzzz"), { 1, 1, 1, 1, 1 }), "no letter in common is all grey")
  for _, w in ipairs(WORDS) do
    check(#w == LEN and w:match("^%l+$") ~= nil, "every word is five lowercase letters: " .. w)
  end
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("wordle needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("wordle: " .. tostring(uiErr))
  return
end

local answer, rows, typed, finished, best

local function newGame()
  answer = WORDS[math.random(#WORDS)]
  rows, typed, finished, best = {}, "", false, {}
end

local function submit()
  local guess = typed
  local marks = score(answer, guess)
  rows[#rows + 1] = { word = guess, marks = marks }
  for i = 1, LEN do
    local letter = guess:sub(i, i)
    if (best[letter] or 0) < marks[i] then best[letter] = marks[i] end
  end
  typed = ""
  if guess == answer then finished = "won"
  elseif #rows >= TRIES then finished = "lost" end
end

local function draw()
  gfx.clear(0x0a0c14)
  -- the grid of guesses on the left
  for r = 1, TRIES do
    local y = 4 + (r - 1) * 21
    local row = rows[r]
    for c = 1, LEN do
      local x = 6 + (c - 1) * 20
      local letter, colour = "", 0x1c2233
      if row then
        letter = row.word:sub(c, c)
        colour = MARK_COLOUR[row.marks[c]]
      elseif r == #rows + 1 and c <= #typed then
        letter = typed:sub(c, c)
        colour = 0x2a3350
      end
      gfx.fill(x, y, 18, 18, colour)
      if letter ~= "" then ui.label(x + 6, y + 5, letter:upper(), 0xffffff) end
    end
  end
  -- the side panel: the title, the try, the status and the keys
  ui.label(124, 4, "WORDLE", 0xe8ecf4)
  ui.label(124, 18, "guess " .. math.min(#rows + 1, TRIES) .. " of " .. TRIES, 0x8a94aa)
  local status
  if finished == "won" then status = "you got it!"
  elseif finished == "lost" then status = "the word was"
  else status = "type five letters" end
  ui.label(124, 30, status, finished == "won" and 0x60ff90 or 0xe8ecf4)
  if finished == "lost" then ui.label(124, 40, answer:upper(), 0xf0d040) end
  if finished then ui.label(124, 52, "n new word", 0x8a94aa) end
  for r, line in ipairs(KEY_ROWS) do
    for i = 1, #line do
      local letter = line:sub(i, i)
      local mark = best[letter]
      ui.label(124 + (i - 1) * 8, 68 + (r - 1) * 12, letter:upper(), mark and MARK_COLOUR[mark] or 0x8a94aa)
    end
  end
  ui.label(124, 100, "green: right place", MARK_COLOUR[MARK_RIGHT])
  ui.label(124, 110, "yellow: in the word", MARK_COLOUR[MARK_WRONG_PLACE])
  ui.label(124, 120, "grey: not in it", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("wordle: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  newGame()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if finished then
        if k == "n" then newGame() end
      elseif k == "backspace" then
        typed = typed:sub(1, -2)
      elseif k == "enter" then
        if #typed == LEN then submit() end
      elseif #k == 1 and k:match("%a") and #typed < LEN then
        typed = typed .. k:lower()
      end
      k = key.poll()
    end
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("wordle: " .. tostring(problem)) end
