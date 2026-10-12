#!lua
-- quiz: rounds of 10 questions, each with four answers to choose from (1 2 3 4 or a b c d, or w s and enter). Choose a
-- category or all of them; a round never asks a question twice. After each answer it says if you were right and which
-- answer was, any key goes on. The best score of each category is kept. ctrl-q quits.
-- Your own questions: /home/user/quiz.csv, one per line, either
--   question;right answer;wrong;wrong;wrong     (four answers to choose from; one to three wrong ones)
--   question;answer|other answer                (you type the answer; capitals and extra spaces do not count)
-- Needs the graphics and the ui package. Run it with --selftest to check the questions and the rules.

local ROUND = 10
local BEST_FILE = "/home/user/.quiz_best"

-- category|question|right|wrong|wrong|wrong
local BANK = [[
Geography|What is the capital of Poland?|Warsaw|Krakow|Gdansk|Poznan
Geography|What is the longest river in Poland?|Vistula|Oder|Warta|Bug
Geography|What is the highest mountain in Poland?|Rysy|Sniezka|Babia Gora|Giewont
Geography|What is the capital of Australia?|Canberra|Sydney|Melbourne|Perth
Geography|What is the capital of Canada?|Ottawa|Toronto|Vancouver|Montreal
Geography|Which is the largest ocean?|Pacific|Atlantic|Indian|Arctic
Geography|What is the highest mountain on Earth?|Mount Everest|K2|Kilimanjaro|Mont Blanc
Geography|Which is the largest country by area?|Russia|Canada|China|USA
Geography|Which is the largest hot desert?|Sahara|Gobi|Kalahari|Atacama
Geography|On which continent is Egypt?|Africa|Asia|Europe|South America
Geography|What is the capital of Japan?|Tokyo|Kyoto|Osaka|Seoul
Geography|Which sea does Poland lie on?|Baltic Sea|North Sea|Black Sea|Adriatic Sea
Geography|What is the capital of Spain?|Madrid|Barcelona|Lisbon|Seville
Geography|Which country has the most people?|India|China|USA|Indonesia
Geography|Which river flows through Paris?|Seine|Thames|Rhine|Danube
Geography|What is the smallest country in the world?|Vatican City|Monaco|San Marino|Malta
Geography|Which continent is the coldest?|Antarctica|Europe|Asia|North America
Geography|What is the capital of Italy?|Rome|Milan|Venice|Naples
Science|What is the chemical symbol of gold?|Au|Ag|Gd|Go
Science|What is the chemical symbol of iron?|Fe|Ir|In|F
Science|How many planets are in the Solar System?|8|9|7|10
Science|Which planet is the largest?|Jupiter|Saturn|Neptune|Earth
Science|Which planet is closest to the Sun?|Mercury|Venus|Mars|Earth
Science|Which is called the red planet?|Mars|Venus|Jupiter|Mercury
Science|What gas do plants take in for photosynthesis?|Carbon dioxide|Oxygen|Nitrogen|Helium
Science|At what temperature does water boil at sea level?|100 C|90 C|80 C|120 C
Science|What is H2O?|Water|Salt|Hydrogen|Ozone
Science|What is the hardest natural material?|Diamond|Gold|Iron|Quartz
Science|How fast is light, roughly?|300 000 km/s|30 000 km/s|3 000 km/s|3 000 000 km/s
Science|Which gas is most of the air?|Nitrogen|Oxygen|Carbon dioxide|Argon
Science|What part of the cell holds the DNA?|Nucleus|Membrane|Ribosome|Wall
Science|Who made the theory of relativity?|Albert Einstein|Isaac Newton|Niels Bohr|Galileo
Science|What is the unit of electric current?|Ampere|Volt|Ohm|Watt
Science|What is the unit of force?|Newton|Joule|Pascal|Watt
Science|How many bones does an adult human have?|206|186|226|306
Science|Which organ pumps the blood?|Heart|Liver|Lungs|Kidneys
Science|What is the lightest element?|Hydrogen|Helium|Lithium|Oxygen
Science|What is the center of an atom called?|Nucleus|Electron|Shell|Orbit
History|In which year did World War II begin?|1939|1914|1945|1941
History|In which year did World War II end?|1945|1944|1918|1950
History|Who was the first king of Poland?|Boleslaw the Brave|Mieszko I|Casimir the Great|Wladyslaw Jagiello
History|In which year was the Baptism of Poland?|966|1066|1410|1025
History|In which year was the battle of Grunwald?|1410|1525|1683|1240
History|In which year did Poland regain independence?|1918|1920|1945|1989
History|Who discovered that the Earth goes round the Sun?|Nicolaus Copernicus|Galileo Galilei|Johannes Kepler|Isaac Newton
History|Who was the first person in space?|Yuri Gagarin|Neil Armstrong|Buzz Aldrin|John Glenn
History|In which year did people first walk on the Moon?|1969|1959|1972|1965
History|Who discovered polonium and radium?|Marie Curie|Albert Einstein|Louis Pasteur|Dmitri Mendeleev
History|In which year did Columbus reach America?|1492|1410|1520|1607
History|Which wall fell in 1989?|Berlin Wall|Great Wall|Hadrian's Wall|Western Wall
History|Who painted the Mona Lisa?|Leonardo da Vinci|Michelangelo|Raphael|Rembrandt
History|Which empire built the Colosseum?|Roman|Greek|Ottoman|Persian
History|Who composed the Minute Waltz?|Frederic Chopin|Mozart|Beethoven|Bach
History|Who wrote Pan Tadeusz?|Adam Mickiewicz|Henryk Sienkiewicz|Juliusz Slowacki|Boleslaw Prus
Math|What is 7 x 8?|56|54|64|48
Math|What is the square root of 144?|12|14|11|16
Math|What is 15% of 200?|30|15|20|35
Math|How many degrees are in a right angle?|90|180|45|360
Math|How many sides does a hexagon have?|6|5|7|8
Math|What is 2 to the power of 10?|1024|1000|512|2048
Math|What is pi, roughly?|3.14|2.72|1.62|3.41
Math|What is 2 + 2 x 2?|6|8|4|10
Math|How many degrees do the angles of a triangle add to?|180|360|90|270
Math|Which number is prime?|13|15|21|27
Math|What is 1000 divided by 8?|125|120|128|150
Math|What is 0.5 as a fraction?|1/2|1/5|5/1|2/5
Math|What is 9 squared?|81|18|72|99
Math|How many minutes are in a day?|1440|1200|1600|3600
Tech|What does CPU stand for?|Central Processing Unit|Computer Power Unit|Central Program Utility|Core Processing User
Tech|How many bits are in a byte?|8|4|16|10
Tech|Which company makes the iPhone?|Apple|Samsung|Google|Nokia
Tech|What does WWW stand for?|World Wide Web|Wide World Web|Web World Wide|World Web Wire
Tech|Who started Linux?|Linus Torvalds|Bill Gates|Steve Jobs|Richard Stallman
Tech|What is the chip in the Cardputer?|ESP32-S3|Raspberry Pi|ATmega328|Snapdragon
Tech|What does RAM stand for?|Random Access Memory|Read Any Memory|Rapid Action Module|Run All Memory
Tech|Which language is this quiz written in?|Lua|Python|C|Java
Tech|What is 1 KB in bytes (binary)?|1024|1000|512|2048
Tech|What does HTTP carry?|Web pages|Electricity|Phone calls|TV signal
Tech|Which number system has only 0 and 1?|Binary|Decimal|Hexadecimal|Octal
Tech|What does the ls command do?|Lists files|Deletes files|Copies files|Shows the date
Nature|What is the largest animal on Earth?|Blue whale|Elephant|Giraffe|Great white shark
Nature|How many legs does a spider have?|8|6|10|12
Nature|What is the fastest land animal?|Cheetah|Lion|Horse|Antelope
Nature|Which bird is the symbol of Poland?|White eagle|Stork|Falcon|Owl
Nature|What do bees make?|Honey|Milk|Silk|Wax only
Nature|Which animal is a mammal?|Dolphin|Shark|Trout|Octopus
Nature|What is a baby frog called?|Tadpole|Cub|Calf|Chick
Nature|Which tree has acorns?|Oak|Pine|Birch|Maple
Nature|How many hearts does an octopus have?|3|1|2|4
Nature|What do pandas mostly eat?|Bamboo|Fish|Fruit|Insects
Nature|Which animal lives the longest?|Greenland shark|Elephant|Parrot|Horse
Nature|What is the largest bird?|Ostrich|Eagle|Albatross|Emu
Culture|How many players are in a football team on the field?|11|10|9|12
Culture|How often are the Summer Olympics held?|Every 4 years|Every 2 years|Every year|Every 5 years
Culture|Which Polish footballer scored the most goals for Poland?|Robert Lewandowski|Zbigniew Boniek|Grzegorz Lato|Kazimierz Deyna
Culture|Who wrote Romeo and Juliet?|William Shakespeare|Charles Dickens|Jane Austen|Mark Twain
Culture|Which instrument has 88 keys?|Piano|Guitar|Violin|Flute
Culture|In which city is the Eiffel Tower?|Paris|London|Rome|Berlin
Culture|What colours are on the Polish flag?|White and red|Red and blue|White and blue|Red and yellow
Culture|How many strings does a standard guitar have?|6|4|5|7
Culture|Which game uses a king, queen and pawns?|Chess|Checkers|Go|Poker
Culture|Which Polish writer wrote Quo Vadis?|Henryk Sienkiewicz|Adam Mickiewicz|Czeslaw Milosz|Wislawa Szymborska
Culture|In which country were the first Olympic Games?|Greece|Italy|Egypt|France
Culture|What is the name of the dragon of Krakow?|Wawel Dragon|Smaug|Toothless|Drogon
]]

-- the text as it is compared: lower case, one space between words, no spaces at the ends
local function normal(s)
  return (s:lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- true when the typed answer is one of the right answers
local function right(typed, answers)
  local t = normal(typed)
  if t == "" then return false end
  for _, a in ipairs(answers) do
    if normal(a) == t then return true end
  end
  return false
end

-- the built-in questions: { category, question, answers = { right, wrong... } }
local function parseBank(text)
  local out = {}
  for line in text:gmatch("[^\n]+") do
    local f = {}
    for part in (line .. "|"):gmatch("(.-)|") do f[#f + 1] = part end
    if #f >= 4 then
      local answers = {}
      for i = 3, #f do answers[#answers + 1] = f[i] end
      out[#out + 1] = { category = f[1], question = f[2], answers = answers }
    end
  end
  return out
end

-- the user's questions: "question;right;wrong..." to choose, or "question;answer|other" to type
local function parseQuiz(text)
  local out = {}
  for line in text:gmatch("[^\n]+") do
    line = line:gsub("\r", "")
    local f = {}
    for part in (line .. ";"):gmatch("(.-);") do f[#f + 1] = part end
    if #f >= 2 and f[1]:match("%S") and f[2]:match("%S") then
      local q = { category = "My questions", question = f[1] }
      if #f >= 3 then
        q.answers = {}
        for i = 2, math.min(#f, 5) do
          if f[i]:match("%S") then q.answers[#q.answers + 1] = f[i] end
        end
      else
        q.typed = {}
        for alt in f[2]:gmatch("[^|]+") do q.typed[#q.typed + 1] = alt end
      end
      out[#out + 1] = q
    end
  end
  return out
end

-- a copy of the list in random order
local function shuffled(list)
  local t = {}
  for i, v in ipairs(list) do t[i] = v end
  for i = #t, 2, -1 do
    local j = math.random(i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

-- the questions of one round: up to `n` of the category ("All" takes every one), none twice
local function pickRound(all, category, n)
  local pool = {}
  for _, q in ipairs(all) do
    if category == "All" or q.category == category then pool[#pool + 1] = q end
  end
  local mixed = shuffled(pool)
  local out = {}
  for i = 1, math.min(n, #mixed) do out[i] = mixed[i] end
  return out
end

-- the categories in the order they first appear
local function categoriesOf(all)
  local seen, out = {}, {}
  for _, q in ipairs(all) do
    if not seen[q.category] then
      seen[q.category] = true
      out[#out + 1] = q.category
    end
  end
  return out
end

-- a line cut into pieces of at most `width` letters at the spaces
local function wrap(text, width)
  local out, cur = {}, ""
  for word in text:gmatch("%S+") do
    if cur == "" then cur = word
    elseif #cur + 1 + #word <= width then cur = cur .. " " .. word
    else
      out[#out + 1] = cur
      cur = word
    end
  end
  if cur ~= "" then out[#out + 1] = cur end
  return out
end

-- the number of the answer a key chooses (1 to n): 1-4 or a-d
local function choiceOf(k, n)
  local i = tonumber(k)
  if not i and #k == 1 then
    local b = k:lower():byte() - 96
    if b >= 1 and b <= 4 then i = b end
  end
  if i and i >= 1 and i <= n then return i end
  return nil
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local bank = parseBank(BANK)
  check(#bank >= 100, "at least 100 built-in questions (" .. #bank .. ")")
  local good = true
  local seenQ = {}
  for _, q in ipairs(bank) do
    if #q.answers ~= 4 or seenQ[q.question] then good = false print("bad question: " .. q.question) end
    seenQ[q.question] = true
    local seenA = {}
    for _, a in ipairs(q.answers) do
      if seenA[a] or a == "" then good = false print("repeated answer: " .. q.question) end
      seenA[a] = true
    end
    if #q.question > 3 * 38 then good = false print("too long for three rows: " .. q.question) end
    for _, a in ipairs(q.answers) do
      if #a > 34 then good = false print("answer too long: " .. a) end
    end
  end
  check(good, "every question has four different answers and fits the screen")
  check(#categoriesOf(bank) == 7, "seven categories")
  local round = pickRound(bank, "All", ROUND)
  local twice = {}
  for _, q in ipairs(round) do
    if twice[q.question] then good = false end
    twice[q.question] = true
  end
  check(#round == ROUND and good, "a round has 10 questions, none twice")
  check(#pickRound(bank, "Math", 100) > 5, "a category alone")
  local mine = parseQuiz("Capital of Poland;Warsaw|Warszawa\nbad line\n;no question\n2+2;4;5;3\n")
  check(#mine == 2 and mine[1].typed and #mine[1].typed == 2, "a typed question with two right answers")
  check(mine[2].answers and #mine[2].answers == 3 and mine[2].answers[1] == "4", "a question to choose from")
  check(right("warsaw", mine[1].typed) and right("  WARSZAWA ", mine[1].typed), "capitals and spaces do not count")
  check(not right("krakow", mine[1].typed) and not right("", mine[1].typed), "a wrong or empty answer is wrong")
  check(choiceOf("2", 4) == 2 and choiceOf("c", 4) == 3 and choiceOf("C", 4) == 3 and choiceOf("5", 4) == nil, "keys")
  check(choiceOf("d", 3) == nil, "no fourth answer when there are three")
  local lines = wrap("one two three four five", 9)
  check(#lines == 3 and lines[3] == "four five", "wrapping")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("quiz needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("quiz: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local all = parseBank(BANK)
local custom = fs.read("/home/user/quiz.csv")
if custom then
  for _, q in ipairs(parseQuiz(custom)) do all[#all + 1] = q end
end

-- the best scores: "category=score" lines
local best = {}
do
  local text = fs.read(BEST_FILE)
  if text then
    for cat, n in text:gmatch("([^=\n]+)=(%d+)") do best[cat] = tonumber(n) end
  end
end
local function saveBest()
  local lines = {}
  for cat, n in pairs(best) do lines[#lines + 1] = cat .. "=" .. n end
  fs.write(BEST_FILE, table.concat(lines, "\n") .. "\n")
end

local LETTERS = { "A", "B", "C", "D" }
local COL = { text = 0xe8ecf4, dim = 0x8a94aa, good = 0x60e090, bad = 0xff6060, sel = 0x2a3a66, box = 0x161c2c }

-- one question on the screen. state: nil while choosing; { chosen = i, ok = bool } after the answer
local function drawQuestion(q, order, num, total, score, cursor, state, typed)
  gfx.clear(0x0a0c14)
  ui.label(4, 3, q.category:upper(), COL.dim)
  ui.label(W - 84, 3, string.format("%2d/%d  %d pts", num, total, score), COL.dim)
  gfx.hline(0, W - 1, 13, 0x2a3350)
  local lines = wrap(q.question, 38)
  for i = 1, math.min(3, #lines) do ui.label(4, 6 + i * 11, lines[i], COL.text) end
  local y0 = 56
  if order then
    for i, ai in ipairs(order) do
      local y = y0 + (i - 1) * 16
      local a = q.answers[ai]
      local bg = COL.box
      if state then
        if ai == 1 then bg = 0x1d5a34 elseif i == state.chosen then bg = 0x6a2020 end
      elseif i == cursor then
        bg = COL.sel
      end
      gfx.fill(2, y - 3, W - 4, 14, bg)
      ui.label(6, y, LETTERS[i], 0xf0c840)
      ui.label(18, y, a, COL.text)
    end
  else
    gfx.fill(2, y0 - 3, W - 4, 14, COL.sel)
    ui.label(6, y0, "> " .. typed .. (state and "" or "_"), COL.text)
    if state and not state.ok then ui.label(6, y0 + 18, "it was: " .. q.typed[1], COL.good) end
  end
  if state then
    ui.label(4, H - 10, state.ok and "Right!   any key: next" or "Wrong.   any key: next", state.ok and COL.good or COL.bad)
  else
    ui.label(4, H - 10, order and "1-4 / a-d, or w s enter   ctrl-q quit" or "type it, enter   ctrl-q quit", COL.dim)
  end
  gfx.flush()
end

-- waits for a key and returns it ("ctrl-q" too), drawing the screen with redraw() meanwhile (gfx.flush lets Ctrl+C in)
local function waitKey(redraw)
  while true do
    redraw()
    local k = key.poll()
    if k then return k end
    sys.sleep(40)
  end
end

-- asks one question; returns true (right), false (wrong) or nil (quit)
local function ask(q, num, total, score)
  if q.typed then
    local typed = ""
    while true do
      local k = waitKey(function() drawQuestion(q, nil, num, total, score, nil, nil, typed) end)
      if k == "ctrl-q" then return nil end
      if k == "enter" and typed:match("%S") then break end
      if k == "backspace" then typed = typed:sub(1, -2)
      elseif #k == 1 and k:byte() >= 32 and k:byte() < 127 and #typed < 34 then typed = typed .. k end
    end
    local ok = right(typed, q.typed)
    local after = function() drawQuestion(q, nil, num, total, score + (ok and 1 or 0), nil, { ok = ok }, typed) end
    if waitKey(after) == "ctrl-q" then return nil end
    return ok
  end
  local order = {}
  for i = 1, #q.answers do order[i] = i end
  order = shuffled(order)
  local cursor = 1
  local chosen
  while not chosen do
    local k = waitKey(function() drawQuestion(q, order, num, total, score, cursor) end)
    if k == "ctrl-q" then return nil end
    local a = ui.keyAction(k)
    if k == "w" or k == "up" then cursor = cursor > 1 and cursor - 1 or #order
    elseif k == "s" or k == "down" then cursor = cursor < #order and cursor + 1 or 1
    elseif a == "ok" then chosen = cursor
    else chosen = choiceOf(k, #order) end
  end
  local ok = order[chosen] == 1
  local after = function() drawQuestion(q, order, num, total, score + (ok and 1 or 0), cursor, { chosen = chosen, ok = ok }) end
  if waitKey(after) == "ctrl-q" then return nil end
  return ok
end

local w, h = ui.open()
if not w then
  print("quiz: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local cats = categoriesOf(all)
  table.insert(cats, 1, "All")
  local choice = 1
  while true do
    local items = {}
    for i, c in ipairs(cats) do items[i] = c .. (best[c] and ("  (best " .. best[c] .. ")") or "") end
    choice = ui.choose("Quiz: category", items, { selected = choice })
    if not choice then return end
    local category = cats[choice]
    local round = pickRound(all, category, ROUND)
    local score, quit = 0, false
    for i, q in ipairs(round) do
      local r = ask(q, i, #round, score)
      if r == nil then
        quit = true
        break
      end
      if r then score = score + 1 end
    end
    if quit then return end
    local lines = { "You scored " .. score .. " of " .. #round .. "." }
    if not best[category] or score > best[category] then
      if best[category] then lines[#lines + 1] = "A new best score!" end
      best[category] = score
      saveBest()
    end
    lines[#lines + 1] = score == #round and "Perfect!" or (score >= #round * 0.7 and "Well done." or "Try again?")
    ui.message("Round over", lines)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("quiz: " .. tostring(problem)) end
