#!lua
-- rustc: Rust for this device: rustc FILE.rs -o PROGRAM, then ./PROGRAM; or rustc -run FILE.rs [ARGS]. The source is translated to Lua, see the driver rustlang for what is in the language.
local M, e = driver.load("rustlang")
if not M then print("rustc: " .. tostring(e)) return end
M.main(arg)
