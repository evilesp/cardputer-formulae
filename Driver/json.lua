#!lua
-- json: reads JSON text for the apps (brew installs it as a driver: driver.load("json")). json.decode(text) gives tables:
-- objects have string keys, arrays are lists (1 is the first), numbers are numbers, true and false are booleans, null is nil.
-- It returns nil and the reason for text that is not JSON. Kept small, for the memory of the Cardputer: a text is read once.

local json = {}

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function utf8char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F)) end
  return string.char(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
end

function json.decode(text)
  local pos = 1
  local readValue

  local function fail(msg)
    error({ json = msg .. " at " .. tostring(pos) }, 0)
  end

  local function skip()
    pos = text:find("[^ \t\r\n]", pos) or (#text + 1)
  end

  local function readString()
    local parts = {}
    pos = pos + 1
    while true do
      local stop = text:find('["\\]', pos)
      if not stop then fail("unfinished text") end
      parts[#parts + 1] = text:sub(pos, stop - 1)
      if text:sub(stop, stop) == '"' then
        pos = stop + 1
        break
      end
      local e = text:sub(stop + 1, stop + 1)
      if e == "u" then
        local cp = tonumber(text:sub(stop + 2, stop + 5), 16)
        if not cp then fail("bad escape") end
        pos = stop + 6
        parts[#parts + 1] = utf8char(cp)
      elseif ESCAPES[e] then
        parts[#parts + 1] = ESCAPES[e]
        pos = stop + 2
      else
        fail("bad escape")
      end
    end
    return table.concat(parts)
  end

  readValue = function()
    skip()
    local ch = text:sub(pos, pos)
    if ch == "{" then
      pos = pos + 1
      local obj = {}
      skip()
      if text:sub(pos, pos) == "}" then
        pos = pos + 1
        return obj
      end
      while true do
        skip()
        if text:sub(pos, pos) ~= '"' then fail("a key must be a string") end
        local key = readString()
        skip()
        if text:sub(pos, pos) ~= ":" then fail("colon expected") end
        pos = pos + 1
        obj[key] = readValue()
        skip()
        local sep = text:sub(pos, pos)
        pos = pos + 1
        if sep == "}" then return obj end
        if sep ~= "," then fail("comma or } expected") end
      end
    elseif ch == "[" then
      pos = pos + 1
      local list = {}
      skip()
      if text:sub(pos, pos) == "]" then
        pos = pos + 1
        return list
      end
      while true do
        list[#list + 1] = readValue()
        skip()
        local sep = text:sub(pos, pos)
        pos = pos + 1
        if sep == "]" then return list end
        if sep ~= "," then fail("comma or ] expected") end
      end
    elseif ch == '"' then
      return readString()
    elseif text:sub(pos, pos + 3) == "true" then
      pos = pos + 4
      return true
    elseif text:sub(pos, pos + 4) == "false" then
      pos = pos + 5
      return false
    elseif text:sub(pos, pos + 3) == "null" then
      pos = pos + 4
      return nil
    else
      local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not num or num == "" then fail("a value expected") end
      pos = pos + #num
      return tonumber(num)
    end
  end

  local ok, result = pcall(readValue)
  if not ok then
    if type(result) == "table" and result.json then return nil, result.json end
    return nil, tostring(result)
  end
  return result
end

return json
