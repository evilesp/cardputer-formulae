#!lua
-- c++: C++ for this device: c++ FILE -o PROGRAM, then ./PROGRAM; or c++ -run FILE [ARGS]. The source is translated to Lua, see the driver clang for what is in the language.
local C, e = driver.load("clang")
if not C then print("c++: " .. tostring(e)) return end
local code = C.main(arg, true)
if code and code ~= 0 and os and os.exit then os.exit(code) end
