#!lua
-- hangman: guess the word one letter at a time. Type letters, Enter starts a new game, q quits.

local WORDS = { "cardputer", "terminal", "keyboard", "battery", "package", "storage",
                "wireless", "firmware", "pixel", "gpio", "scheduler", "lua" }

local STAGES = {
  "  +---+\n  |   |\n      |\n      |\n      |\n=========",
  "  +---+\n  |   |\n  O   |\n      |\n      |\n=========",
  "  +---+\n  |   |\n  O   |\n  |   |\n      |\n=========",
  "  +---+\n  |   |\n  O   |\n /|   |\n      |\n=========",
  "  +---+\n  |   |\n  O   |\n /|\\  |\n      |\n=========",
  "  +---+\n  |   |\n  O   |\n /|\\  |\n /    |\n=========",
  "  +---+\n  |   |\n  O   |\n /|\\  |\n / \\  |\n=========",
}

local word, guessed, wrong
local function newGame()
  word = WORDS[math.random(#WORDS)]
  guessed, wrong = {}, 0
end

local function shown()
  local out = {}
  for c in word:gmatch(".") do out[#out + 1] = guessed[c] and c or "_" end
  return table.concat(out, " ")
end

local function won()
  for c in word:gmatch(".") do
    if not guessed[c] then return false end
  end
  return true
end

local function draw(status)
  term.clear()
  term.text(0, 0, "HANGMAN", "white")
  local rowY = 2
  for line in (STAGES[wrong + 1] .. "\n"):gmatch("(.-)\n") do
    term.text(0, rowY, line, wrong >= 6 and "red" or "text")
    rowY = rowY + 1
  end
  term.text(16, 3, shown(), "green")
  local letters = {}
  for c in ("abcdefghijklmnopqrstuvwxyz"):gmatch(".") do
    if guessed[c] and not word:find(c, 1, true) then letters[#letters + 1] = c end
  end
  term.text(16, 5, "wrong: " .. table.concat(letters, " "), "red")
  term.text(16, 7, status or "type a letter", "cyan")
  term.text(0, 15, "enter new word   q quit", "dim")
  term.flush()
end

newGame()
term.fullscreen(true)
local quit, status = false, nil
while not quit do
  local finished = won() or wrong >= 6
  local k = key.poll()
  while k do
    if k == "q" then
      quit = true
    elseif k == "enter" then
      newGame()
      status = nil
    elseif not finished and #k == 1 and k:match("%a") then
      local c = k:lower()
      if not guessed[c] then
        guessed[c] = true
        if not word:find(c, 1, true) then wrong = wrong + 1 end
      end
    end
    k = key.poll()
  end
  if quit then break end
  if won() then status = "you got it! enter for another"
  elseif wrong >= 6 then status = "the word was " .. word .. ". enter for another" end
  draw(status)
  sys.sleep(60)
end
term.fullscreen(false)
