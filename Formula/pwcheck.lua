#!lua
-- pwcheck: rates how strong a password or passphrase is, all offline.
-- usage: pwcheck PASSWORD     for example: pwcheck Tr0ub4dor&3   pwcheck correct horse battery
--        words after the command are joined with spaces, so a passphrase works too.
-- It counts the length and the character sets used, finds very common passwords and
-- simple patterns, and estimates the time to guess it at 10 billion guesses a second
-- (a fast offline attack). The password is not saved and is not shown again.
-- Run it with --selftest to check the rules.

local GUESSES_PER_SECOND = 1e10

local SECONDS_PER_MINUTE = 60
local SECONDS_PER_HOUR = 3600
local SECONDS_PER_DAY = 86400
local SECONDS_PER_YEAR = 31557600

-- the most used passwords, checked in lower case; digits at the end are ignored
local COMMON = {
  ["password"] = true, ["123456"] = true, ["12345678"] = true, ["123456789"] = true,
  ["111111"] = true, ["000000"] = true, ["qwerty"] = true, ["qwertyuiop"] = true,
  ["letmein"] = true, ["admin"] = true, ["welcome"] = true, ["login"] = true,
  ["dragon"] = true, ["monkey"] = true, ["iloveyou"] = true, ["sunshine"] = true,
  ["football"] = true, ["master"] = true, ["passw0rd"] = true, ["abc123"] = true,
  ["cardputer"] = true, ["linux"] = true, ["hello"] = true, ["secret"] = true,
}

-- true when three or more of the same character come in a row, such as aaa
local function hasRepeat(text)
  return text:find("(.)%1%1") ~= nil
end

-- true when the characters count up or down by one three times in a row, such as abc or 321
local function hasSequence(text)
  for i = 1, #text - 2 do
    local a, b, c = text:byte(i, i + 2)
    if b == a + 1 and c == b + 1 then return true end
    if b == a - 1 and c == b - 1 then return true end
  end
  return false
end

-- the strength word for a number of bits; a common password is always very weak
local function ratingOf(bits, common)
  if common or bits < 28 then return "very weak" end
  if bits < 36 then return "weak" end
  if bits < 60 then return "fair" end
  if bits < 80 then return "strong" end
  return "very strong"
end

-- "1 second", "2 seconds": a count with its unit in the right plural
local function counted(n, unit)
  local whole = math.max(1, math.floor(n + 0.5))
  return whole .. " " .. unit .. (whole == 1 and "" or "s")
end

-- the time a fast offline attack needs for a password with this many bits (half the guesses on average)
local function timeOf(bits)
  local seconds = 2 ^ bits / 2 / GUESSES_PER_SECOND
  if seconds < 1 then return "less than a second" end
  if seconds < SECONDS_PER_MINUTE then return "about " .. counted(seconds, "second") end
  if seconds < SECONDS_PER_HOUR then return "about " .. counted(seconds / SECONDS_PER_MINUTE, "minute") end
  if seconds < SECONDS_PER_DAY then return "about " .. counted(seconds / SECONDS_PER_HOUR, "hour") end
  if seconds < SECONDS_PER_YEAR then return "about " .. counted(seconds / SECONDS_PER_DAY, "day") end
  local years = seconds / SECONDS_PER_YEAR
  if years > 1e9 then return "more than a billion years" end
  return "about " .. counted(years, "year")
end

-- the facts about a password: its length, the character sets, the bits and the patterns
local function analyse(text)
  local r = { length = #text, lower = 0, upper = 0, digit = 0, symbol = 0 }
  for i = 1, #text do
    local c = text:sub(i, i)
    if c:find("%l") then r.lower = r.lower + 1
    elseif c:find("%u") then r.upper = r.upper + 1
    elseif c:find("%d") then r.digit = r.digit + 1
    else r.symbol = r.symbol + 1 end
  end
  -- the number of characters a password could be made of, from the sets it uses
  local pool = 0
  if r.lower > 0 then pool = pool + 26 end
  if r.upper > 0 then pool = pool + 26 end
  if r.digit > 0 then pool = pool + 10 end
  if r.symbol > 0 then pool = pool + 33 end
  r.bits = 0
  if pool > 0 then r.bits = r.length * math.log(pool, 2) end
  local lower = text:lower()
  local stripped = lower:gsub("%d+$", "")
  r.common = COMMON[lower] or COMMON[stripped] or false
  r.repeats = hasRepeat(text)
  r.sequence = hasSequence(text)
  -- common words and simple patterns count for much less than their length suggests
  if r.common then
    r.bits = math.min(r.bits, 10)
  elseif r.repeats or r.sequence then
    r.bits = r.bits * 0.6
  end
  r.rating = ratingOf(r.bits, r.common)
  return r
end

-- the character sets used, as a list of words
local function kindsOf(r)
  local kinds = {}
  if r.lower > 0 then kinds[#kinds + 1] = "lower case" end
  if r.upper > 0 then kinds[#kinds + 1] = "upper case" end
  if r.digit > 0 then kinds[#kinds + 1] = "digits" end
  if r.symbol > 0 then kinds[#kinds + 1] = "symbols or spaces" end
  return table.concat(kinds, ", ")
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(analyse("Tr0ub4dor&3").rating == "strong", "Tr0ub4dor&3 is strong")
  check(analyse("kq7Zp2w9Lm4Xtr8Bv3Ns").rating == "very strong", "a 21 character mix is very strong")
  check(analyse("password").common, "password is a common password")
  check(analyse("password1").common, "password1 is a common password (digits at the end are ignored)")
  check(analyse("qwerty").rating == "very weak", "qwerty is very weak")
  check(analyse("aaaa1111Xy").repeats, "aaaa is a repeat")
  check(analyse("abcdefgh").sequence, "abc is a sequence")
  check(analyse("987xyz").sequence, "987 is a sequence going down")
  check(not analyse("hello").sequence, "hello has no sequence")
  check(analyse("abcdefgh").bits < analyse("bdfhjlnp").bits, "a counting pattern lowers the bits")
  check(analyse("a b c d").symbol == 3, "spaces count as symbols")
  check(analyse("ABCabc123!").lower == 3 and analyse("ABCabc123!").upper == 3, "letters are split by case")
  check(timeOf(20) == "less than a second", "20 bits is less than a second")
  check(timeOf(60) == "about 2 years", "60 bits is about 2 years")
  check(timeOf(128) == "more than a billion years", "128 bits is more than a billion years")
  check(counted(1, "second") == "1 second", "one second is singular")
  check(counted(2, "second") == "2 seconds", "two seconds is plural")
  if failed == 0 then print("selftest ok") end
  return
end

local text
if #arg > 0 then text = table.concat(arg, " ") end

if not text or text == "" then
  print("usage: pwcheck PASSWORD   (pwcheck Tr0ub4dor&3, words are joined)")
  return
end

local r = analyse(text)
print("length: " .. r.length .. " characters")
print("sets: " .. kindsOf(r))
print(string.format("entropy: about %.0f bits", r.bits))
print("strength: " .. r.rating)
print("time to guess: " .. timeOf(r.bits))
print("(10 billion guesses a second)")
if r.common then print("warning: a very common password") end
if r.repeats then print("warning: three equal characters in a row") end
if r.sequence then print("warning: a counting pattern such as abc or 123") end
if r.length < 12 then print("tip: use 12 or more characters") end
print("the password is not saved")
