#!lua
-- cowsay: a cow (or another animal) says your words, like cowsay 3.8.
-- usage: cowsay [-bdgpstwy] [-h] [-e eyes] [-f cowfile] [-l] [-n] [-T tongue] [-W wrapcolumn] [message]

local USAGE = "Usage: cowsay [-bdgpstwy] [-h] [-e eyes] [-f cowfile]\n          [-l] [-n] [-T tongue] [-W wrapcolumn] [message]"

local COWS = {
  default = {
    "        $t   ^__^",
    "         $t  ($e)\\_______",
    "            (__)\\       )\\/\\",
    "             $o ||----w |",
    "                ||     ||",
  },
  tux = {
    "   $t",
    "    $t",
    "        .--.",
    "       |o_o |",
    "       |:_/ |",
    "      //   \\ \\",
    "     (|     | )",
    "    /'\\_   _/`\\",
    "    \\___)=(___/",
  },
  small = {
    "        $t   ,__,",
    "         $t  ($e)____",
    "            (__)    )\\",
    "             $o ||--|| *",
  },
}

local function fail(msg, code)
  io.stderr:write(msg .. "\n")
  os.exit(code)
end

local eyes, tongue = "oo", "  "
local cow, wrap, nowrap, think = "default", 40, false, false
-- the program may be started as cowthink: not available here, kept for the balloon style
local words = {}
local i = 1
while arg[i] do
  local a = arg[i]
  if a == "--" then
    for k = i + 1, #arg do words[#words + 1] = arg[k] end
    break
  elseif a:sub(1, 1) == "-" and #a > 1 then
    local j = 2
    while j <= #a do
      local o = a:sub(j, j)
      if o == "b" then eyes = "=="
      elseif o == "d" then eyes, tongue = "xx", "U "
      elseif o == "g" then eyes = "$$"
      elseif o == "p" then eyes = "@@"
      elseif o == "s" then eyes, tongue = "**", "U "
      elseif o == "t" then eyes = "--"
      elseif o == "w" then eyes = "OO"
      elseif o == "y" then eyes = ".."
      elseif o == "n" then nowrap = true
      elseif o == "h" then
        print(USAGE)
        return
      elseif o == "l" then
        print("Cow files in /usr/share/cows:")
        print("default small tux")
        return
      elseif o == "e" or o == "T" or o == "f" or o == "W" then
        local val = a:sub(j + 1)
        if val == "" then
          i = i + 1
          val = arg[i]
        end
        if not val then
          io.stderr:write("Option " .. o .. " requires an argument\n")
          fail(USAGE, 1)
        end
        if o == "e" then eyes = (val .. "  "):sub(1, 2)
        elseif o == "T" then tongue = (val .. "  "):sub(1, 2)
        elseif o == "f" then cow = val
        else
          wrap = tonumber(val) or 40
          if wrap < 3 then wrap = 3 end
        end
        j = #a
      else
        io.stderr:write("Unknown option: " .. o .. "\n")
        fail(USAGE, 1)
      end
      j = j + 1
    end
  else
    words[#words + 1] = a
  end
  i = i + 1
end

local art = COWS[(cow:gsub("%.cow$", ""):gsub("^.*/", ""))]
if not art then fail("cowsay: Could not find " .. cow .. " cowfile!", 255) end

-- the message: the words, or what is piped in
local text
if #words > 0 then
  text = table.concat(words, " ")
elseif sys.piped then
  text = io.read("a") or ""
else
  text = ""
end

-- like Text::Wrap: lines are cut at blanks, a word that is too long is cut in pieces
local limit = wrap - 2
local lines = {}
local function addLine(l) lines[#lines + 1] = l end
for para in (text:gsub("\t", "        "):gsub("\n$", "") .. "\n"):gmatch("(.-)\n") do
  if nowrap then
    addLine(para)
  else
    local cur = ""
    for word in para:gmatch("%S+") do
      while #word > limit do
        if cur ~= "" then addLine(cur); cur = "" end
        addLine(word:sub(1, limit))
        word = word:sub(limit + 1)
      end
      if cur == "" then cur = word
      elseif #cur + 1 + #word <= limit then cur = cur .. " " .. word
      else addLine(cur); cur = word end
    end
    addLine(cur)
  end
end
if #lines == 0 then lines[1] = "" end

local max = 0
for _, l in ipairs(lines) do if #l > max then max = #l end end

print(" " .. string.rep("_", max + 2))
for n, l in ipairs(lines) do
  local left, right = "<", ">"
  if #lines > 1 then
    if n == 1 then left, right = "/", "\\"
    elseif n == #lines then left, right = "\\", "/"
    else left, right = "|", "|" end
  end
  print(left .. " " .. l .. string.rep(" ", max - #l) .. " " .. right)
end
print(" " .. string.rep("-", max + 2))
for _, row in ipairs(art) do
  print((row:gsub("%$t", "\\"):gsub("%$e", function() return eyes end):gsub("%$o", function() return tongue end)))
end
