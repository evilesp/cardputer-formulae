#!lua
-- deepSleep: puts the Cardputer into deep sleep. The screen goes dark and the processor stops: a key or the BOOT (G0)
-- button wakes it, and it starts again from the beginning. The step counter does not count while it sleeps.
-- Needs firmware v0.1.0.18(beta) or newer.

if not sys.deepSleep then
  print("deepSleep needs firmware v0.1.0.18(beta) or newer: SystemBackUpdate")
  return
end
print("Deep sleep. A key or BOOT (G0) wakes the Cardputer up.")
sys.deepSleep()
