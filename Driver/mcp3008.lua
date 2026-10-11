#!lua
-- mcp3008: a driver for the MCP3008 analogue-to-digital converter: 8 inputs (channels 0 to 7), 10 bits (0 to 1023).
-- It works on any bus with transfer(text): the spi module of the firmware and the softspi driver both do.
--   local mcp3008 = driver.load("mcp3008")
--   local softspi = driver.load("softspi")
--   local adc = mcp3008.open(softspi.open{ sck = 1, mosi = 2, miso = 3, cs = 4 })
--   adc:read(0)          -- 0 to 1023
--   adc:volts(0, 3.3)    -- volts, when the chip's VREF pin is at 3.3 V
-- Wiring: CLK to sck, DIN to mosi, DOUT to miso, CS to cs (plus VDD, VREF, AGND and DGND). The chip's logic and VREF
-- levels must match the Cardputer's pins, so 3.3 V is the safe choice.
-- Run it as a script with --selftest to check the protocol with a fake bus.

local M = {}

local Adc = {}
Adc.__index = Adc

function M.open(bus)
  if type(bus) ~= "table" or type(bus.transfer) ~= "function" then
    error("mcp3008.open needs a bus with transfer(text), from spi.open or softspi.open", 2)
  end
  return setmetatable({ bus = bus }, Adc)
end

local function channelArg(channel)
  if math.type(channel) ~= "integer" or channel < 0 or channel > 7 then
    error("the MCP3008 channels are 0 to 7", 3)
  end
  return channel
end

-- A conversion sends three bytes: the start bit; single-ended mode and the channel; nothing. The reply holds the
-- 10 result bits in its last ten positions: the two high bits are the low bits of the second byte.
function Adc:read(channel)
  local ch = channelArg(channel)
  local reply = self.bus:transfer(string.char(0x01, 0x80 | (ch << 4), 0x00))
  if #reply ~= 3 then error("mcp3008: the bus returned " .. #reply .. " bytes, 3 expected", 2) end
  return ((reply:byte(2) & 0x03) << 8) | reply:byte(3)
end

function Adc:volts(channel, vref)
  if type(vref) ~= "number" or vref <= 0 then error("volts needs the reference voltage, for example 3.3", 2) end
  return self:read(channel) * vref / 1023
end

if arg and arg[1] == "--selftest" then
  local checks = 0
  local function expect(cond, what)
    checks = checks + 1
    if not cond then error("check " .. checks .. ": " .. what) end
  end
  -- a fake bus: it records what was sent and gives back the reply it is told to
  local bus = {}
  function bus.transfer(self, text)
    self.sent = text
    return self.reply
  end
  local adc = M.open(bus)
  bus.reply = "\0\2\171"  -- 0x2AB = 683
  expect(adc:read(0) == 683, "0x2AB reads as 683")
  expect(bus.sent == "\1\128\0", "channel 0 sends 01 80 00")
  bus.reply = "\255\255\255"  -- the first byte is ignored
  expect(adc:read(7) == 1023, "the top value reads as 1023")
  expect(bus.sent == "\1\240\0", "channel 7 sends 01 f0 00")
  bus.reply = "\0\0\0"
  expect(adc:read(3) == 0, "zero reads as 0")
  expect(bus.sent == "\1\176\0", "channel 3 sends 01 b0 00")
  expect(not pcall(adc.read, adc, 8), "channel 8 is refused")
  expect(not pcall(adc.read, adc, 1.5), "a channel must be a whole number")
  bus.reply = "\0\0"
  expect(not pcall(adc.read, adc, 0), "a short reply is an error")
  bus.reply = "\0\2\171"
  expect(math.abs(adc:volts(0, 3.3) - 683 * 3.3 / 1023) < 1e-9, "volts is code times vref over 1023")
  expect(not pcall(adc.volts, adc, 0, 0), "a zero reference is refused")
  expect(not pcall(M.open, {}), "a bus without transfer is refused")
  print(string.format("selftest ok (%d checks)", checks))
  return
end

return M
