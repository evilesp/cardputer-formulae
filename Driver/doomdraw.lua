#!lua
-- doomdraw: draws the picture of doom: the walls and floor of the ray caster, the monsters, pickups and fireballs, the
-- weapon, the crosshair, the minimap and the bar at the bottom. A driver, not a program: doom loads it with
-- driver.load("doomdraw") and calls draw.render(state, ui) once per frame. The state holds P (the player), enemies,
-- pickups, balls and G (the game flags). It needs the doomlevel driver too.

local level = driver.load("doomlevel")
local draw = {}

local SW, SH = 240, 135            -- the screen
local HUD_H = 17                   -- the bar at the bottom
local VIEW_H = SH - HUD_H          -- the picture is the rest
local COLW = 2                     -- a ray is 2 pixels wide
local RAYS = SW // COLW
local FOV = 0.66                   -- the camera plane: about 66 degrees
local HALF = VIEW_H / 2

local WALL, LOOKS = level.WALL, level.LOOKS
local MW, MH, grid, cast = level.MW, level.MH, level.grid, level.cast

-- the state of the frame being drawn, and the distance of the wall behind each column
local S, P = nil, nil
local zbuf = {}

-- f from 0 to 256: 256 leaves the colour as it is
local function shade(c, f)
  return ((((c >> 16) & 255) * f >> 8) << 16) | ((((c >> 8) & 255) * f >> 8) << 8) | ((c & 255) * f >> 8)
end

-- how much of a colour is left at this distance, 70 to 256
local function fog(dist)
  local f = math.floor(256 / (1 + dist * 0.16))
  return f < 70 and 70 or f
end

draw.shade, draw.fog = shade, fog

local function drawWorld(horizon)
  -- the ceiling and the floor in bands, darker far away
  local bands = 6
  for i = 0, bands - 1 do
    local y0, y1 = math.floor(horizon * i / bands), math.floor(horizon * (i + 1) / bands)
    gfx.fill(0, y0, SW, y1 - y0 + 1, shade(0x2c3452, 90 + i * 28))
  end
  for i = 0, bands - 1 do
    local y0 = horizon + math.floor((VIEW_H - horizon) * i / bands)
    local y1 = horizon + math.floor((VIEW_H - horizon) * (i + 1) / bands)
    gfx.fill(0, y0, SW, y1 - y0 + 1, shade(0x5a4a3a, 80 + i * 26))
  end
  local dirX, dirY = math.cos(P.angle), math.sin(P.angle)
  local planeX, planeY = -dirY * FOV, dirX * FOV
  for i = 0, RAYS - 1 do
    local cam = 2 * i / (RAYS - 1) - 1
    local dist, side, kind, wx = cast(P.x, P.y, dirX + planeX * cam, dirY + planeY * cam)
    if dist < 0.05 then dist = 0.05 end
    zbuf[i + 1] = dist
    local lineH = VIEW_H / dist
    local top = math.floor(horizon - lineH / 2)
    local bottom = math.floor(horizon + lineH / 2)
    local ya, yb = top < 0 and 0 or top, bottom >= VIEW_H and VIEW_H - 1 or bottom
    local f = fog(dist)
    if side == 1 then f = f * 3 // 4 end
    local base = WALL[kind] or 0x808080
    local px = i * COLW
    gfx.fill(px, ya, COLW, yb - ya + 1, shade(base, f))
    if lineH >= 14 then
      local dark = shade(base, f * 2 // 3)
      if kind == 1 then  -- brick: seams across, and now and then one up
        for k = 1, 3 do
          local y = math.floor(top + lineH * k / 4)
          if y >= 0 and y < VIEW_H then gfx.fill(px, y, COLW, 1, dark) end
        end
        if (wx * 5) % 1 < 0.08 then gfx.fill(px, ya, COLW, yb - ya + 1, dark) end
      elseif kind == 2 then  -- stone: panels
        if (wx * 2) % 1 < 0.06 then gfx.fill(px, ya, COLW, yb - ya + 1, dark) end
      elseif kind == 3 then  -- tech: a light strip
        local y = math.floor(top + lineH * 0.42)
        if y >= 0 and y < VIEW_H then gfx.fill(px, y, COLW, math.max(1, lineH // 14), shade(0x80d0ff, f)) end
      else  -- moss: dark patches at the top
        if math.floor(wx * 8) % 3 == 0 then gfx.fill(px, ya, COLW, math.max(1, lineH * 0.3 // 1), dark) end
      end
    end
  end
end

-- everything that stands in the level, far ones first; a monster is drawn only where no wall is in front of it
local function drawThings(horizon)
  local dirX, dirY = math.cos(P.angle), math.sin(P.angle)
  local planeX, planeY = -dirY * FOV, dirX * FOV
  local invDet = 1 / (planeX * dirY - dirX * planeY)
  local list = {}
  local function add(x, y, look, size, lift, flash)
    local sx, sy = x - P.x, y - P.y
    local tx = invDet * (dirY * sx - dirX * sy)
    local ty = invDet * (-planeY * sx + planeX * sy)
    if ty > 0.15 and ty < 16 then list[#list + 1] = { tx = tx, ty = ty, look = look, size = size, lift = lift, flash = flash } end
  end
  for _, p in ipairs(S.pickups) do
    if not p.taken then add(p.x, p.y, LOOKS[p.kind], 0.4, 0, 0) end
  end
  for _, e in ipairs(S.enemies) do
    if e.dead then
      if e.deadT < 6 then add(e.x, e.y, LOOKS.dead, 0.9, 0, 0) end
    else
      add(e.x, e.y, LOOKS[e.kind], e.type.size, 0, e.flash)
    end
  end
  for _, b in ipairs(S.balls) do add(b.x, b.y, LOOKS.ball, 0.32, 0.3, 0) end
  table.sort(list, function(a, b) return a.ty > b.ty end)
  for _, s in ipairs(list) do
    local lineH = VIEW_H / s.ty
    local h = lineH * s.size
    local wRays = h / COLW
    local center = (RAYS - 1) * (1 + s.tx / s.ty) / 2
    local left = math.floor(center - wRays / 2)
    local right = math.floor(center + wRays / 2)
    local floorY = horizon + lineH / 2 - s.lift * lineH
    local topY = floorY - h
    local f = fog(s.ty)
    local stride = wRays > 40 and 2 or 1
    local i = left < 0 and 0 or left
    while i <= right and i < RAYS do
      if s.ty < zbuf[i + 1] then
        local u = (i - left + 0.5) / (right - left + 1)
        for _, part in ipairs(s.look) do
          if u >= part[1] and u < part[2] then
            local ya = math.floor(topY + part[3] * h)
            local yb = math.floor(topY + part[4] * h)
            if ya < 0 then ya = 0 end
            if yb > VIEW_H then yb = VIEW_H end
            if yb > ya then
              local c = shade(part[5], f)
              if s.flash > 0 then c = 0xffffff end
              gfx.fill(i * COLW, ya, COLW * stride, yb - ya, c)
            end
          end
        end
      end
      i = i + stride
    end
  end
end

local function drawWeapon()
  local sway = math.floor(math.sin(P.bob) * 4 * P.moving)
  local drop = math.floor(math.abs(math.cos(P.bob)) * 3 * P.moving) + (P.flash > 0 and 5 or 0)
  local bx, by = SW // 2 + sway + 40, VIEW_H + 4 + drop
  gfx.fill(bx - 4, by - 36, 8, 26, 0x50565e)      -- barrel
  gfx.fill(bx - 9, by - 28, 18, 16, 0x7a838c)     -- slide
  gfx.fill(bx - 9, by - 28, 18, 2, 0xa8b2bc)
  gfx.fill(bx - 6, by - 14, 12, 14, 0x4a3626)     -- grip
  gfx.fill(bx - 11, by - 8, 22, 12, 0xd8a078)     -- hand
  if P.flash > 0 then
    gfx.triangle(bx - 7, by - 38, bx + 7, by - 38, bx, by - 58, 0xffb020)
    gfx.disc(bx, by - 40, 5, 0xfff0a0)
  end
end

local function drawCrosshair()
  local cx, cy = SW // 2, VIEW_H // 2
  local c = S.G.aim and 0xff4040 or 0xf0f0f0
  gfx.hline(cx - 5, cx - 2, cy, c)
  gfx.hline(cx + 2, cx + 5, cy, c)
  gfx.vline(cx, cy - 5, cy - 2, c)
  gfx.vline(cx, cy + 2, cy + 5, c)
end

local function drawMinimap()
  local s, ox, oy = 2, SW - MW * 2 - 3, 3
  gfx.fill(ox - 1, oy - 1, MW * s + 2, MH * s + 2, 0x000000)
  for y = 0, MH - 1 do
    local x = 0
    while x < MW do
      local t = grid[y][x]
      if t > 0 then
        local x1 = x
        while x1 + 1 < MW and grid[y][x1 + 1] > 0 do x1 = x1 + 1 end
        gfx.fill(ox + x * s, oy + y * s, (x1 - x + 1) * s, s, 0x586078)
        x = x1 + 1
      else
        x = x + 1
      end
    end
  end
  for _, e in ipairs(S.enemies) do
    if not e.dead then gfx.fill(ox + math.floor(e.x * s) - 1, oy + math.floor(e.y * s) - 1, 2, 2, 0xff3030) end
  end
  local px, py = ox + P.x * s, oy + P.y * s
  gfx.line(math.floor(px), math.floor(py), math.floor(px + math.cos(P.angle) * 4), math.floor(py + math.sin(P.angle) * 4), 0xffff60)
  gfx.fill(math.floor(px) - 1, math.floor(py) - 1, 3, 3, 0x40ff80)
end

local function drawHud(ui)
  local t = ui.theme
  local y = VIEW_H
  gfx.fill(0, y, SW, HUD_H, t.panel)
  gfx.hline(0, SW - 1, y, t.border)
  ui.label(4, y + 5, "HP", t.dim)
  local hpColor = P.hp > 50 and t.accent or (P.hp > 25 and t.warn or t.danger)
  ui.bar(20, y + 3, 66, 11, math.max(0, P.hp), 100, hpColor, tostring(math.max(0, P.hp)))
  ui.label(96, y + 5, "AMMO", t.dim)
  ui.label(128, y + 5, tostring(P.ammo), P.ammo <= 5 and t.danger or t.text)
  ui.label(160, y + 5, "KILLS " .. P.kills .. "/" .. #S.enemies, t.text)
end

-- one picture of the game. The message line shows for two seconds after an event (G.msg, G.msgT).
function draw.render(state, ui)
  S, P = state, state.P
  local G = state.G
  local horizon = math.floor(HALF + math.sin(P.bob * 2) * 2.5 * P.moving)
  drawWorld(horizon)
  drawThings(horizon)
  drawWeapon()
  drawCrosshair()
  if G.map then drawMinimap() end
  if G.msgT > 0 then ui.label(4, 3, G.msg, 0xffe060) end
  if P.hurt > 0 then
    for k = 0, 2 do gfx.rect(k, k, SW - 2 * k, VIEW_H - 2 * k, shade(0xff2020, math.floor(256 * math.min(1.0, P.hurt * 2.5)))) end
  end
  drawHud(ui)
end

draw.SCREEN = { w = SW, h = SH, viewH = VIEW_H, hudH = HUD_H }

return draw
