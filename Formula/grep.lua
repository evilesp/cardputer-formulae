#!lua
-- grep: shows the lines of a text or of a file on the SD card that contain a word.
-- usage: grep WORD FILE          for example: grep milk /home/user/todo.txt
--        grep -i WORD FILE       ignores upper and lower case
--        grep -c WORD FILE       only counts the matching lines
-- The word is plain text: dots, brackets and stars are letters, not patterns.
-- Run it with --selftest to check the matching.

-- the lines of a text that contain the word, as a list of { number = , text = }
local function matchLines(text, word, ignoreCase)
  local found = {}
  if word == "" or text == "" then return found end
  if text:sub(-1) ~= "\n" then text = text .. "\n" end
  if ignoreCase then word = word:lower() end
  local number = 0
  for line in text:gmatch("(.-)\n") do
    number = number + 1
    local where = ignoreCase and line:lower() or line
    if where:find(word, 1, true) then
      found[#found + 1] = { number = number, text = line }
    end
  end
  return found
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local text = "buy milk\nwrite the report\n\ncall mum\n"
  local milk = matchLines(text, "milk", false)
  check(#milk == 1 and milk[1].number == 1 and milk[1].text == "buy milk", "milk is on line 1")
  local the = matchLines(text, "the", false)
  check(#the == 1 and the[1].number == 2, "a word inside a line is found, on line 2")
  check(#matchLines(text, "MILK", false) == 0, "upper case does not match without -i")
  local any = matchLines(text, "MILK", true)
  check(#any == 1 and any[1].text == "buy milk", "-i matches upper case")
  check(#matchLines(text, "a.b", false) == 0, "a dot is a dot, not any character")
  check(#matchLines("a.b\naxb\n", "a.b", false) == 1, "only the literal a.b matches")
  check(#matchLines(text, "*", false) == 0, "a star is a letter, not a pattern")
  check(#matchLines(text, "", false) == 0, "an empty word matches nothing")
  check(#matchLines("", "milk", false) == 0, "an empty text has no lines")
  local last = matchLines("one\ntwo", "two", false)
  check(#last == 1 and last[1].number == 2, "the last line counts without a new line")
  local blank = matchLines(text, "call", false)
  check(#blank == 1 and blank[1].number == 4, "numbers go on past a blank line")
  if failed == 0 then print("selftest ok") end
  return
end

local ignoreCase, countOnly = false, false
local i = 1
while arg[i] == "-i" or arg[i] == "-c" do
  if arg[i] == "-i" then ignoreCase = true else countOnly = true end
  i = i + 1
end

local word, path = arg[i], arg[i + 1]
if not word or not path then
  print("usage: grep [-i] [-c] WORD FILE")
  return
end

local data, err = fs.read(path)
if not data then
  print("grep: " .. path .. ": " .. tostring(err))
  return
end

local found = matchLines(data, word, ignoreCase)
if countOnly then
  print(string.format("%d matching lines", #found))
  return
end
if #found == 0 then
  print("no match")
  return
end
local shown = 15
for n = 1, math.min(#found, shown) do
  print(string.format("%d: %s", found[n].number, found[n].text))
end
if #found > shown then
  print(string.format("... %d more lines (use grep -c to count)", #found - shown))
end
