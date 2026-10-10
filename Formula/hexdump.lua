#!lua
-- hexdump: shows a file as hex and text. usage: hexdump FILE [BYTES]   (default 256 bytes)

local path = arg[1]
if not path then
  print("usage: hexdump FILE [BYTES]")
  return
end
local limit = tonumber(arg[2]) or 256

local data, err = fs.read(path)
if not data then
  print("hexdump: " .. path .. ": " .. tostring(err))
  return
end

local shown = data:sub(1, limit)
for offset = 0, #shown - 1, 8 do
  local hex, text = {}, {}
  for i = 1, 8 do
    local b = shown:byte(offset + i)
    if b then
      hex[#hex + 1] = string.format("%02x", b)
      text[#text + 1] = (b >= 32 and b < 127) and string.char(b) or "."
    else
      hex[#hex + 1] = "  "
    end
  end
  term.write(string.format("%04x: ", offset), "cyan")
  term.write(table.concat(hex, " ") .. " ", "text")
  term.print(table.concat(text), "dim")
end
if #data > limit then
  print(string.format("... %d more bytes (use hexdump FILE %d)", #data - limit, #data))
end
