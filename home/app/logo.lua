-- Логотип Home: четыре плитки библиотеки и рамка фокуса, как на главном экране.
-- Им начинается загрузочное видео (кадры рисует bootanim) и кончается заставка Home,
-- поэтому переход с видео на лаунчер выглядит одним движением.

local M = {}

M.COLORS = { {0.23, 0.55, 0.93}, {0.95, 0.40, 0.35}, {0.98, 0.70, 0.18}, {0.35, 0.75, 0.45} }
M.ACCENT = {0.20, 0.78, 0.82}
M.DURATION = 2.4                       -- после этого кадр не меняется

local function clamp(x) return math.max(0, math.min(1, x)) end
local function easeOutBack(x)
  local c1, c3 = 1.70158, 2.70158
  return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end
local function easeOut(x) return 1 - (1 - x) ^ 3 end

-- t — секунды от начала (nil — готовый логотип), size — сторона квадрата плиток
function M.draw(t, cx, cy, size, font, small)
  t = t or 99
  local g = love.graphics
  local gap = size * 0.12
  local s = (size - gap) / 2
  local x0, y0 = cx - size / 2, cy - size / 2 - size * 0.18
  for i = 1, 4 do
    local k = clamp((t - 0.15 - 0.13 * (i - 1)) / 0.5)
    if k > 0 then
      local sc = easeOutBack(k)
      local c = M.COLORS[i]
      local tx = x0 + ((i - 1) % 2) * (s + gap) + s / 2
      local ty = y0 + math.floor((i - 1) / 2) * (s + gap) + s / 2
      g.setColor(c[1], c[2], c[3], clamp(k * 2))
      g.rectangle("fill", tx - s * sc / 2, ty - s * sc / 2, s * sc, s * sc, s * 0.22 * sc)
    end
  end
  -- рамка фокуса прыгает на первую плитку
  local r = clamp((t - 0.85) / 0.35)
  if r > 0 then
    local e = easeOut(r)
    local pad = size * 0.045 + (1 - e) * size * 0.12
    g.setColor(M.ACCENT[1], M.ACCENT[2], M.ACCENT[3], r)
    g.setLineWidth(math.max(2, size * 0.035))
    g.rectangle("line", x0 - pad, y0 - pad, s + pad * 2, s + pad * 2, s * 0.22 + pad)
    g.setLineWidth(1)
  end
  -- надпись
  local w = clamp((t - 1.25) / 0.5)
  if w > 0 and font then
    local e = easeOut(w)
    g.setColor(1, 1, 1, w)
    g.setFont(font)
    local ty = y0 + size + size * 0.22 + (1 - e) * size * 0.12
    g.printf("R36H", cx - 200, ty, 400, "center")
    if small then
      local w2 = clamp((t - 1.6) / 0.5)
      g.setColor(0.62, 0.66, 0.74, w2)
      g.setFont(small)
      g.printf("Home", cx - 200, ty + font:getHeight() + 2, 400, "center")
    end
  end
end

return M
