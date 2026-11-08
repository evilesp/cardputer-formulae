#!lua
-- python: the same program as python3.
if not driver then print("python3: needs the driver module") return end
local P, e = driver.load("pylang")
if not P then print("python3: " .. tostring(e)) return end
local code = P.main(arg)
if code and code ~= 0 and sys and sys.exit then sys.exit(code) end
