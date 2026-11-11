#!lua
-- webplay: a small web player: a page with CSS and JavaScript on the screen. webplay FILE.html | URL (see the driver htmlapp)
local A, e = driver.load("htmlapp")
if not A then print("webplay: " .. tostring(e)) return end
A.main(arg, "webplay")
