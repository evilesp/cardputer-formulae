#!lua
-- quiz: questions and answers from /home/user/quiz.csv, one per line: question;answer (or answer|other answer, which is also
-- right). Without the file a few questions are asked. Type the answer and enter; letters are compared without capitals and
-- extra spaces. n gives the next question, ctrl-q quits and shows the score. Needs the graphics and the ui package. Run it
-- with --selftest to check the file and the answers.

local BUILT_IN = {
  "Capital of Poland;Warsaw|Warszawa",
  "2 + 2 * 2;6",
  "Chemical symbol of gold;Au",
}

-- the questions of a text: { question, answers = { ... } } for each line with a question and an answer
local function parseQuiz(text)
  local out = {}
  for line in text:gmatch("[^\n]+") do
    local q, a = line:match("^(.-);(.+)$")
    if q and q:match("%S") and a:match("%S") then
      local answers = {}
      for alt in a:gmatch("[^|]+") do answers[#answers + 1] = alt end
      out[#out + 1] = { question = q, answers = answers }
    end
  end
  return out
end

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

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local list = parseQuiz("Capital of Poland;Warsaw|Warszawa\nbad line\n;no question\nno answer;\n2+2;4\n")
  check(#list == 2 and list[1].question == "Capital of Poland" and #list[1].answers == 2, "two questions with their answers")
  check(list[2].answers[1] == "4", "a question with one answer")
  check(right("warsaw", list[1].answers) and right("  WARSZAWA ", list[1].answers), "capitals and spaces do not count")
  check(not right("krakow", list[1].answers) and not right("", list[1].answers), "a wrong or empty answer is wrong")
  check(right("Hello   world", { "hello world" }), "several spaces are one")
  check(#parseQuiz(table.concat(BUILT_IN, "\n")) == 3, "the built-in questions are all readable")
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
local questions = parseQuiz(table.concat(BUILT_IN, "\n"))
local custom = fs.read("/home/user/quiz.csv")
if custom then
  local mine = parseQuiz(custom)
  if #mine > 0 then questions = mine end
end
local current, score, asked, feedback = nil, 0, 0, ""

local function nextQuestion()
  current = questions[math.random(#questions)]
  feedback = ""
end

local function draw()
  gfx.clear(0x0a0c14)
  ui.label(8, 4, "QUIZ", 0xe8ecf4)
  ui.label(150, 4, "score " .. score .. " of " .. asked, 0x8a94aa)
  if current then
    ui.label(8, 36, current.question:sub(1, 36), 0xe8ecf4, 1)
    if #current.question > 36 then ui.label(8, 50, current.question:sub(37, 72), 0xe8ecf4) end
  end
  ui.label(8, 80, feedback, feedback:sub(1, 5) == "right" and 0x60ff90 or 0xff6060)
  ui.label(8, H - 10, "type the answer, enter   n next   ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("quiz: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  nextQuestion()
  while true do
    draw()
    local typed = ui.prompt("answer", "", 40)
    if typed == nil then return end
    asked = asked + 1
    if right(typed, current.answers) then
      score = score + 1
      feedback = "right!"
    else
      feedback = "it was: " .. current.answers[1]
    end
    nextQuestion()
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("quiz: " .. tostring(problem)) end
