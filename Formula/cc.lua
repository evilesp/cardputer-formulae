#!lua
-- cc: C for this device: cc FILE -o PROGRAM, then ./PROGRAM; or cc -run FILE [ARGS]. The source is translated to Lua, see the driver clang for what is in the language.
local C, e = driver.load("clang")
if not C then print("cc: " .. tostring(e)) return end
C.main(arg, false)
