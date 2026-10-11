#!lua
-- off: switches the Cardputer off. The battery is disconnected where the board allows it; otherwise the Cardputer goes to
-- deep sleep, and only BOOT (G0) wakes it. The step counter's log is saved first.
-- Needs firmware v0.1.0.18(beta) or newer.

if not sys.powerOff then
  print("off needs firmware v0.1.0.18(beta) or newer: SystemBackUpdate")
  return
end
print("Switching off. BOOT (G0) or the power switch turns it on again.")
sys.powerOff()
