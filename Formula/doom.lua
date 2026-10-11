#!lua
-- doom 0.1.1.1: a Doom-like shooter with pixel graphics. Walk a level, shoot the imps and demons, pick up health and ammo, and
-- clear the level. Needs firmware v0.1.0.14(beta) (the graphics in little pieces of memory) and three drivers, which brew
-- installs with it: doomlevel, doomdraw and doomgame (brew asks first).
-- Every key is a letter, so no Fn is needed, and nothing has to be held down:
--   w  walk, again for a run            s  slow down, then walk back
--   a  turn left, again for faster      d  turn right, again for faster
--   q  step left                        e  step right (the other key stops a step)
--   z  quick turn left                  c  quick turn right (for aiming)
--   f or enter  fire                    space  stop everything
--   m  the map     p  pause     ctrl-q  quit
-- doom --start skips the title. This file is only the launcher: the game is the driver doomgame, which the Cardputer keeps in
-- memory without the line numbers (driver.load with true), because the memory of the device is small.

if #arg > 0 and arg[1] ~= "--start" then
  print("usage: doom [--start]   (--start skips the title)")
  return
end
if not gfx or not gfx.depth then
  print("doom needs the graphics of firmware v0.1.0.14(beta): update with SystemUpdateBeta")
  return
end
if not driver then
  print("doom needs the driver module: update the firmware")
  return
end
local game, err = driver.load("doomgame", true)
if not game then
  print("doom: " .. tostring(err))
  print("doom: install the parts with: brew install doom")
  return
end
game.run(arg[1] == "--start")
