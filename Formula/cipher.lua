#!lua
-- cipher: encrypt and decrypt text. c uses a Caesar shift (every letter moves by a number you choose), v uses a Vigenere
-- key (a word, letter by letter). d switches between encrypting and decrypting, t types a new text, k types a new key or
-- shift, w saves the result to /home/user/cipher.txt, ctrl-q quits. Letters only change; other characters stay.
-- Needs the graphics and the ui package. Run it with --selftest to check the ciphers.

local function shiftLetter(ch, n)
  local code = ch:byte()
  if code >= 65 and code <= 90 then return string.char((code - 65 + n) % 26 + 65) end
  if code >= 97 and code <= 122 then return string.char((code - 97 + n) % 26 + 97) end
  return ch
end

-- every letter moves by n places (negative to undo)
local function caesar(text, n)
  return (text:gsub(".", function(ch) return shiftLetter(ch, n % 26) end))
end

-- the Vigenere cipher: the key's letters shift the text's letters one after another (decrypt subtracts)
local function vigenere(text, key, decrypt)
  local shifts = {}
  for ch in key:upper():gmatch("%a") do shifts[#shifts + 1] = ch:byte() - 65 end
  if #shifts == 0 then return text end
  local i = 0
  return (text:gsub("%a", function(ch)
    i = i + 1
    local s = shifts[(i - 1) % #shifts + 1]
    return shiftLetter(ch, decrypt and -s or s)
  end))
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(caesar("Hello, World!", 3) == "Khoor, Zruog!", "the Caesar shift keeps the case and the punctuation")
  check(caesar(caesar("Hello", 7), -7) == "Hello", "a shift and back is the same text")
  check(caesar("xyz", 3) == "abc", "the alphabet wraps around")
  check(vigenere("ATTACKATDAWN", "LEMON", false) == "LXFOPVEFRNHR", "the classic Vigenere example")
  check(vigenere("LXFOPVEFRNHR", "LEMON", true) == "ATTACKATDAWN", "and decrypted again")
  check(vigenere("Hi there", "", false) == "Hi there", "an empty key changes nothing")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("cipher needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("cipher: " .. tostring(uiErr))
  return
end

local text, keyword, mode, decrypt = "", "", "caesar", false
local shift = 3

local function result()
  if mode == "caesar" then return caesar(text, decrypt and -shift or shift) end
  return vigenere(text, keyword, decrypt)
end

local function draw(message)
  gfx.clear(0x0a0c14)
  ui.label(8, 4, "CIPHER", 0xe8ecf4)
  ui.label(120, 4, (mode == "caesar" and ("caesar shift " .. shift) or ("vigenere key " .. keyword)) .. (decrypt and "  decrypt" or "  encrypt"), 0x8a94aa)
  ui.label(8, 24, "text: " .. text:sub(1, 36), 0xe8ecf4)
  ui.label(8, 40, "out:  " .. result():sub(1, 36), 0x60ff90)
  ui.label(8, 58, "out:  " .. result():sub(37, 72), 0x60ff90)
  ui.label(8, 110, "c caesar  v vigenere  d decrypt  t text  k key  w save", 0x8a94aa)
  ui.label(8, 122, message or "ctrl-q quits", 0xffe060)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("cipher: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  local message
  while true do
    draw(message)
    message = nil
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "c" then mode = "caesar"
      elseif k == "v" then mode = "vigenere"
      elseif k == "d" then decrypt = not decrypt
      elseif k == "t" then
        local t = ui.prompt("text", text, 72)
        if t then text = t end
      elseif k == "k" then
        if mode == "caesar" then
          local s = tonumber(ui.prompt("shift 1 to 25", tostring(shift), 2) or "")
          if s and s >= 1 and s <= 25 then shift = s else message = "a shift is a number from 1 to 25" end
        else
          local kk = ui.prompt("key (letters)", keyword, 20)
          if kk then keyword = kk:gsub("[^%a]", "") end
        end
      elseif k == "w" then
        local good, err = fs.write("/home/user/cipher.txt", result() .. "\n")
        message = good and "saved to /home/user/cipher.txt" or ("cannot save: " .. tostring(err))
      end
      k = key.poll()
    end
    sys.sleep(60)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("cipher: " .. tostring(problem)) end
