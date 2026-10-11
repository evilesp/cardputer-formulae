#!lua
-- i2cscan: lists the devices that answer on an I2C bus. Give two free pins for the bus (the Cardputer's own keyboard bus
-- is not offered). Needs firmware v0.1.0.10(beta) or newer.
--   i2cscan SDA SCL [CLOCK]       e.g. i2cscan 1 2     (CLOCK in Hz, 100000 by default)
-- The names are the usual parts for each address; the datasheet of your part tells the rest.

local NAMES = {
  [0x24] = "PN532 NFC reader",
  [0x3c] = "OLED display (SSD1306)",
  [0x3d] = "OLED display (SSD1306)",
  [0x50] = "EEPROM (AT24)",
  [0x51] = "clock (PCF8563)",
  [0x53] = "NFC tag (ST25DV)",
  [0x68] = "clock or motion sensor (DS1307, MPU6050)",
  [0x76] = "BME280 or BMP280 sensor",
  [0x77] = "BME280 or BMP280 sensor",
}

if not i2c then
  print("i2cscan: this firmware has no I2C, update to v0.1.0.10(beta) or newer")
  return
end

local sda, scl = tonumber(arg[1] or ""), tonumber(arg[2] or "")
local clock = tonumber(arg[3] or "") or 100000
if not sda or not scl or sda ~= math.floor(sda) or scl ~= math.floor(scl) then
  print("usage: i2cscan SDA SCL [CLOCK]   e.g. i2cscan 1 2")
  return
end

local bus, err = i2c.open{ sda = math.floor(sda), scl = math.floor(scl), clock = math.floor(clock) }
if not bus then
  print("i2cscan: " .. tostring(err))
  return
end
local found = bus:scan()
bus:close()

if #found == 0 then
  print("no device answers")
  return
end
for _, addr in ipairs(found) do
  print(string.format("0x%02x  %s", addr, NAMES[addr] or ""))
end
