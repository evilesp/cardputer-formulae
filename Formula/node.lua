#!lua
-- node: JavaScript for this device. node FILE.js [ARGS], node -e "CODE", node alone for the prompt. See the driver jslang for what is in the language.
local J, e = driver.load("jslang")
if not J then print("node: " .. tostring(e)) return end
local code = J.main(arg)
if code and code ~= 0 and os and os.exit then os.exit(code) end
