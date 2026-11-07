-- fonts: the smooth fonts of the graphical apps (Lato, SIL Open Font License), made with tools/make_vlw.py and kept in the tap.
-- An app loads this driver and calls fonts.ensure(): the files that are not on the card yet are fetched from the tap (1 MB at most
-- for the set an app uses), once. After that gfx.font(fonts.path("lato-18")) gives text with soft edges.
--   local fonts = driver.load("fonts")
--   fonts.ensure({ "lato-14", "lato-bold-18" })          -> true | nil, error
--   gfx.font(fonts.path("lato-bold-18"))
local M = {}

M.dir = "/usr/share/fonts/vlw/"
M.base = "https://raw.githubusercontent.com/evilesp/cardputer-formulae/main/Fonts/"

-- the files of the set: regular (small to big), bold, light (big, for titles and clocks)
M.all = {
  "lato-12", "lato-14", "lato-16", "lato-18", "lato-20", "lato-24",
  "lato-bold-12", "lato-bold-14", "lato-bold-16", "lato-bold-18", "lato-bold-20", "lato-bold-24", "lato-bold-32", "lato-bold-44", "lato-bold-64",
  "lato-light-32", "lato-light-44", "lato-light-64",
}

function M.path(name)
  return M.dir .. name .. ".vlw"
end

function M.have(name)
  return fs.exists(M.path(name))
end

-- fetches the files of the list that are not on the card; progress(done, total, name) is called before each download
function M.ensure(list, progress)
  list = list or M.all
  local missing = {}
  for _, name in ipairs(list) do
    if not M.have(name) then missing[#missing + 1] = name end
  end
  for i, name in ipairs(missing) do
    if progress then progress(i, #missing, name) end
    local bytes, err = net.pull(M.base .. name .. ".vlw", M.path(name), 1024 * 1024)
    if not bytes then return nil, name .. ": " .. tostring(err) end
  end
  return true
end

return M
