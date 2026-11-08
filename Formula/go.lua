#!lua
-- go: Go for this device. go run FILE.go [ARGS], go build [-o PROGRAM] FILE.go. The source is translated to Lua, see the driver golang for what is in the language.
local M, e = driver.load("golang")
if not M then print("go: " .. tostring(e)) return end
M.main(arg)
