#!lua
-- rtc: the clock of a DS3231 real-time clock module on an I2C bus. The Cardputer has no clock of its own, so the time
-- is lost when it is switched off; the module keeps it with its battery.
--   rtc SDA SCL                             show the time the module keeps
--   rtc SDA SCL set "2026-10-11 16:30:45"   set the time
--   rtc SDA SCL sync                        set it from the network clock (WiFi needed)
-- Wire SDA and SCL to two free pins, and the module's VCC and GND to 3.3 V and GND. The module is at address 0x68.
-- Needs firmware v0.1.0.10(beta) or newer (the i2c module).

local ADDR = 0x68
local USAGE = "usage: rtc SDA SCL [set \"YYYY-MM-DD HH:MM:SS\" | sync]   e.g. rtc 1 2 sync"

if not i2c then
  print("rtc: this firmware has no I2C, update to v0.1.0.10(beta) or newer")
  return
end

local sda, scl = tonumber(arg[1] or ""), tonumber(arg[2] or "")
if not sda or not scl or sda ~= math.floor(sda) or scl ~= math.floor(scl) then
  print(USAGE)
  return
end
local action = arg[3]
if action and action ~= "set" and action ~= "sync" then
  print(USAGE)
  return
end

local function toBcd(n)
  return (n // 10) * 16 + n % 10
end

local function fromBcd(b)
  return (b >> 4) * 10 + (b & 0x0F)
end

-- the day of the week the chip counts: 1 is Monday, 7 is Sunday (Sakamoto's method, with 0 as Sunday)
local function weekday(y, m, d)
  local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
  if m < 3 then y = y - 1 end
  local w = (y + y // 4 - y // 100 + y // 400 + t[m] + d) % 7
  return w == 0 and 7 or w
end

-- the registers from 0x00: seconds, minutes, hours, day of the week, date, month and year, all in BCD
local function encode(y, mo, d, h, mi, s)
  return string.char(toBcd(s), toBcd(mi), toBcd(h), weekday(y, mo, d), toBcd(d), toBcd(mo), toBcd(y % 100))
end

local function decode(regs)
  local sec = fromBcd(regs:byte(1) & 0x7F)
  local min = fromBcd(regs:byte(2) & 0x7F)
  local hb = regs:byte(3)
  local hour
  if (hb & 0x40) ~= 0 then  -- 12-hour mode: bit 5 is PM
    hour = fromBcd(hb & 0x1F) % 12 + ((hb & 0x20) ~= 0 and 12 or 0)
  else
    hour = fromBcd(hb & 0x3F)
  end
  local day = fromBcd(regs:byte(5) & 0x3F)
  local month = fromBcd(regs:byte(6) & 0x1F)
  local year = 2000 + fromBcd(regs:byte(7))
  return string.format("%04d-%02d-%02d %02d:%02d:%02d", year, month, day, hour, min, sec)
end

-- "2026-10-11 16:30:45" as the parts of the time, or nil and the reason
local function parseTime(text)
  local y, mo, d, h, mi, s = text:match("^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d):(%d%d)$")
  if not y then return nil, "the time is YYYY-MM-DD HH:MM:SS, for example 2026-10-11 16:30:45" end
  y, mo, d, h, mi, s = tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi), tonumber(s)
  if y < 2000 or y > 2099 or mo < 1 or mo > 12 or d < 1 or d > 31 or h > 23 or mi > 59 or s > 59 then
    return nil, "the time is out of range"
  end
  return { y, mo, d, h, mi, s }
end

local bus, err = i2c.open{ sda = sda, scl = scl }
if not bus then
  print("rtc: " .. tostring(err))
  return
end

local found = false
for _, a in ipairs(bus:scan()) do
  if a == ADDR then found = true end
end
if not found then
  print(string.format("rtc: no DS3231 at 0x%02X on SDA %d, SCL %d", ADDR, sda, scl))
  bus:close()
  return
end

if not action then
  local regs = bus:writeRead(ADDR, "\0", 7)
  if #regs ~= 7 then
    print("rtc: the module gave " .. #regs .. " bytes, 7 expected")
  else
    print(decode(regs))
  end
else
  local text
  if action == "sync" then
    text = sys.date("%Y-%m-%d %H:%M:%S")
    if not text then
      print("rtc: no network clock yet (connect to WiFi first: wifi connect SSID PASS)")
      bus:close()
      return
    end
  else
    text = table.concat(arg, " ", 4)
  end
  local p, why = parseTime(text)
  if not p then
    print("rtc: " .. why)
  else
    bus:write(ADDR, "\0" .. encode(p[1], p[2], p[3], p[4], p[5], p[6]))
    print("set to " .. text)
  end
end
bus:close()
