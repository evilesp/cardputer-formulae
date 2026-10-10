#!lua
-- calc: evaluates an expression with math functions. usage: calc 2^10 + sqrt(144)

local expr = table.concat(arg, " ")
if expr == "" then
  print("usage: calc EXPRESSION   e.g. calc (3+4)*2 or calc sin(pi/2)")
  return
end

-- only the math library is visible to the expression
local env = {}
for name, value in pairs(math) do env[name] = value end

local chunk, err = load("return " .. expr, "=calc", "t", env)
if not chunk then
  print("calc: syntax error")
  return
end
local ok, result = pcall(chunk)
if not ok then
  print("calc: " .. tostring(result))
  return
end
if math.type(result) == "integer" then
  print(tostring(result))
else
  print(string.format("%.10g", result))
end
