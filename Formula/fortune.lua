#!lua
-- fortune: prints a random saying, like BSD fortune-mod.
-- usage: fortune [-acefilosw] [-n length] [ -m pattern] [[#%] file/dir/all]

local USAGE = "Usage: fortune [-acefilosw] [-n length] [ -m pattern] [[#%] file/dir/all]"

-- classic public-domain sayings and short pieces of advice written for this package
local F = {
  "Beware of bugs in the above code; I have only proved it correct, not tried it.\n\t\t-- Donald Knuth",
  "Premature optimization is the root of all evil.\n\t\t-- Donald Knuth",
  "Simplicity is prerequisite for reliability.\n\t\t-- Edsger W. Dijkstra",
  "There are only two hard things in computer science: cache invalidation and naming things.",
  "A journey of a thousand miles begins with a single step.\n\t\t-- Lao Tzu",
  "The best way to predict the future is to invent it.\n\t\t-- Alan Kay",
  "If at first you don't succeed, try again. Then quit. There's no use being a damn fool about it.\n\t\t-- W. C. Fields",
  "Measure twice, cut once.",
  "Debugging is twice as hard as writing the code in the first place. Therefore, if you write the code as cleverly as possible, you are, by definition, not smart enough to debug it.\n\t\t-- Brian W. Kernighan",
  "Keep it simple, stupid.",
  "Talk is cheap. Show me the code.\n\t\t-- Linus Torvalds",
  "Unix is simple. It just takes a genius to understand its simplicity.\n\t\t-- Dennis Ritchie",
  "Make it work, make it right, make it fast.\n\t\t-- Kent Beck",
  "The only way to learn a new programming language is by writing programs in it.\n\t\t-- Dennis Ritchie",
  "Early to bed and early to rise makes a man healthy, wealthy and wise.\n\t\t-- Benjamin Franklin",
  "Well done is better than well said.\n\t\t-- Benjamin Franklin",
  "An investment in knowledge pays the best interest.\n\t\t-- Benjamin Franklin",
  "We must all hang together, or assuredly we shall all hang separately.\n\t\t-- Benjamin Franklin",
  "The unexamined life is not worth living.\n\t\t-- Socrates",
  "I think, therefore I am.\n\t\t-- Rene Descartes",
  "Fall seven times, stand up eight.\n\t\t-- Japanese proverb",
  "He who laughs last has not yet heard the bad news.",
  "Never put off until tomorrow what you can avoid altogether.",
  "A watched pot never boils.",
  "The early bird gets the worm, but the second mouse gets the cheese.",
  "Good, fast, cheap: pick any two.",
  "If it ain't broke, don't fix it.",
  "Read the error message. All of it. The answer is often in the middle.",
  "The best time to back up your SD card was yesterday.",
  "Commit early, commit often, and read the diff before you push.",
  "A bug that reproduces every time is a gift. Enjoy it briefly.",
  "Measure first. Your guess about the slow part is probably wrong.",
  "Short functions are easy to test. Long ones are easy to forget.",
  "Name things for what they do, not for how they are built.",
  "Every program is a list of decisions. Write the reasons down.",
  "Simple solutions age better than clever ones.",
  "Take a walk. The problem will still be there, and so will you, refreshed.",
  "To err is human; to really foul things up requires a computer.",
  "Software is like entropy: it is difficult to grasp, weighs nothing, and obeys the Second Law of Thermodynamics; i.e., it always increases.\n\t\t-- Norman Augustine",
  "The first 90 percent of the code accounts for the first 90 percent of the development time. The remaining 10 percent of the code accounts for the other 90 percent of the development time.\n\t\t-- Tom Cargill",
}

local only, short, long, all, minLen, showFile, pattern = nil, false, false, false, 160, false, nil
local i = 1
while arg[i] do
  local a = arg[i]
  if a:sub(1, 1) == "-" and #a > 1 then
    local j = 2
    while j <= #a do
      local o = a:sub(j, j)
      if o == "s" then short = true
      elseif o == "l" then long = true
      elseif o == "a" or o == "o" or o == "e" or o == "i" or o == "w" then
        -- offensive and equal-size options: one small list, so nothing changes
      elseif o == "c" then showFile = true
      elseif o == "f" then only = "f"
      elseif o == "n" or o == "m" then
        local val = a:sub(j + 1)
        if val == "" then
          i = i + 1
          val = arg[i]
        end
        if not val then
          io.stderr:write("fortune: option requires an argument -- '" .. o .. "'\n")
          io.stderr:write(USAGE .. "\n")
          os.exit(1)
        end
        if o == "n" then
          minLen = tonumber(val)
          if not minLen then
            io.stderr:write("fortune: invalid number: " .. val .. "\n")
            os.exit(1)
          end
        else pattern = val end
        j = #a
      else
        io.stderr:write("fortune: invalid option -- '" .. o .. "'\n")
        io.stderr:write(USAGE .. "\n")
        os.exit(1)
      end
      j = j + 1
    end
  end
  i = i + 1
end

if only == "f" then
  print("100.00% /usr/share/fortune")
  print("    100.00% fortunes")
  return
end

local pool = {}
for _, t in ipairs(F) do
  local body = t:gsub("\n.*$", "")
  local isShort = #body < minLen
  if (not short and not long or (short and isShort) or (long and not isShort))
     and (not pattern or t:lower():find(pattern:lower(), 1, true)) then
    pool[#pool + 1] = t
  end
end
if #pool == 0 then
  io.stderr:write("No fortunes found\n")
  os.exit(1)
end

if showFile then print("(fortunes)") print("%") end
math.randomseed(sys.millis and sys.millis() or os.time())
local text = pool[math.random(#pool)]
-- the screen is 57 columns wide: wrap the saying, keep the author line as it is
local body, rest = text:match("^(.-)(\n.*)$")
body = body or text
local cur = ""
for word in body:gmatch("%S+") do
  if cur == "" then cur = word
  elseif #cur + 1 + #word <= 56 then cur = cur .. " " .. word
  else print(cur); cur = word end
end
if cur ~= "" then print(cur) end
if rest then print((rest:gsub("^\n", ""))) end
