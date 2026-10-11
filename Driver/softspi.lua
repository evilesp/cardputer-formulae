#!lua
-- softspi: an SPI bus on any GPIO pins, bit-banged in Lua. Use it for a device whose pins the hardware spi module cannot
-- reach. A driver is not a program: brew installs it into /usr/local/lib/drivers, and an app loads it with driver.load.
--   local softspi = driver.load("softspi")
--   local bus = softspi.open{ sck = 1, mosi = 2, miso = 3, cs = 4 }   -- delay = 2 (microseconds per half clock)
--   local reply = bus:transfer("\x01\x80\x00")   -- sends the bytes and returns the bytes read (as many as sent)
--   bus:write("\x00")                             -- sends without keeping the reply
--   bus:close()                                   -- the pins are inputs again
-- It is SPI mode 0 (clock low when idle, data read on the rising edge), most significant bit first. A half clock of
-- 2 microseconds gives about 200 kHz; delay can be 1 to 10000. It needs firmware v0.1.0.11(beta) (sys.delayUs).
-- Run it as a script with --selftest to check it on the desktop harness.

local M = {}

local Bus = {}
Bus.__index = Bus

local function pinArg(opts, name)
  local p = opts[name]
  if math.type(p) ~= "integer" or p < 0 or p > 48 then
    error("softspi.open needs " .. name .. " as a pin number, 0 to 48", 3)
  end
  return p
end

function M.open(opts)
  if type(opts) ~= "table" then
    error("softspi.open needs a table, for example softspi.open{ sck = 1, mosi = 2, miso = 3, cs = 4 }", 2)
  end
  if not sys.delayUs then
    error("softspi needs firmware v0.1.0.11(beta) or newer (sys.delayUs)", 2)
  end
  local bus = {
    sck = pinArg(opts, "sck"),
    mosi = pinArg(opts, "mosi"),
    miso = pinArg(opts, "miso"),
    cs = pinArg(opts, "cs"),
    delay = opts.delay or 2,
  }
  if math.type(bus.delay) ~= "integer" or bus.delay < 1 or bus.delay > 10000 then
    error("softspi delay is 1 to 10000 microseconds", 2)
  end
  local used = {}
  for _, p in ipairs({ bus.sck, bus.mosi, bus.miso, bus.cs }) do
    if used[p] then error("softspi pins must all differ (pin " .. p .. " is used twice)", 2) end
    used[p] = true
  end
  gpio.mode(bus.sck, "out")
  gpio.write(bus.sck, 0)
  gpio.mode(bus.mosi, "out")
  gpio.mode(bus.cs, "out")
  gpio.write(bus.cs, 1)
  gpio.mode(bus.miso, "in")
  return setmetatable(bus, Bus)
end

-- Sends the bytes of text, most significant bit first, and returns the bytes read in the same clocks
function Bus:transfer(text)
  if self.closed then error("the bus is closed", 2) end
  if type(text) ~= "string" then error("transfer takes a string of bytes", 2) end
  local d = self.delay
  local reply = {}
  gpio.write(self.cs, 0)
  for i = 1, #text do
    local out = text:byte(i)
    local got = 0
    for bit = 7, 0, -1 do
      gpio.write(self.mosi, (out >> bit) & 1)
      sys.delayUs(d)
      gpio.write(self.sck, 1)
      got = (got << 1) | gpio.read(self.miso)
      sys.delayUs(d)
      gpio.write(self.sck, 0)
    end
    reply[i] = string.char(got)
  end
  gpio.write(self.cs, 1)
  return table.concat(reply)
end

function Bus:write(text)
  self:transfer(text)
end

-- The pins go back to inputs, so the app can use them for something else
function Bus:close()
  if self.closed then return end
  self.closed = true
  for _, p in ipairs({ self.sck, self.mosi, self.cs }) do gpio.mode(p, "in") end
end

if arg and arg[1] == "--selftest" then
  local checks = 0
  local function expect(cond, what)
    checks = checks + 1
    if not cond then error("check " .. checks .. ": " .. what) end
  end
  expect(not pcall(M.open, { sck = 1 }), "a missing pin is refused")
  expect(not pcall(M.open, { sck = 1, mosi = 1, miso = 3, cs = 4 }), "two equal pins are refused")
  expect(not pcall(M.open, { sck = 1, mosi = 2, miso = 3, cs = 99 }), "pin 99 is refused")
  expect(not pcall(M.open, { sck = 1, mosi = 2, miso = 3, cs = 4, delay = 0 }), "delay 0 is refused")
  local bus = M.open{ sck = 1, mosi = 2, miso = 3, cs = 4, delay = 1 }
  expect(#bus:transfer("\1\2\3") == 3, "a transfer returns as many bytes as it sends")
  expect(#bus:transfer("") == 0, "an empty transfer returns nothing")
  bus:write("\0")
  bus:close()
  expect(not pcall(bus.transfer, bus, "\0"), "a closed bus refuses transfers")
  bus:close()
  print(string.format("selftest ok (%d checks)", checks))
  return
end

return M
