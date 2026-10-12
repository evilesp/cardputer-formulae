#!lua
-- baseconv: a number in decimal, hexadecimal, binary, octal and as a character, with the 32 bits drawn so that you can flip them.
-- a and d move along the bits, space flips the bit under the cursor, v types a number (255, 0xFF, 0b1010, 0o17, 'A'),
-- + and - add or take 1, l and r shift left and right, i inverts all bits, z clears, ctrl-q quits.
-- Needs the graphics and the ui package. Run it with --selftest to check the conversions.

local MASK = 0xFFFFFFFF

-- a number from text: decimal, 0x hex, 0b binary, 0o octal, a character in quotes, or a negative decimal; nil when it is not a number
local function parseNumber(text)
  local s = text:gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then return nil end
  local ch = s:match("^'(.)'$") or s:match('^"(.)"$')
  if ch then return ch:byte() end
  local neg = false
  if s:sub(1, 1) == "-" then neg, s = true, s:sub(2) end
  local v
  local lower = s:lower()
  if lower:match("^0x[%x]+$") then v = tonumber(lower:sub(3), 16)
  elseif lower:match("^0b[01]+$") then v = tonumber(lower:sub(3), 2)
  elseif lower:match("^0o[0-7]+$") then v = tonumber(lower:sub(3), 8)
  elseif s:match("^%d+$") then v = tonumber(s)
  elseif lower:match("^%x+h$") then v = tonumber(lower:sub(1, -2), 16)
  end
  if not v or v > MASK then return nil end
  if neg then v = (-v) & MASK end
  return math.floor(v) & MASK
end

-- the 32 bits as a string of 0 and 1, from the highest bit
local function bits(v)
  local t = {}
  for i = 31, 0, -1 do t[#t + 1] = (v >> i) & 1 == 1 and "1" or "0" end
  return table.concat(t)
end

-- the number as a signed 32 bit value
local function signed(v)
  return v >= 0x80000000 and v - 0x100000000 or v
end

local function octal(v) return string.format("%o", v) end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(parseNumber("255") == 255 and parseNumber("0xFF") == 255 and parseNumber("0b11111111") == 255 and parseNumber("0o377") == 255, "four bases")
  check(parseNumber("'A'") == 65 and parseNumber("FFh") == 255, "a character and the h suffix")
  check(parseNumber("-1") == MASK and parseNumber("-2") == 0xFFFFFFFE, "negative numbers are two's complement")
  check(parseNumber("4294967295") == MASK and parseNumber("4294967296") == nil, "the limit of 32 bits")
  check(parseNumber("abc") == nil and parseNumber("") == nil and parseNumber("0xZZ") == nil and parseNumber("1.5") == nil, "bad text")
  check(bits(5) == "00000000000000000000000000000101" and #bits(MASK) == 32, "bits")
  check(signed(MASK) == -1 and signed(0x7FFFFFFF) == 2147483647 and signed(0x80000000) == -2147483648, "signed")
  check(octal(8) == "10" and octal(255) == "377", "octal")
  check(((0x80000001 << 1) & MASK) == 2 and (0xF0 >> 4) == 0xF and ((~0) & MASK) == MASK, "shifts and not stay in 32 bits")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("baseconv needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("baseconv: " .. tostring(uiErr))
  return
end

local W, H = 240, 135
local value, cur = 0, 0  -- the number, and the bit the cursor is on (0 is the lowest)

local function draw()
  gfx.clear(0x0a0e18)
  ui.label(4, 3, "BASE CONVERTER", 0xe8ecf4)
  local c = (value >= 32 and value < 127) and string.char(value) or nil
  ui.label(4, 18, "dec", 0x8a94aa);  ui.label(40, 18, string.format("%d", value), 0x60e090, 1)
  ui.label(4, 29, "hex", 0x8a94aa);  ui.label(40, 29, string.format("0x%X", value), 0xe8ecf4)
  ui.label(4, 40, "oct", 0x8a94aa);  ui.label(40, 40, "0o" .. octal(value), 0xe8ecf4)
  ui.label(4, 51, "int32", 0x8a94aa); ui.label(40, 51, tostring(signed(value)), 0xe8ecf4)
  ui.label(4, 62, "char", 0x8a94aa); ui.label(40, 62, c and ("'" .. c .. "'") or "-", 0xe8ecf4)
  if value <= 0xFF then ui.label(130, 62, string.format("%d bits", value == 0 and 1 or math.floor(math.log(value, 2)) + 1), 0x8a94aa) end
  -- the bits: 32 cells in four groups of eight
  local text = bits(value)
  for i = 0, 31 do
    local x = 5 + i * 7 + (i // 8) * 2
    local on = text:sub(i + 1, i + 1) == "1"
    local bit = 31 - i
    gfx.fill(x, 86, 6, 14, on and 0x2c8a50 or 0x1c2233)
    ui.label(x, 90, on and "1" or "0", on and 0xffffff or 0x5a6478)
    if bit == cur then gfx.rect(x - 1, 85, 8, 16, 0xffe060) end
    if bit % 8 == 0 then ui.label(x - 1, 103, tostring(bit), 0x5a6478) end
  end
  ui.label(4, 76, "bit " .. cur .. " = " .. ((value >> cur) & 1), 0xf0c840)
  ui.label(4, 116, "a d bit  space flip  v value  + - l r i z", 0x8a94aa)
  ui.label(4, H - 10, "ctrl-q quit", 0x8a94aa)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("baseconv: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  while true do
    draw()
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if #k == 1 then k = k:lower() end
      if k == "a" or k == "left" then cur = math.min(31, cur + 1)
      elseif k == "d" or k == "right" then cur = math.max(0, cur - 1)
      elseif k == " " or k == "enter" then value = value ~ (1 << cur)
      elseif k == "+" or k == "=" or k == "w" or k == "up" then value = (value + 1) & MASK
      elseif k == "-" or k == "s" or k == "down" then value = (value - 1) & MASK
      elseif k == "l" then value = (value << 1) & MASK
      elseif k == "r" then value = value >> 1
      elseif k == "i" then value = (~value) & MASK
      elseif k == "z" then value = 0
      elseif k == "v" then
        local text = ui.prompt("number (255, 0xFF, 0b101, 'A')", "", 20)
        if text then
          local v = parseNumber(text)
          if v then value = v else ui.message("Not a number", { "try 255, 0xFF, 0b1010, 'A'" }) end
        end
      end
      k = key.poll()
    end
    sys.sleep(30)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("baseconv: " .. tostring(problem)) end
