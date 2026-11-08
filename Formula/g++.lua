#!lua
-- g++: C++ for this device: g++ FILE -o PROGRAM, then ./PROGRAM; or g++ -run FILE [ARGS]. The source is translated to Lua, see the driver clang for what is in the language.
local C, e = driver.load("clang")
if not C then print("g++: " .. tostring(e)) return end
C.main(arg, true)
