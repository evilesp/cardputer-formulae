#!lua
-- GamePerformance: more memory for games and animations. The WiFi driver takes 40 to 50 KB of the Cardputer's memory; with
-- GamePerformance the radio is off while you play, and when the game ends the WiFi comes back and connects in the background
-- (you can go on working). A program that needs the network brings the WiFi back by itself.
-- usage: GamePerformance on       from now until "off" (or a restart)
--        GamePerformance off      never (the WiFi stays as it is)
--        GamePerformance auto     by itself whenever a game or an animation opens the screen (kept over a restart)
--        GamePerformance          shows the mode and the free memory
-- Needs firmware v0.1.0.23(beta). Run it with --selftest to check the arguments.

local MODES = { on = true, off = true, auto = true }

-- the mode asked for, or nil for "show"; false when the argument is not a mode
local function modeOf(a)
  if a == nil or a == "" or a == "status" then return nil end
  a = a:lower()
  if MODES[a] then return a end
  return false
end

local EXPLAIN = {
  on = "on: the WiFi is off until GamePerformance off",
  off = "off: games run with the WiFi as it is",
  auto = "auto: the WiFi goes off while a game or an animation runs, and comes back after it",
}

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(modeOf("on") == "on" and modeOf("AUTO") == "auto" and modeOf("off") == "off", "the three modes")
  check(modeOf(nil) == nil and modeOf("status") == nil, "no argument shows the mode")
  check(modeOf("fast") == false, "an unknown mode is refused")
  if failed == 0 then print("selftest ok") end
  return
end

if not sys.performance then
  print("GamePerformance needs firmware v0.1.0.23(beta) or newer: SystemUpdateBeta")
  return
end

local want = modeOf(arg[1])
if want == false then
  print("usage: GamePerformance [on|off|auto]")
  return
end

local before = select(3, sys.performance())
local ok, mode, active, free, block = pcall(sys.performance, want)
if not ok then
  print("GamePerformance: " .. tostring(mode))
  return
end
print("GamePerformance " .. mode .. (active and " (active now: the WiFi is off)" or ""))
print(EXPLAIN[mode])
if want == "on" and free > before then
  print(string.format("free memory %d KB (was %d KB), largest block %d KB", free, before, block))
elseif want == "off" then
  print("the WiFi comes back in the background when it was on")
else
  print(string.format("free memory %d KB, largest block %d KB", free, block))
end
