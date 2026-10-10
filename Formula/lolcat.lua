#!lua
-- lolcat: prints text in rainbow colors. usage: lolcat TEXT...

local RAINBOW = { "red", "yellow", "green", "cyan", "blue", "magenta" }

local text = table.concat(arg, " ")
if text == "" then
  print("usage: lolcat TEXT...")
  return
end

local n = 0
for ch in text:gmatch(".") do
  if ch ~= " " then
    n = n + 1
    term.write(ch, RAINBOW[(n // 2) % #RAINBOW + 1])
  else
    term.write(" ", "text")
  end
end
term.print("", "text")
