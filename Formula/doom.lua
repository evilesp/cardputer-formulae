#!lua
-- doom 0.1.1.3: a Doom-like shooter with pixel graphics. Walk a level, shoot the imps and demons, pick up health and ammo, and
-- clear the level. Needs firmware v0.1.0.14(beta) (the graphics in little pieces of memory) and three drivers, which brew
-- installs with it: doomlevel, doomdraw and doomgame (brew asks first).
-- Every key is a letter or a punctuation key, so no Fn is needed. The motion keys work while they are held down:
--   w  forward          s  back            a  turn left      d  turn right
--   ,  turn left        /  turn right      q  step left      e  step right
--   z  quick turn left                     c  quick turn right (for aiming)
--   f or enter  fire                       space  stop everything
--   m  the map     p  pause     x  sound on / off     ctrl-q  quit
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
