#!lua
-- typetest: how fast and how accurately you type. Type the sentence exactly; the clock starts with the first key. When
-- it is complete, the result shows the words per minute (5 characters are one word) and the accuracy. Backspace
-- corrects a letter, but a wrong letter still counts as a mistake. enter starts another sentence, ctrl-q quits.
--   typetest              a random sentence
--   typetest WORDS...     your own text to type, e.g. typetest the quick brown fox

local SENTENCES = {
  "the quick brown fox jumps over the lazy dog",
  "a small cup of hot tea keeps the cold away",
  "keys make small sounds when you press them",
  "the sun rises in the east and sets in the west",
  "pack my box with five dozen liquor jugs",
  "every good boy deserves fudge",
}

local COLS, ROWS = term.size()
local own = #arg > 0 and table.concat(arg, " ") or nil
local target

local typed = ""      -- what the player has typed so far (corrections included)
local keys = 0        -- the letters typed, wrong ones too (backspace is not a key here)
local mistakes = 0    -- the letters that did not match the sentence when they were typed
local startedAt = nil -- sys.millis() of the first key
local elapsed = 0     -- milliseconds from the first key to the end
local finished = false

local function newSentence()
  target = own or SENTENCES[math.random(#SENTENCES)]
  typed, keys, mistakes, startedAt, elapsed, finished = "", 0, 0, nil, 0, false
end

local function draw()
  term.clear()
  term.text(0, 0, "typetest", "green")
  for i = 1, #target do
    local x, y = (i - 1) % COLS, 2 + (i - 1) // COLS
    local color = "dim"
    if i <= #typed then color = typed:sub(i, i) == target:sub(i, i) and "green" or "red" end
    term.text(x, y, target:sub(i, i), color)
  end
  term.text(0, 6, string.format("typed %d of %d", #typed, #target), "text")
  if finished then
    -- under half a second the speed means nothing yet
    local wpm = "-"
    if elapsed >= 500 then wpm = tostring(math.floor((#target / 5) / (elapsed / 60000) + 0.5)) end
    local accuracy = keys > 0 and math.floor((keys - mistakes) * 100 / keys) or 100
    term.text(0, 8, string.format("wpm %s   accuracy %d%%   time %.1f s", wpm, accuracy, elapsed / 1000), "cyan")
  end
  term.text(0, ROWS - 2, "enter: another sentence   backspace: fix", "dim")
  term.text(0, ROWS - 1, "ctrl-q: quit", "dim")
  term.flush()
end

-- returns false when the player quits
local function handle(k)
  if k == "ctrl-q" then return false end
  if k == "enter" then
    newSentence()
  elseif k == "backspace" then
    if not finished and #typed > 0 then typed = typed:sub(1, -2) end
  elseif #k == 1 and k:byte() >= 32 and not finished then
    if not startedAt then startedAt = sys.millis() end
    keys = keys + 1
    local i = #typed + 1
    if k ~= target:sub(i, i) then mistakes = mistakes + 1 end
    typed = typed .. k
    if #typed == #target then
      finished = true
      elapsed = sys.millis() - startedAt
    end
  end
  return true
end

newSentence()
term.fullscreen(true)
local quit = false
while not quit do
  draw()
  local k = key.poll()
  while k do
    if not handle(k) then
      quit = true
      break
    end
    k = key.poll()
  end
  sys.sleep(30)
end
term.fullscreen(false)
