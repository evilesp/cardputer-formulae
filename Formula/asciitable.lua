#!lua
-- asciitable: the printable ASCII characters with their codes in decimal and hex.
-- usage: asciitable               the whole table, codes 32 to 126
--        asciitable A             the code of a character (a single character)
--        asciitable 65            the character with a code, decimal (65) or hex (0x41)
-- Run it with --selftest to check the rules.

local FIRST, LAST = 32, 126

local NAMES = { [32] = "space" }

-- the text shown for one code: a name for the space, the character itself otherwise
local function label(code)
  return NAMES[code] or string.char(code)
end

-- the code of a single character, or nil when the text is not exactly one printable character
local function codeOf(text)
  if #text ~= 1 then return nil end
  local code = text:byte(1)
  if code < FIRST or code > LAST then return nil end
  return code
end

-- the character for a decimal or hex (0x41) code, or nil when it is not printable
local function charOf(text)
  local code
  if text:sub(1, 2):lower() == "0x" then
    code = tonumber(text:sub(3), 16)
  else
    code = tonumber(text)
  end
  if not code or math.type(code) ~= "integer" then return nil end
  if code < FIRST or code > LAST then return nil end
  return code
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(codeOf("A") == 65, "A is code 65")
  check(codeOf(" ") == 32, "the space is code 32")
  check(codeOf("~") == 126, "the tilde is code 126")
  check(codeOf("AB") == nil, "two characters are not one code")
  check(codeOf("") == nil, "an empty text has no code")
  check(codeOf("\n") == nil, "a newline is not printable")
  check(charOf("65") == 65, "65 is a code")
  check(charOf("0x41") == 65, "0x41 is code 65")
  check(charOf("0X7e") == 126, "0X7e (upper case X) is code 126")
  check(charOf("31") == nil, "31 is a control code, not printable")
  check(charOf("127") == nil, "127 is delete, not printable")
  check(charOf("abc") == nil, "abc is not a code")
  check(charOf("1.5") == nil, "a fraction is not a code")
  check(label(32) == "space", "32 is shown as space")
  check(label(65) == "A", "65 is shown as A")
  if failed == 0 then print("selftest ok") end
  return
end

local input = arg[1]

if not input then
  -- the full table, three columns: "065 41 A"
  local line = {}
  for code = FIRST, LAST do
    line[#line + 1] = string.format("%03d %02X %-5s", code, code, label(code))
    if #line == 3 then
      print(table.concat(line, "  "))
      line = {}
    end
  end
  if #line > 0 then print(table.concat(line, "  ")) end
  return
end

local code = codeOf(input)
if code then
  print(label(code) .. " = " .. code .. " (0x" .. string.format("%02X", code) .. ")")
  return
end

local char = charOf(input)
if char then
  print(string.format("%d (0x%02X) = %s", char, char, label(char)))
  return
end

print("not a printable character or code: " .. input)
print("usage: asciitable [CHARACTER|CODE]   (codes 32 to 126)")
