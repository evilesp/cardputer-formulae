#!lua
-- natan-local-pl: ask the device in plain words, in Polish (or English), and three small language models that run on this
-- device answer. Nothing leaves it: no network, no server. For example:
--   natan-local-pl ile mam miejsca na karcie SD            -> runs df -h / and says "Masz 15 GB wolnego miejsca."
--   natan-local-pl jaka pojemność ma moja karta            -> says the size of the card
--   natan-local-pl ustaw jasność na 100                    -> sets the brightness
-- The models: natan-intent:pl (what you meant), natan-cmd:pl (writes the terminal command) and natan-reply:pl (reads what it
-- printed and answers). They are pulled once: ollama pull natan-intent:pl natan-cmd:pl natan-reply:pl. The commands are
-- limited (reading files and settings; one that changes files asks first). Needs the llm module and sys.run of the firmware.

if #arg == 0 then
  print("usage: natan-local-pl PYTANIE...   (np. natan-local-pl ile mam miejsca na karcie SD)")
  return
end
if not llm or not sys.run or not driver then
  print("natan-local-pl needs the llm module and sys.run of the firmware: update with SystemUpdateBeta")
  return
end
local nl, err = driver.load("natanlocal")
if not nl then
  print("natan-local-pl needs the driver natanlocal: " .. tostring(err))
  return
end
local missing = nl.missing()
if #missing > 0 then
  print("the models are not here yet; pull them once:")
  print("  ollama pull " .. table.concat(missing, " "))
  return
end
local ok, reason = nl.ask(table.concat(arg, " "))
if not ok and reason and reason ~= "denied" and reason ~= "cancelled" and not reason:match("^intent") and not reason:match("^cmd") and not reason:match("^reply") then
  print("natan-local-pl: " .. tostring(reason))
end
