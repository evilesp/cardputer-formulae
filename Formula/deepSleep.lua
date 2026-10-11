#!lua
-- deepSleep: puts the Cardputer into deep sleep. The screen goes dark and the processor stops: a key or the BOOT (G0)
-- button wakes it, and it starts again from the beginning. The step counter does not count while it sleeps. If a key is
-- still held (or its release has not been read yet), the Cardputer stays awake, because that key would wake it at once.
-- Needs firmware v0.1.0.19(beta) or newer.

if not sys.deepSleep then
  print("deepSleep needs firmware v0.1.0.19(beta) or newer: SystemBackUpdate")
  return
end
local ok, err = pcall(sys.deepSleep)
if not ok then print("deepSleep: " .. tostring(err)) end
