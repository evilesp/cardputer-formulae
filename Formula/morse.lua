#!lua
-- morse: Morse code with sound. Send mode: type a text and hear it in Morse (dots and dashes as tones from the speaker).
-- Learn mode: a letter or a digit is sounded, and you type it; each right answer is a point. Tab switches the mode, and
-- + and - change the speed, ctrl-q quits. Needs firmware v0.1.0.18(beta) (audio.beep) and the graphics and the ui package.
-- Run it with --selftest to check the code table and the timing.

local CODE = {
  A = ".-", B = "-...", C = "-.-.", D = "-..", E = ".", F = "..-.", G = "--.", H = "....", I = "..", J = ".---",
  K = "-.-", L = ".-..", M = "--", N = "-.", O = "---", P = ".--.", Q = "--.-", R = ".-.", S = "...", T = "-",
  U = "..-", V = "...-", W = ".--", X = "-..-", Y = "-.--", Z = "--..",
  ["0"] = "-----", ["1"] = ".----", ["2"] = "..---", ["3"] = "...--", ["4"] = "....-", ["5"] = ".....",
  ["6"] = "-....", ["7"] = "--...", ["8"] = "---..", ["9"] = "----.",
}
local SYMBOLS = {}
for k in pairs(CODE) do SYMBOLS[#SYMBOLS + 1] = k end
table.sort(SYMBOLS)

-- the timing in milliseconds of one unit at a speed in words per minute (PARIS standard: a dot is 1 unit,
-- a dash 3, the gap inside a letter 1, between letters 3, between words 7)
local function unitMs(wpm)
  return 1200 / wpm
end

-- the list of tones for a text: { kind = "dot" | "dash" | "letter" | "word", units = n } ; spaces make words
local function plan(text)
  local out = {}
  local upper = text:upper()
  for i = 1, #upper do
    local ch = upper:sub(i, i)
    if ch == " " then
      out[#out + 1] = { kind = "word", units = 7 }
    elseif CODE[ch] then
      local code = CODE[ch]
      for j = 1, #code do
        local sym = code:sub(j, j)
        out[#out + 1] = { kind = sym == "." and "dot" or "dash", units = sym == "." and 1 or 3 }
        if j < #code then out[#out + 1] = { kind = "gap", units = 1 } end
      end
      out[#out + 1] = { kind = "letter", units = 3 }
    end
  end
  return out
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(#SYMBOLS == 36, "26 letters and 10 digits")
  check(CODE.S == "..." and CODE.O == "---" and CODE.E == "." and CODE["0"] == "-----", "some codes")
  local seen, unique = {}, true
  for _, code in pairs(CODE) do
    if seen[code] then unique = false end
    seen[code] = true
  end
  check(unique, "each code is different")
  check(unitMs(12) == 100 and unitMs(24) == 50, "the unit of time at a speed")
  local p = plan("SOS")
  local dots, dashes = 0, 0
  for _, t in ipairs(p) do
    if t.kind == "dot" then dots = dots + 1 end
    if t.kind == "dash" then dashes = dashes + 1 end
  end
  check(dots == 6 and dashes == 3, "SOS is three dots, three dashes and three dots")
  local hasWord = false
  for _, t in ipairs(plan("A B")) do
    if t.kind == "word" and t.units == 7 then hasWord = true end
  end
  check(hasWord, "a space is a word gap of seven units")
  check(#plan("%%") == 0, "characters without a code are left out")
  if failed == 0 then print("selftest ok") end
  return
end

if not audio or not audio.beep then
  print("morse needs firmware v0.1.0.18(beta) or newer: SystemBackUpdate")
  return
end
if not gfx then
  print("morse needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("morse: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local wpm = 15
local mode = "send"         -- or "learn"
local typed = ""
local target, score, tries = nil, 0, 0
local feedback = ""

-- sounds a plan, one tone after another (a tone is started and the program waits for it to end)
local function sound(text)
  for _, t in ipairs(plan(text)) do
    local ms = unitMs(wpm) * t.units
    if t.kind == "dot" or t.kind == "dash" then pcall(audio.beep, 700, math.floor(ms)) end
    sys.sleep(math.floor(ms))
    if key.poll() == "ctrl-q" then return false end
  end
  return true
end

local function newTarget()
  target = SYMBOLS[math.random(#SYMBOLS)]
  typed = ""
  feedback = ""
end

local function draw()
  gfx.clear(0x0a0c14)
  ui.label(4, 2, "MORSE", 0xe8ecf4)
  ui.label(120, 2, string.format("%s  %d wpm", mode, wpm), 0x8a94aa)
  if mode == "send" then
    ui.label(12, 30, "type text, enter to send:", 0x8a94aa)
    ui.label(12, 46, typed .. "_", 0xffe060, 2)
  else
    ui.label(12, 30, "listen, then type the character:", 0x8a94aa)
    ui.label(12, 50, "score " .. score .. " of " .. tries, 0xe8ecf4)
    if feedback ~= "" then ui.label(12, 74, feedback, feedback:sub(1, 5) == "right" and 0x60ff90 or 0xff6060) end
    ui.label(12, 90, "enter to replay   ...", 0x8a94aa)
  end
  ui.label(4, H - 10, "tab mode  + - speed  ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("morse: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  newTarget()
  local listened = false
  draw()
  while true do
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "tab" then
        mode = mode == "send" and "learn" or "send"
        typed = ""
        if mode == "learn" then newTarget() end
      elseif k == "+" or k == "=" then wpm = math.min(35, wpm + 1)
      elseif k == "-" then wpm = math.max(5, wpm - 1)
      elseif mode == "send" then
        if k == "enter" then
          if #typed > 0 then
            draw()
            if not sound(typed) then return end
          end
          typed = ""
        elseif k == "backspace" then typed = typed:sub(1, -2)
        elseif #k == 1 and typed:len() < 40 then typed = typed .. k
        end
      else
        if k == "enter" then
          if not sound(target) then return end
        elseif #k == 1 and not listened then
          tries = tries + 1
          if k:upper() == target then
            score = score + 1
            feedback = "right: " .. target
          else
            feedback = "it was " .. target
          end
          newTarget()
          sound(target)
        end
      end
      k = key.poll()
    end
    draw()
    sys.sleep(40)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("morse: " .. tostring(problem)) end
