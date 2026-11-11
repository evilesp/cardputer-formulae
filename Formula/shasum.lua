#!lua
-- shasum: SHA-1/224/256/384/512 checksums, like the perl shasum. Extra: shasum -s TEXT... hashes the words.
-- usage: shasum [OPTION]... [FILE]...

local USAGE = [[
Usage: shasum [OPTION]... [FILE]...
Print or check SHA checksums.
With no FILE, or when FILE is -, read standard input.

  -a, --algorithm   1 (default), 224, 256, 384, 512, 512224, 512256
  -b, --binary      read in binary mode
  -c, --check       read SHA sums from the FILEs and check them
      --tag         create a BSD-style checksum
  -t, --text        read in text mode (default)
  -U, --UNIVERSAL   read in Universal Newlines mode
                        produces same digest on Windows/Unix/Mac
  -0, --01          read in BITS mode
                        ASCII '0' interpreted as 0-bit,
                        ASCII '1' interpreted as 1-bit,
                        all other characters ignored

The following five options are useful only when verifying checksums:
      --ignore-missing  don't fail or report status for missing files
  -q, --quiet           don't print OK for each successfully verified file
  -s, --status          don't output anything, status code shows success
      --strict          exit non-zero for improperly formatted checksum lines
  -w, --warn            warn about improperly formatted checksum lines

  -h, --help        display this help and exit
  -v, --version     output version information and exit

The sums are computed as described in FIPS PUB 180-4.  When checking, the
input should be a former output of this program.  The default mode is to
print a line with checksum, a character indicating type (`*' for binary,
` ' for text, `?' for portable, `^' for BITS), and name for each FILE.

Report shasum bugs to mshelor@cpan.org]]

-- the 80 round constants of SHA-512; SHA-256 uses the top 32 bits of the first 64
local K = {
  0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc,
  0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118,
  0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2,
  0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694,
  0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
  0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5,
  0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4,
  0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70,
  0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df,
  0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
  0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30,
  0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8,
  0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8,
  0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3,
  0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
  0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b,
  0xca273eceea26619c, 0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178,
  0x06f067aa72176fba, 0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b,
  0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c,
  0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817,
}
local H512 = { 0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1, 0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179 }
local H384 = { 0xcbbb9d5dc1059ed8, 0x629a292a367cd507, 0x9159015a3070dd17, 0x152fecd8f70e5939, 0x67332667ffc00b31, 0x8eb44a8768581511, 0xdb0c2e0d64f98fa7, 0x47b5481dbefa4fa4 }

local M32 = 0xffffffff
local function rotr32(x, n) return ((x >> n) | (x << (32 - n))) & M32 end
local function rotl32(x, n) return ((x << n) | (x >> (32 - n))) & M32 end
local function rotr64(x, n) return (x >> n) | (x << (64 - n)) end

local function pad(msg, block, lenBytes)
  local len = #msg
  local zeros = (block - lenBytes - 1 - len) % block
  local tail = lenBytes == 8 and string.pack(">I8", len * 8) or string.pack(">I8I8", len >> 61, len * 8)
  return msg .. "\128" .. string.rep("\0", zeros) .. tail
end

local function yield(n)
  if n % 256 == 0 and sys and sys.yield then sys.yield() end
end

local function sha1(msg)
  local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
  msg = pad(msg, 64, 8)
  for chunk = 1, #msg, 64 do
    local w = {}
    for i = 0, 15 do w[i] = string.unpack(">I4", msg, chunk + i * 4) end
    for i = 16, 79 do w[i] = rotl32(w[i - 3] ~ w[i - 8] ~ w[i - 14] ~ w[i - 16], 1) end
    local a, b, c, d, e = h0, h1, h2, h3, h4
    for i = 0, 79 do
      local f, k
      if i < 20 then f, k = (b & c) | ((~b) & d), 0x5A827999
      elseif i < 40 then f, k = b ~ c ~ d, 0x6ED9EBA1
      elseif i < 60 then f, k = (b & c) | (b & d) | (c & d), 0x8F1BBCDC
      else f, k = b ~ c ~ d, 0xCA62C1D6 end
      local t = (rotl32(a, 5) + (f & M32) + e + k + w[i]) & M32
      e, d, c, b, a = d, c, rotl32(b, 30), a, t
    end
    h0, h1, h2, h3, h4 = (h0 + a) & M32, (h1 + b) & M32, (h2 + c) & M32, (h3 + d) & M32, (h4 + e) & M32
    yield(chunk // 64 + 1)
  end
  return string.format("%08x%08x%08x%08x%08x", h0, h1, h2, h3, h4)
end

local function sha256(msg, words)
  local h = {}
  if words == 7 then
    for i = 1, 8 do h[i] = H384[i] & M32 end
  else
    for i = 1, 8 do h[i] = H512[i] >> 32 end
  end
  msg = pad(msg, 64, 8)
  for chunk = 1, #msg, 64 do
    local w = {}
    for i = 0, 15 do w[i] = string.unpack(">I4", msg, chunk + i * 4) end
    for i = 16, 63 do
      local s0 = rotr32(w[i - 15], 7) ~ rotr32(w[i - 15], 18) ~ (w[i - 15] >> 3)
      local s1 = rotr32(w[i - 2], 17) ~ rotr32(w[i - 2], 19) ~ (w[i - 2] >> 10)
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & M32
    end
    local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
    for i = 0, 63 do
      local S1 = rotr32(e, 6) ~ rotr32(e, 11) ~ rotr32(e, 25)
      local ch = (e & f) ~ ((~e) & g)
      local t1 = (hh + S1 + (ch & M32) + (K[i + 1] >> 32) + w[i]) & M32
      local S0 = rotr32(a, 2) ~ rotr32(a, 13) ~ rotr32(a, 22)
      local maj = (a & b) ~ (a & c) ~ (b & c)
      local t2 = (S0 + maj) & M32
      hh, g, f, e = g, f, e, (d + t1) & M32
      d, c, b, a = c, b, a, (t1 + t2) & M32
    end
    local add = { a, b, c, d, e, f, g, hh }
    for i = 1, 8 do h[i] = (h[i] + add[i]) & M32 end
    yield(chunk // 64 + 1)
  end
  local out = {}
  for i = 1, words or 8 do out[i] = string.format("%08x", h[i]) end
  return table.concat(out)
end

local function sha512(msg, words)
  local h = {}
  for i = 1, 8 do h[i] = (words == 6 and H384 or H512)[i] end
  msg = pad(msg, 128, 16)
  for chunk = 1, #msg, 128 do
    local w = {}
    for i = 0, 15 do w[i] = string.unpack(">i8", msg, chunk + i * 8) end
    for i = 16, 79 do
      local s0 = rotr64(w[i - 15], 1) ~ rotr64(w[i - 15], 8) ~ (w[i - 15] >> 7)
      local s1 = rotr64(w[i - 2], 19) ~ rotr64(w[i - 2], 61) ~ (w[i - 2] >> 6)
      w[i] = w[i - 16] + s0 + w[i - 7] + s1
    end
    local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
    for i = 0, 79 do
      local S1 = rotr64(e, 14) ~ rotr64(e, 18) ~ rotr64(e, 41)
      local ch = (e & f) ~ ((~e) & g)
      local t1 = hh + S1 + ch + K[i + 1] + w[i]
      local S0 = rotr64(a, 28) ~ rotr64(a, 34) ~ rotr64(a, 39)
      local maj = (a & b) ~ (a & c) ~ (b & c)
      local t2 = S0 + maj
      hh, g, f, e = g, f, e, d + t1
      d, c, b, a = c, b, a, t1 + t2
    end
    local add = { a, b, c, d, e, f, g, hh }
    for i = 1, 8 do h[i] = h[i] + add[i] end
    yield(chunk // 128 + 1)
  end
  local out = {}
  for i = 1, words or 8 do out[i] = string.format("%016x", h[i]) end
  return table.concat(out)
end

local function digest(alg, msg)
  if alg == 1 then return sha1(msg)
  elseif alg == 224 then return sha256(msg, 7)
  elseif alg == 256 then return sha256(msg, 8)
  elseif alg == 384 then return sha512(msg, 6)
  else return sha512(msg, 8) end
end

local ALGS = { [1] = true, [224] = true, [256] = true, [384] = true, [512] = true }
local BYLEN = { [40] = 1, [56] = 224, [64] = 256, [96] = 384, [128] = 512 }

local algGiven = false
local alg, binary, check, status, quiet, warn, strict, ignoreMissing, tag, textMode = 1, false, false, false, false, false, false, false, false, false
local files = {}
local i = 1
local noOpts = false
local function bad(msg)
  io.stderr:write(msg .. "\n")
  io.stderr:write(USAGE .. "\n")
  os.exit(1)
end
while arg[i] do
  local a = arg[i]
  if noOpts or a == "-" or a:sub(1, 1) ~= "-" then
    files[#files + 1] = a
  elseif a == "--" then
    noOpts = true
  elseif a:sub(1, 2) == "--" then
    local name, val = a:match("^%-%-([%w%-]+)=?(.*)$")
    if name == "algorithm" then
      if val == "" then i = i + 1; val = arg[i] end
      alg = tonumber(val)
      algGiven = true
      if not alg or not (ALGS[alg] or alg == 512224 or alg == 512256) then
        io.stderr:write("shasum: Unrecognized algorithm\n")
        os.exit(1)
      end
    elseif name == "binary" then binary = true
    elseif name == "text" then textMode = true
    elseif name == "check" then check = true
    elseif name == "tag" then tag = true
    elseif name == "quiet" then quiet = true
    elseif name == "status" then status = true
    elseif name == "warn" then warn = true
    elseif name == "strict" then strict = true
    elseif name == "ignore-missing" then ignoreMissing = true
    elseif name == "portable" or name == "UNIVERSAL" or name == "01" then textMode = true
    elseif name == "help" then print(USAGE) return
    elseif name == "version" then print("6.04") return
    else bad("shasum: unrecognized option '" .. a .. "'") end
  else
    local j = 2
    while j <= #a do
      local o = a:sub(j, j)
      if o == "a" then
        local val = a:sub(j + 1)
        if val == "" then i = i + 1; val = arg[i] end
        alg = tonumber(val)
      algGiven = true
        if not alg or not (ALGS[alg] or alg == 512224 or alg == 512256) then
          io.stderr:write("shasum: Unrecognized algorithm\n")
          os.exit(1)
        end
        j = #a
      elseif o == "b" then binary = true
      elseif o == "t" or o == "U" or o == "p" or o == "0" then textMode = true
      elseif o == "c" then check = true
      elseif o == "q" then quiet = true
      elseif o == "s" then status = true
      elseif o == "w" then warn = true
      elseif o == "h" then print(USAGE) return
      elseif o == "v" then print("6.04") return
      else bad("shasum: invalid option -- '" .. o .. "'") end
      j = j + 1
    end
  end
  i = i + 1
end

if alg == 512224 or alg == 512256 then
  io.stderr:write("shasum: Unrecognized algorithm\n")
  os.exit(1)
end

local function readAll(name)
  if name == "-" then
    if sys.piped then return io.read("a") or "" end
    return ""
  end
  if fs.isdir(name) then return nil, "Is a directory" end
  local data = fs.read(name)
  if data == nil then return nil, "No such file or directory" end
  return data
end

-- extra from the old package: shasum -s TEXT... hashes the words (SHA-256 unless -a is given)
if status and not check and #files > 0 then
  print(digest(algGiven and alg or 256, table.concat(files, " ")) .. "  -")
  return
end

local exit = 0
if #files == 0 then files[1] = "-" end

if not check then
  for _, f in ipairs(files) do
    local data, err = readAll(f)
    if not data then
      io.stderr:write("shasum: " .. f .. ": " .. err .. "\n")
      exit = 1
    elseif tag then
      print("SHA" .. alg .. " (" .. f .. ") = " .. digest(alg, data))
    else
      print(digest(alg, data) .. " " .. (binary and "*" or " ") .. f)
    end
  end
  os.exit(exit)
end

-- shasum -c: check the lines "HASH  FILE" of every list file
local bad_, unread, lines = 0, 0, 0
for _, list in ipairs(files) do
  local text, err = readAll(list)
  if not text then
    io.stderr:write("shasum: " .. list .. ": " .. err .. "\n")
    exit = 1
  else
    local found, n = 0, 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
      n = n + 1
      local hash, mode, name = line:match("^(%x+) ([ *?^])(.*)$")
      local useAlg = hash and BYLEN[#hash]
      if not useAlg then
        if line ~= "" then
          if warn then io.stderr:write("shasum: " .. list .. ": " .. n .. ": improperly formatted SHA checksum line\n") end
          if strict then exit = 1 end
        end
      else
        found = found + 1
        local data = readAll(name)
        if not data then
          if not ignoreMissing then
            io.stderr:write("shasum: " .. name .. ": No such file or directory\n")
            if not status then print(name .. ": FAILED open or read") end
            unread = unread + 1
          end
        elseif digest(useAlg, data):lower() == hash:lower() then
          if not status and not quiet then print(name .. ": OK") end
        else
          if not status then print(name .. ": FAILED") end
          bad_ = bad_ + 1
        end
      end
    end
    if found == 0 then
      io.stderr:write("shasum: " .. list .. ": no properly formatted SHA checksum lines found\n")
      exit = 1
    end
  end
end
local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end
if not status then
  if unread > 0 then
    io.stderr:write("shasum: WARNING: " .. plural(unread, "listed file could not be read", "listed files could not be read") .. "\n")
  end
  if bad_ > 0 then
    io.stderr:write("shasum: WARNING: " .. plural(bad_, "computed checksum did NOT match", "computed checksums did NOT match") .. "\n")
  end
end
if bad_ > 0 or unread > 0 then exit = 1 end
os.exit(exit)
