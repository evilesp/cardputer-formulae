#!lua
-- primes: lists the prime numbers up to a limit, or breaks a number into its prime factors.
-- usage: primes LIMIT          for example: primes 50
--        primes factor NUMBER  for example: primes factor 360   (360 = 2^3 x 3^2 x 5)
-- The list runs up to 1000 and factors work up to 999999999. Trial division only, no big tables.
-- Run it with --selftest to check the rules.

local LIST_MAX = 1000
local FACTOR_MAX = 999999999

-- true when n is a prime number, by trial division
local function isPrime(n)
  if n < 2 then return false end
  if n < 4 then return true end
  if n % 2 == 0 then return false end
  local d = 3
  while d * d <= n do
    if n % d == 0 then return false end
    d = d + 2
  end
  return true
end

-- the prime factors of n as text, like "2^3 x 3^2 x 5", or nil when n is out of range
local function factorText(n)
  if math.type(n) ~= "integer" or n < 2 or n > FACTOR_MAX then return nil end
  local parts = {}
  local d = 2
  while d * d <= n do
    local count = 0
    while n % d == 0 do
      n = n // d
      count = count + 1
    end
    if count == 1 then
      parts[#parts + 1] = tostring(d)
    elseif count > 1 then
      parts[#parts + 1] = tostring(d) .. "^" .. tostring(count)
    end
    if d == 2 then d = 3 else d = d + 2 end
  end
  -- what is left over after the loop is a prime factor too
  if n > 1 then parts[#parts + 1] = tostring(n) end
  return table.concat(parts, " x ")
end

-- the primes from 2 up to limit, as a list of numbers
local function primesUpTo(limit)
  local out = {}
  for n = 2, limit do
    if isPrime(n) then out[#out + 1] = n end
  end
  return out
end

if arg[1] == "--selftest" then
  local failed = 0
  local function check(cond, what)
    if not cond then
      failed = failed + 1
      print("selftest failed: " .. what)
    end
  end
  check(isPrime(2), "2 is prime")
  check(isPrime(97), "97 is prime")
  check(not isPrime(1), "1 is not prime")
  check(not isPrime(91), "91 is 7 x 13, not prime")
  check(#primesUpTo(30) == 10, "there are 10 primes up to 30")
  check(primesUpTo(100)[25] == 97, "the 25th prime is 97")
  check(factorText(360) == "2^3 x 3^2 x 5", "360 is 2^3 x 3^2 x 5")
  check(factorText(4) == "2^2", "4 is 2^2")
  check(factorText(97) == "97", "97 is prime, so it is its own factor")
  check(factorText(30030) == "2 x 3 x 5 x 7 x 11 x 13", "30030 is 2 x 3 x 5 x 7 x 11 x 13")
  check(factorText(999999937) == "999999937", "999999937 is prime, the largest one below the limit")
  check(factorText(1) == nil, "1 has no prime factors")
  check(factorText(1.5) == nil, "a fraction has no prime factors")
  check(factorText(FACTOR_MAX + 1) == nil, "a number above the range is refused")
  if failed == 0 then print("selftest ok") end
  return
end

if arg[1] == "factor" then
  local n = tonumber(arg[2] or "")
  if math.type(n) ~= "integer" then
    print("usage: primes factor NUMBER   (for example: primes factor 360)")
    return
  end
  local text = factorText(n)
  if text then
    print(n .. " = " .. text)
  else
    print("out of range: use whole numbers from 2 to " .. FACTOR_MAX)
  end
  return
end

local limit = tonumber(arg[1] or "")
if math.type(limit) ~= "integer" then
  print("usage: primes LIMIT   or   primes factor NUMBER   (primes 50, primes factor 360)")
  return
end
if limit < 2 or limit > LIST_MAX then
  print("out of range: the list runs up to " .. LIST_MAX)
  return
end

local list = primesUpTo(limit)
print(#list .. " primes up to " .. limit .. ":")
-- ten numbers in a row
local row = {}
for _, p in ipairs(list) do
  row[#row + 1] = string.format("%4d", p)
  if #row == 10 then
    print(table.concat(row))
    row = {}
  end
end
if #row > 0 then print(table.concat(row)) end
