#!lua
-- htmlplay: a small web player: a page with CSS and JavaScript on the screen. htmlplay FILE.html | URL (see the driver htmlapp)
local A, e = driver.load("htmlapp")
if not A then print("htmlplay: " .. tostring(e)) return end
A.main(arg, "htmlplay")
