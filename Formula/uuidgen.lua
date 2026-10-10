#!lua
-- uuidgen: prints a random UUID (version 4). usage: uuidgen [COUNT]

local count = tonumber(arg[1]) or 1

for _ = 1, count do
  local out = {}
  for i = 1, 32 do
    local v
    if i == 13 then v = 4              -- version nibble
    elseif i == 17 then v = math.random(8, 11)  -- variant bits 10xx
    else v = math.random(0, 15) end
    out[i] = string.format("%X", v)
  end
  local s = table.concat(out)
  print(string.format("%s-%s-%s-%s-%s", s:sub(1, 8), s:sub(9, 12), s:sub(13, 16), s:sub(17, 20), s:sub(21, 32)))
end
