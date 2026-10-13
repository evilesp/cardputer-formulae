#!lua
-- wc: counts the lines, words and bytes of a text or of a file on the SD card.
-- usage: wc TEXT...      for example: wc the quick brown fox
--        wc -f FILE      for example: wc -f /home/user/notes.txt
-- The words are the pieces between spaces, tabs and new lines; the bytes count
-- every byte, so a letter with an accent counts as two.
-- Run it with --selftest to check the counts.

-- the number of lines in a text: the new lines, plus the last line when it has no new line
local function countLines(text)
  if text == "" then return 0 end
  local _, newlines = text:gsub("\n", "")
  if text:sub(-1) ~= "\n" then newlines = newlines + 1 end
  return newlines
end

-- the number of words in a text
local function countWords(text)
  local words = 0
  for _ in text:gmatch("%S+") do words = words + 1 end
  return words
end

-- the three counts of a text, as a table
local function countAll(text)
  return { lines = countLines(text), words = countWords(text), bytes = #text }
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local empty = countAll("")
  check(empty.lines == 0 and empty.words == 0 and empty.bytes == 0, "an empty text has no lines, words or bytes")
  local one = countAll("hello")
  check(one.lines == 1 and one.words == 1 and one.bytes == 5, "hello is one line, one word, five bytes")
  local line = countAll("the quick brown fox\n")
  check(line.lines == 1 and line.words == 4 and line.bytes == 20, "a line with a new line at the end is one line")
  local two = countAll("one two\nthree")
  check(two.lines == 2 and two.words == 3 and two.bytes == 13, "two lines, the last one without a new line")
  local spaces = countAll("  a \t b\n\n  c  \n")
  check(spaces.lines == 3 and spaces.words == 3, "spaces, tabs and blank lines do not add words")
  check(countWords("\n\t ") == 0, "only white space has no words")
  check(countLines("\n") == 1, "a single new line is one line")
  if failed == 0 then print("selftest ok") end
  return
end

local function show(counts)
  print(string.format("lines: %d", counts.lines))
  print(string.format("words: %d", counts.words))
  print(string.format("bytes: %d", counts.bytes))
end

if arg[1] == "-f" then
  local path = arg[2]
  if not path then
    print("usage: wc -f FILE")
    return
  end
  local data, err = fs.read(path)
  if not data then
    print("wc: " .. path .. ": " .. tostring(err))
    return
  end
  show(countAll(data))
  return
end

if not arg[1] then
  print("usage: wc TEXT...   or   wc -f FILE")
  return
end

local parts = {}
local i = 1
while arg[i] do
  parts[#parts + 1] = arg[i]
  i = i + 1
end
show(countAll(table.concat(parts, " ")))
