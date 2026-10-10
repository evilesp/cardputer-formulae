#!lua
-- base64: encodes or decodes text. usage: base64 [-d] TEXT...   or   base64 [-d] -f FILE

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function encode(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = (a << 16) | ((b or 0) << 8) | (c or 0)
    local chunk = {}
    for k = 3, 0, -1 do
      local idx = (n >> (6 * k)) & 63
      chunk[#chunk + 1] = ALPHABET:sub(idx + 1, idx + 1)
    end
    if not b then chunk[3], chunk[4] = "=", "=" elseif not c then chunk[4] = "=" end
    out[#out + 1] = table.concat(chunk)
  end
  return table.concat(out)
end

local function decode(s)
  s = s:gsub("[^%w%+/=]", "")
  local out, bits, nbits = {}, 0, 0
  for ch in s:gmatch(".") do
    if ch == "=" then break end
    local v = ALPHABET:find(ch, 1, true) - 1
    bits = ((bits << 6) | v) & 0xffffff
    nbits = nbits + 6
    if nbits >= 8 then
      nbits = nbits - 8
      out[#out + 1] = string.char((bits >> nbits) & 0xff)
    end
  end
  return table.concat(out)
end

local decodeMode = false
local fileName
local words = {}
local i = 1
while arg[i] do
  if arg[i] == "-d" then decodeMode = true
  elseif arg[i] == "-f" then fileName = arg[i + 1]; i = i + 1
  else words[#words + 1] = arg[i] end
  i = i + 1
end

local input
if fileName then
  local data, err = fs.read(fileName)
  if not data then
    print("base64: " .. fileName .. ": " .. tostring(err))
    return
  end
  input = data
else
  input = table.concat(words, " ")
end

if input == "" then
  print("usage: base64 [-d] TEXT...  or  base64 [-d] -f FILE")
  return
end
print(decodeMode and decode(input) or encode(input))
