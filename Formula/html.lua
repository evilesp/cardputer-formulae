#!lua
-- html: a small web player: a page with CSS and JavaScript on the screen. html FILE.html | URL (see the driver htmlapp)
local A, e = driver.load("htmlapp")
if not A then print("html: " .. tostring(e)) return end
A.main(arg, "html")
