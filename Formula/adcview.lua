#!lua
-- adcview: the 8 inputs of an MCP3008 analogue-to-digital converter, live on the screen. The chip is wired to any free
-- pins through softspi (a software SPI), so the pins need not be the hardware SPI's.
--   adcview SCK MOSI MISO CS [VREF]     e.g. adcview 1 2 3 4 3.3
-- SCK goes to CLK, MOSI to DIN, MISO to DOUT and CS to CS. VREF is the reference voltage (3.3 by default) and must be
-- the voltage on the chip's VREF pin. Needs the brew packages softspi and mcp3008 (brew install softspi mcp3008) and
-- firmware v0.1.0.11(beta) or newer. q quits, and the pins are released when the app ends.

local USAGE = "usage: adcview SCK MOSI MISO CS [VREF]   e.g. adcview 1 2 3 4 3.3"

if not sys.delayUs or not driver then
  print("adcview: this firmware is too old, update to v0.1.0.11(beta) or newer")
  return
end

local pins = {}
for i = 1, 4 do
  pins[i] = tonumber(arg[i] or "")
  if not pins[i] or pins[i] ~= math.floor(pins[i]) then
    print(USAGE)
    return
  end
end
local vref = 3.3
if arg[5] then
  vref = tonumber(arg[5])
  if not vref or vref <= 0 then
    print(USAGE)
    return
  end
end

local softspi, serr = driver.load("softspi")
if not softspi then
  print("adcview: " .. tostring(serr))
  return
end
local mcp3008, merr = driver.load("mcp3008")
if not mcp3008 then
  print("adcview: " .. tostring(merr))
  return
end
local ok, bus = pcall(softspi.open, { sck = pins[1], mosi = pins[2], miso = pins[3], cs = pins[4] })
if not ok then
  print("adcview: " .. tostring(bus))
  return
end
local adc = mcp3008.open(bus)

local COLS, ROWS = term.size()
local BAR = COLS - 21  -- the bar is what is left after "ch 0   683  2.203 V  "

local function draw(codes)
  term.clear()
  term.text(0, 0, string.format("adcview   Vref %.2f V", vref), "green")
  for ch = 0, 7 do
    local code = codes[ch]
    local volts = code * vref / 1023
    local bar = string.rep("#", math.floor(code * BAR / 1023))
    term.text(0, 2 + ch, string.format("ch %d  %4d  %5.3f V  %s", ch, code, volts, bar), "text")
  end
  term.text(0, ROWS - 1, "q quits", "dim")
  term.flush()
end

local function loop()
  while true do
    local codes = {}
    for ch = 0, 7 do codes[ch] = adc:read(ch) end
    draw(codes)
    local k = key.poll()
    while k do
      if k == "q" then return end
      k = key.poll()
    end
    sys.sleep(150)
  end
end

term.fullscreen(true)
local okLoop, err = pcall(loop)
bus:close()  -- also after Ctrl+C, which stops the loop with an error
term.fullscreen(false)
if not okLoop and not tostring(err):find("interrupted", 1, true) then
  print("adcview: " .. tostring(err))
end
