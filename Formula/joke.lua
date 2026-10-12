#!lua
-- joke: a random joke from JokeAPI (no key, the safe mode is on: nothing rude). In English.
-- usage: joke [programming|pun|misc|spooky|christmas]   (any of them when left out)
-- Needs WiFi (wifi connect SSID PASS). Run it with --selftest to check the reading of the answer.

local CATEGORIES = { programming = "Programming", pun = "Pun", misc = "Misc", spooky = "Spooky", christmas = "Christmas" }

-- the text of a joke: the answer is plain text; a two-part joke has its setup and its punchline on separate lines
local function cleanJoke(text)
  text = text:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
  -- the font has no curly quotes or dashes: the common ones become ASCII
  text = text:gsub("\xE2\x80[\x98\x99]", "'"):gsub("\xE2\x80[\x9C\x9D]", '"'):gsub("\xE2\x80[\x93\x94]", "-")
  text = text:gsub("\xE2\x80\xA6", "...")
  return text
end

-- a line cut into pieces of at most `width` letters at the spaces
local function wrap(line, width)
  local out, cur = {}, ""
  for word in line:gmatch("%S+") do
    if cur == "" then
      cur = word
    elseif #cur + 1 + #word <= width then
      cur = cur .. " " .. word
    else
      out[#out + 1] = cur
      cur = word
    end
    while #cur > width do
      out[#out + 1] = cur:sub(1, width)
      cur = cur:sub(width + 1)
    end
  end
  if cur ~= "" or #out == 0 then out[#out + 1] = cur end
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
  check(cleanJoke("  hi\r\nthere \n") == "hi\nthere", "spaces and returns go")
  check(cleanJoke("it\xE2\x80\x99s") == "it's", "a curly apostrophe becomes '")
  local lines = wrap("one two three four five", 9)
  check(#lines == 3 and lines[1] == "one two" and lines[3] == "four five", "long lines are wrapped at spaces")
  check(#wrap("abcdefghijkl", 5) == 3, "a long word is cut")
  if failed == 0 then print("selftest ok") end
  return
end

local cat = "Programming,Misc,Pun"
if arg[1] then
  cat = CATEGORIES[arg[1]:lower()]
  if not cat then
    print("usage: joke [programming|pun|misc|spooky|christmas]")
    return
  end
end
if not net.connected() then
  print("joke: no WiFi connection (wifi connect SSID PASS)")
  return
end

local code, body = net.fetch("https://v2.jokeapi.dev/joke/" .. cat .. "?safe-mode&format=txt", 2048)
if not code then
  print("joke: cannot download: " .. tostring(body))
  return
end
if code ~= 200 then
  print("joke: the server answered " .. code)
  return
end
local COLS = term.size()
for line in (cleanJoke(body) .. "\n"):gmatch("(.-)\n") do
  for _, piece in ipairs(wrap(line, COLS)) do print(piece) end
end
