#!lua
-- functionplot: draws a function y = f(x). Type the expression with x in it, for example sin(x), x*x - 2, sqrt(abs(x)),
-- or exp(-x*x). Functions: sin cos tan asin acos atan exp log sqrt abs floor ceil min max, and the number pi. e changes the
-- expression, + and - zoom in and out, w a s d move the picture, r resets it, ctrl-q quits. Needs the graphics and the ui
-- package. Run it with --selftest to check the expressions.

local W, H = 240, 135
local TOP, BOTTOM = 14, 124

local ENV = {
  sin = math.sin, cos = math.cos, tan = math.tan, asin = math.asin, acos = math.acos, atan = math.atan,
  exp = math.exp, log = math.log, sqrt = math.sqrt, abs = math.abs, floor = math.floor, ceil = math.ceil,
  min = math.min, max = math.max, pi = math.pi,
}

-- the function of x for an expression, or nil and the reason it is not a function
local function compile(expr)
  local f, err = load("local x = ... return " .. expr, "expression", "t", ENV)
  if not f then return nil, err end
  -- a trial run: an expression that fails for x = 1 is refused
  local ok, v = pcall(f, 1)
  if not ok then return nil, tostring(v) end
  return function(x)
    local ok2, y = pcall(f, x)
    if ok2 and type(y) == "number" then return y end
    return nil
  end
end

-- the values of f at n points from x0 to x1 (nil where it is not a number)
local function sample(f, x0, x1, n)
  local out = {}
  for i = 0, n - 1 do
    local x = x0 + (x1 - x0) * i / (n - 1)
    out[i + 1] = f(x)
  end
  return out
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  local sq = compile("x*x")
  check(sq ~= nil and sq(3) == 9 and sq(-2) == 4, "x*x")
  local sn = compile("sin(x)")
  check(sn ~= nil and math.abs(sn(math.pi / 2) - 1) < 1e-9, "sin(x)")
  local bad = compile("x +")
  check(bad == nil, "a broken expression is refused")
  local nosys = compile("os.exit()")
  check(nosys == nil, "the system is not reachable from an expression")
  local pts = sample(sq, -2, 2, 5)
  check(#pts == 5 and pts[1] == 4 and pts[3] == 0 and pts[5] == 4, "sampling a function")
  local div = compile("1/x")
  check(div ~= nil and (div(0) == nil or div(0) == math.huge), "a division by zero is no point or infinity, never a number on the screen")
  if failed == 0 then print("selftest ok") end
  return
end

if not gfx then
  print("functionplot needs the graphics of firmware v0.1.0.13: SystemUpdateBeta")
  return
end
local ui, uiErr = driver.load("ui", true)
if not ui then
  print("functionplot: " .. tostring(uiErr))
  return
end

local expr = "sin(x)"
local f, why = compile(expr)
local cx, zoom = 0, 1.0      -- the middle of the picture and the scale: a unit of x is 24 pixels at zoom 1

local function draw()
  gfx.clear(0x0a0c14)
  local px = 24 * zoom
  local x0 = cx - (W / 2) / px
  local x1 = cx + (W / 2) / px
  local y0 = (TOP + BOTTOM) / 2
  gfx.hline(0, W - 1, math.floor(y0), 0x3a4260)
  gfx.vline(math.floor(W / 2 - cx * px), TOP, BOTTOM, 0x3a4260)
  if f then
    local prevX, prevY
    for sx = 0, W - 1 do
      local x = x0 + sx / px
      local y = f(x)
      if y then
        local sy = math.floor(y0 - y * px + 0.5)
        if sy >= TOP - 40 and sy <= BOTTOM + 40 then
          if prevX then gfx.line(prevX, prevY, sx, sy, 0x60c8ff) end
          prevX, prevY = sx, sy
        else
          prevX = nil
        end
      else
        prevX = nil
      end
    end
  end
  ui.label(4, 2, "y = " .. expr:sub(1, 26), f and 0xe8ecf4 or 0xff6060)
  ui.label(4, H - 10, f and "e edit   + - zoom   w a s d move   r reset   ctrl-q" or (why or "not a function"), f and 0x8a94aa or 0xff6060)
  gfx.flush()
end

local w, h = ui.open()
if not w then
  print("functionplot: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  draw()
  while true do
    local k = key.poll()
    while k do
      if k == "ctrl-q" then return end
      if k == "e" then
        local text = ui.prompt("y = (x is the variable)", expr, 40)
        if text and text ~= "" then
          local g, err = compile(text)
          expr = text
          f, why = g, err
        end
      elseif k == "+" or k == "=" then zoom = math.min(16, zoom * 1.25)
      elseif k == "-" then zoom = math.max(0.1, zoom / 1.25)
      elseif k == "a" then cx = cx - 1 / zoom
      elseif k == "d" then cx = cx + 1 / zoom
      elseif k == "r" then cx, zoom = 0, 1.0
      end
      k = key.poll()
    end
    draw()
    sys.sleep(60)
  end
end)
ui.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("functionplot: " .. tostring(problem)) end
