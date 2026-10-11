#!lua
-- passgen: a random password. passgen [LENGTH] [-s]   LENGTH is 4 to 64 (16 by default); -s adds symbols.
-- Every password has a letter and a digit (and a symbol with -s). It prints only the password, so it can be copied
-- from the screen or piped on. The random numbers start from the clock of the device.

local LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local DIGITS = "0123456789"
local SYMBOLS = "!@#$%^&*-_=+?"
local USAGE = "usage: passgen [LENGTH] [-s]   e.g. passgen 20 -s   (LENGTH 4 to 64, 16 by default)"

local length, symbols = 16, false
for _, a in ipairs(arg) do
  if a == "-s" then
    symbols = true
  elseif a:match("^%d+$") then
    length = tonumber(a)
  else
    print(USAGE)
    return
  end
end
if length < 4 or length > 64 then
  print(USAGE)
  return
end

if sys.micros then math.randomseed(sys.micros()) end

local classes = { LETTERS, DIGITS }
if symbols then classes[#classes + 1] = SYMBOLS end
local all = table.concat(classes)

local function pick(set)
  local k = math.random(#set)
  return set:sub(k, k)
end

-- one character from each class first, the rest from all of them; then the order is shuffled
local chars = {}
for i = 1, length do
  chars[i] = pick(i <= #classes and classes[i] or all)
end
for i = #chars, 2, -1 do
  local j = math.random(i)
  chars[i], chars[j] = chars[j], chars[i]
end
print(table.concat(chars))
