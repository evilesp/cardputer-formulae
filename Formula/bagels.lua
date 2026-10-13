#!lua
-- bagels: guess the secret number of three different digits (0 to 9). After each guess the clues tell you
-- FERMI for a right digit in the right place, PICO for a right digit in the wrong place, and BAGELS when no
-- digit is right. You have ten guesses. Type three digits and enter, backspace deletes, n starts a new number,
-- q or ctrl-q quits. Needs the graphics and the ui package. Run it with --selftest to check the clues.

local SLOTS, TRIES = 3, 10

-- the clues for a guess against the secret: fermi (right place) and pico (wrong place)
local function clues(secret, guess)
  local fermi, pico = 0, 0
  for i = 1, SLOTS do
    if guess[i] == secret[i] then
      fermi = fermi + 1
    else
      for j = 1, SLOTS do
        if guess[i] == secret[j] then
          pico = pico + 1
          break
        end
      end
    end
  end
  return fermi, pico
end

-- the words shown for the clues: FERMI first, then PICO, or BAGELS when nothing is right
local function clueText(fermi, pico)
  if fermi == 0 and pico == 0 then return "BAGELS" end
  local parts = {}
  for _ = 1, fermi do parts[#parts + 1] = "FERMI" end
  for _ = 1, pico do parts[#parts + 1] = "PICO" end
  return table.concat(parts, " ")
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local f, p = clues({ 1, 2, 3 }, { 1, 2, 3 })
  check(f == 3 and p == 0, "the same number is three fermi")
  f, p = clues({ 1, 2, 3 }, { 2, 3, 1 })
  check(f == 0 and p == 3, "right digits in the wrong place are three pico")
  f, p = clues({ 1, 2, 3 }, { 4, 5, 6 })
  check(f == 0 and p == 0, "no right digit gives no clues")
  f, p = clues({ 1, 2, 3 }, { 1, 5, 6 })
  check(f == 1 and p == 0, "one digit in its place is one fermi")
  f, p = clues({ 1, 2, 3 }, { 3, 5, 1 })
  check(f == 0 and p == 2, "two digits swapped out of place are two pico")
  f, p = clues({ 1, 2, 3 }, { 2, 1, 5 })
  check(f == 0 and p == 2, "two digits in each other's place are two pico")
  check(clueText(0, 0) == "BAGELS", "no right digit says BAGELS")
  check(clueText(1, 2) == "FERMI PICO PICO", "the clue words follow the counts")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("bagels needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("bagels: " .. tostring(uiErr))
  return
end

local secret, rows, typed, finished, secretText

local function newGame()
  secret = {}
  local used = {}
  while #secret < SLOTS do
    local d = math.random(0, 9)
    if not used[d] then
      used[d] = true
      secret[#secret + 1] = d
    end
  end
  rows, typed, finished, secretText = {}, {}, false, nil
end

-- a guess is checked as soon as it is sent; the row keeps its text so the drawing makes no new tables
local function submit()
  local fermi, pico = clues(secret, typed)
  local guessText = typed[1] .. " " .. typed[2] .. " " .. typed[3]
  local clue = clueText(fermi, pico)
  rows[#rows + 1] = { guess = guessText, clue = clue, colour = fermi == 0 and pico == 0 and 0x8a94aa or 0x60ff90 }
  typed = {}
  if fermi == SLOTS then
    finished = "won"
  elseif #rows >= TRIES then
    finished = "lost"
    secretText = secret[1] .. " " .. secret[2] .. " " .. secret[3]
  end
end

local function draw()
  gfx.clear(0x0a0c14)
  ui.label(8, 4, "BAGELS", 0xe8ecf4)
  for r = 1, #rows do
    local y = 20 + (r - 1) * 10
    ui.label(8, y, rows[r].guess, 0xe8ecf4)
    ui.label(60, y, rows[r].clue, rows[r].colour)
  end
  if not finished then
    local y = 20 + #rows * 10
    for s = 1, SLOTS do
      local ch = typed[s] and tostring(typed[s]) or "_"
      ui.label(8 + (s - 1) * 12, y, ch, 0xffffff)
    end
  end
  local status
  if finished == "won" then status = "you got it!"
  elseif finished == "lost" then status = "the number was " .. secretText
  else status = "guess " .. (#rows + 1) .. " of " .. TRIES end
  ui.label(160, 20, status, finished == "won" and 0x60ff90 or 0x8a94aa)
  ui.label(160, 40, finished and "n new number" or "type 3 digits, enter", 0x8a94aa)
  ui.label(8, 124, "FERMI = right place   PICO = wrong place", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("bagels: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  newGame()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" or k == "q" then return end
      if k == "n" then newGame()
      elseif finished then
        -- the game is over: n starts another
      elseif k:match("^%d$") and #typed < SLOTS then
        local repeated = false
        for _, d in ipairs(typed) do
          if d == tonumber(k) then repeated = true end
        end
        if not repeated then typed[#typed + 1] = tonumber(k) end
      elseif k == "backspace" then
        typed[#typed] = nil
      elseif k == "enter" and #typed == SLOTS then
        submit()
      end
      k = key.poll()
    end
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("bagels: " .. tostring(problem)) end
