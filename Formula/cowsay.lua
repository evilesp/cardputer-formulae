#!lua
-- cowsay: a cow says what you give it. usage: cowsay WORDS...

local WIDTH = 34

local text = table.concat(arg, " ")
if text == "" then text = "moo" end

-- word wrap
local lines, cur = {}, ""
for word in text:gmatch("%S+") do
  if cur == "" then
    cur = word
  elseif #cur + 1 + #word <= WIDTH then
    cur = cur .. " " .. word
  else
    lines[#lines + 1] = cur
    cur = word
  end
end
if cur ~= "" then lines[#lines + 1] = cur end

local longest = 0
for _, l in ipairs(lines) do
  if #l > longest then longest = #l end
end

print(" " .. string.rep("_", longest + 2))
for i, l in ipairs(lines) do
  local left, right = "<", ">"
  if #lines > 1 then
    if i == 1 then left, right = "/", "\\"
    elseif i == #lines then left, right = "\\", "/"
    else left, right = "|", "|" end
  end
  print(left .. " " .. l .. string.rep(" ", longest - #l) .. " " .. right)
end
print(" " .. string.rep("-", longest + 2))
print("        \\   ^__^")
print("         \\  (oo)\\_______")
print("            (__)\\       )\\/\\")
print("                ||----w |")
print("                ||     ||")
