#!lua
-- fortune: a random line of advice for the day.

local FORTUNES = {
  "Commit early, commit often, and read the diff before you push.",
  "A bug that reproduces every time is a gift. Enjoy it briefly.",
  "The best time to back up your SD card was yesterday.",
  "Measure first. Your guess about the slow part is probably wrong.",
  "Short functions are easy to test. Long ones are easy to forget.",
  "Read the error message. All of it. The answer is often in the middle.",
  "Take a walk. The problem will still be there, and so will you, refreshed.",
  "Name things for what they do, not for how they are built.",
  "Every program is a list of decisions. Write the reasons down.",
  "Simple solutions age better than clever ones.",
  "Ask the device to show you its state before you assume it.",
  "Good tests describe behavior, not implementation details.",
}

local WIDTH = 36

local text = FORTUNES[math.random(#FORTUNES)]
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

print("")
for _, l in ipairs(lines) do
  print("  " .. l)
end
print("")
