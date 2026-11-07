#!lua
-- touchcal: calibrates the touch screen. Touch the middle of each of the four crosses with a fingertip and hold it a moment;
-- the program works out how far the touch is off (shift and scale of each axis) and saves it in /etc/touch.cal, which the
-- firmware reads at start. touchcal reset removes the calibration, ctrl-q quits without saving. Needs firmware v0.1.5.
-- Run it with --selftest to check the calculation.

-- the least squares line target = scale * raw + shift through the points { raw, target }
local function fitLine(points)
  local n, sx, sy, sxx, sxy = #points, 0, 0, 0, 0
  for _, p in ipairs(points) do
    sx, sy, sxx, sxy = sx + p[1], sy + p[2], sxx + p[1] * p[1], sxy + p[1] * p[2]
  end
  local den = n * sxx - sx * sx
  if n < 2 or math.abs(den) < 1e-6 then return nil end
  local scale = (n * sxy - sx * sy) / den
  return scale, (sy - scale * sx) / n
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  -- a touch that lands 20 pixels low and a little stretched
  local pts = {}
  for _, t in ipairs({ 60, 200, 400, 740 }) do pts[#pts + 1] = { t * 1.02 + 20, t } end
  local a, c = fitLine(pts)
  check(a and math.abs(a - 1 / 1.02) < 1e-6 and math.abs(a * (300 * 1.02 + 20) + c - 300) < 1e-6, "scale and shift are found")
  a, c = fitLine({ { 5, 5 }, { 5, 9 } })
  check(a == nil, "points on one raw value give no line")
  a, c = fitLine({ { 10, 10 }, { 100, 100 } })
  check(math.abs(a - 1) < 1e-9 and math.abs(c) < 1e-9, "a right touch gives the identity")
  if failed == 0 then print("selftest ok") end
  return
end

if not (touch and touch.raw and touch.calibrate) then
  print("touchcal needs firmware v0.1.5(beta): update with SystemUpdateBeta")
  return
end
local FILE = "/etc/touch.cal"
if arg[1] == "reset" then
  touch.calibrate()
  if fs and fs.write then pcall(fs.write, FILE, "1 0 0 0 1 0\n") end  -- an identity file: /etc cannot be removed from Lua
  print("touch calibration removed")
  return
end
if not gfx then
  print("touchcal needs the graphics: SystemUpdateBeta")
  return
end

local w, h = gfx.open("native")
if not w then
  print("touchcal: " .. tostring(h))
  return
end
local ok, problem = pcall(function()
  touch.calibrate()  -- measure without an old calibration (raw ignores it, but the result replaces it)
  local m = 60
  local targets = { { m, m }, { w - m, m }, { w - m, h - m }, { m, h - m } }
  local samples = {}
  local function cross(x, y, colour)
    gfx.hline(x - 24, x + 24, y, colour)
    gfx.vline(x, y - 24, y + 24, colour)
    gfx.disc(x, y, 5, colour)
  end
  local function screen(i, message)
    gfx.clear(0x10131c)
    gfx.text(w // 2 - #"Touch calibration" * 9, h // 2 - 40, "Touch calibration", 0xe8ecf4, 3)
    gfx.text(w // 2 - #message * 6, h // 2 + 10, message, 0x8a94aa, 2)
    for k, t in ipairs(targets) do cross(t[1], t[2], k == i and 0x3cc878 or 0x3a4256) end
    gfx.flush()
  end
  for i, t in ipairs(targets) do
    screen(i, "touch the green cross (" .. i .. "/4)")
    -- wait for a finger, take the mean of its readings, wait for it to lift
    local sx, sy, n = 0, 0, 0
    while true do
      local k = key.poll()
      while k do
        if k == "ctrl-q" then return end
        k = key.poll()
      end
      local x, y = touch.raw()
      if x then
        sx, sy, n = sx + x, sy + y, n + 1
      elseif n > 0 then
        break
      end
      sys.sleep(15)
    end
    if n < 3 then screen(i, "too short, try again"); sys.sleep(700); return "again" end
    samples[i] = { sx / n, sy / n }
  end
  local ax, cx = fitLine({ { samples[1][1], targets[1][1] }, { samples[2][1], targets[2][1] }, { samples[3][1], targets[3][1] }, { samples[4][1], targets[4][1] } })
  local ay, cy = fitLine({ { samples[1][2], targets[1][2] }, { samples[2][2], targets[2][2] }, { samples[3][2], targets[3][2] }, { samples[4][2], targets[4][2] } })
  if not (ax and ay) then screen(0, "the readings do not differ"); sys.sleep(1500); return end
  local good, why = touch.calibrate(ax, 0, cx, 0, ay, cy)
  if not good then screen(0, "refused: " .. tostring(why)); sys.sleep(2500); return end
  local text = string.format("%.5f 0 %.2f 0 %.5f %.2f\n", ax, cx, ay, cy)
  local saved = false
  if fs and fs.write then
    local wrote, res = pcall(fs.write, FILE, text)
    saved = wrote and res ~= nil
  end
  screen(0, saved and "saved, touch is calibrated" or "calibrated until reboot (cannot write " .. FILE .. ")")
  sys.sleep(1800)
end)
gfx.close()
if not ok and not tostring(problem):find("interrupted", 1, true) then print("touchcal: " .. tostring(problem)) end
