-- Свой главный экран для R36H (LÖVE 11.4).
-- Игры запускает теми же командами, что EmulationStation: команду пишет
-- в /tmp/home_launch.sh и выходит, Home.sh её выполняет и запускает экран снова.

local lib = require("library")
local logo = require("logo")
local utf8 = require("utf8")

local W, H = 640, 480
local LAUNCH_FILE = "/tmp/home_launch.sh"
local SELF = "/roms/ports/Home.sh"

local ACCENTS = {
  { name = "Бирюза",   c = {0.20, 0.78, 0.82} },
  { name = "Янтарь",   c = {1.00, 0.72, 0.20} },
  { name = "Коралл",   c = {1.00, 0.45, 0.40} },
  { name = "Лаванда",  c = {0.62, 0.55, 1.00} },
  { name = "Лайм",     c = {0.55, 0.85, 0.30} },
}
local TILE_COLORS = {
  {0.23, 0.55, 0.93}, {0.95, 0.40, 0.35}, {0.98, 0.70, 0.18}, {0.35, 0.75, 0.45},
  {0.62, 0.45, 0.95}, {0.20, 0.72, 0.80}, {0.95, 0.50, 0.72}, {0.55, 0.62, 0.70},
}
local C = {
  bg = {0.06, 0.07, 0.09}, bg2 = {0.10, 0.12, 0.16},
  card = {0.14, 0.16, 0.20}, text = {1, 1, 1}, dim = {0.62, 0.66, 0.74},
  faint = {0.35, 0.38, 0.45}, bar = {0.04, 0.05, 0.06, 0.94},
}
local WEEKDAYS = { "Воскресенье", "Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота" }
local MONTHS = { "января", "февраля", "марта", "апреля", "мая", "июня", "июля",
                 "августа", "сентября", "октября", "ноября", "декабря" }

local TILE_STYLES = { { id = "covers", name = "обложки" }, { id = "color", name = "цвет" },
                      { id = "minimal", name = "минимализм" } }
local state = { history = {}, favs = {}, accent = 1, tileStyle = "covers", sysOpts = {}, gameOpts = {} }
local systems, settings, games = {}, {}, {}
local recent, favorites, tiles = {}, {}, {}
local fonts, images, imageOrder = {}, {}, {}
local stick
local screen, overlay
local launching
local battery, charging, wifi = nil, false, false
local sysTimer = 0
local repeatBtn, repeatT = nil, 0
local stickDir, stickT = nil, 0             -- левый стик работает как крестовина

---------------------------------------------------------------- утилиты

local function accent() return ACCENTS[state.accent].c end

local function font(size, bold)
  local key = (bold and "b" or "r") .. size
  if not fonts[key] then
    fonts[key] = love.graphics.newFont(bold and "fonts/DejaVuSans-Bold.ttf" or "fonts/DejaVuSans.ttf", size)
  end
  return fonts[key]
end

local function serialize(v, ind)
  ind = ind or ""
  local t = type(v)
  if t == "table" then
    local out = { "{\n" }
    for k, x in pairs(v) do
      local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
      out[#out + 1] = ind .. " " .. key .. "=" .. serialize(x, ind .. " ") .. ",\n"
    end
    out[#out + 1] = ind .. "}"
    return table.concat(out)
  elseif t == "string" then
    return string.format("%q", v)
  end
  return tostring(v)
end

local function loadLua(name)
  if not love.filesystem.getInfo(name) then return nil end
  local ok, chunk = pcall(love.filesystem.load, name)
  if not ok or not chunk then return nil end
  local ok2, v = pcall(chunk)
  return ok2 and v or nil
end

local function saveState() love.filesystem.write("state.lua", "return " .. serialize(state)) end

local function readLine(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*l")
  f:close()
  return s
end

local function ago(t)
  local d = os.time() - t
  if d < 60 then return "только что" end
  if d < 3600 then return math.floor(d / 60) .. " мин назад" end
  if d < 86400 then return math.floor(d / 3600) .. " ч назад" end
  if d < 172800 then return "вчера" end
  return math.floor(d / 86400) .. " дн. назад"
end

-- Обрезать строку по ширине, не разрывая UTF-8
local function fit(text, f, width)
  if f:getWidth(text) <= width then return text end
  local chars = {}
  for _, c in utf8.codes(text) do chars[#chars + 1] = utf8.char(c) end
  while #chars > 0 and f:getWidth(table.concat(chars) .. "…") > width do chars[#chars] = nil end
  return table.concat(chars) .. "…"
end

local function shortName(name)
  return (name:gsub("%s*[%(%[].-[%)%]]", ""):gsub("%s+$", ""))
end

---------------------------------------------------------------- картинки

local function getImage(path)
  if not path then return nil end
  local e = images[path]
  if e ~= nil then return e or nil end
  local data = lib.readFile(path)
  local img = false
  if data then
    local ok, res = pcall(function()
      local fd = love.filesystem.newFileData(data, path:match("[^/]+$"))
      local i = love.graphics.newImage(fd)
      i:setFilter("linear", "linear")
      return i
    end)
    if ok then img = res end
  end
  images[path] = img
  imageOrder[#imageOrder + 1] = path
  if #imageOrder > 80 then
    local old = table.remove(imageOrder, 1)
    if images[old] then images[old]:release() end
    images[old] = nil
  end
  return img or nil
end

-- Картинка с обрезкой под прямоугольник (как object-fit: cover)
local function drawCover(img, x, y, w, h)
  local iw, ih = img:getDimensions()
  local s = math.max(w / iw, h / ih)
  local qw, qh = w / s, h / s
  local q = love.graphics.newQuad((iw - qw) / 2, (ih - qh) / 2, qw, qh, iw, ih)
  love.graphics.draw(img, q, x, y, 0, s, s)
end

local function drawContain(img, x, y, w, h)
  local iw, ih = img:getDimensions()
  local s = math.min(w / iw, h / ih)
  love.graphics.draw(img, x + (w - iw * s) / 2, y + (h - ih * s) / 2, 0, s, s)
end

-- Арт систем берём из тем ArkOS: обложки steamdeck, логотипы и персонажи nes-box
local THEME_ROOT = rawget(_G, "THEME_ROOT") or "/etc/emulationstation/themes"
local ART = {
  capsule = "/es-theme-steamdeck/_inc/systems/capsule/%s.png",
  logo = "/es-theme-nes-box/%s/system.png",
  hero = "/es-theme-nes-box/%s/background_icon.png",
}

local function sysArt(sys, kind)
  if not sys then return nil end
  return getImage(THEME_ROOT .. ART[kind]:format(sys.theme or sys.name))
end

-- Силуэты геймпадов (белые PNG из темы Carbon, см. pads/CREDITS.txt)
local PAD_ALIAS = { megadrive = "genesis", ["pico-8"] = "pc", pico8 = "pc", easyrpg = "pc",
                    scummvm = "pc", tg16 = "pcengine", sg1000 = "sg-1000", pcenginecd = "pce-cd" }
local pads = {}

local function padImage(sys)
  if not sys then return nil end
  local name = sys.theme or sys.name
  for _, n in ipairs({ name, PAD_ALIAS[name] or name, sys.name, PAD_ALIAS[sys.name] or sys.name, "pc" }) do
    if pads[n] == nil then
      local file = "pads/" .. n .. ".png"
      pads[n] = love.filesystem.getInfo(file) and love.graphics.newImage(file, { mipmaps = true }) or false
      if pads[n] then pads[n]:setFilter("linear", "linear"); pads[n]:setMipmapFilter("linear") end
    end
    if pads[n] then return pads[n] end
  end
end

local function gradient(x, y, w, h, top, bottom)
  local steps = 12
  for i = 0, steps - 1 do
    local t = i / (steps - 1)
    love.graphics.setColor(top[1] + (bottom[1] - top[1]) * t, top[2] + (bottom[2] - top[2]) * t,
                           top[3] + (bottom[3] - top[3]) * t, 1)
    love.graphics.rectangle("fill", x, y + h * i / steps, w, h / steps + 1)
  end
end

-- Заглушка вместо скриншота: геймпад системы и её название на тёмном фоне в её цвете
local function drawPlaceholder(sys, x, y, w, h)
  local c = (sys and sys.color) or {0.3, 0.35, 0.45}
  gradient(x, y, w, h, { c[1] * 0.28, c[2] * 0.28, c[3] * 0.28 }, { c[1] * 0.10, c[2] * 0.10, c[3] * 0.10 })
  local f = font(math.max(11, math.min(20, math.floor(h / 9))), true)
  local pad = padImage(sys)
  local textH = sys and f:getHeight() + h * 0.06 or 0
  if pad then
    love.graphics.setColor(1, 1, 1, 0.85)
    drawContain(pad, x + w * 0.2, y + h * 0.14, w * 0.6, h * 0.72 - textH)
  end
  if sys then
    love.graphics.setColor(1, 1, 1, 0.75)
    love.graphics.setFont(f)
    love.graphics.printf(fit(sys.fullname or sys.name, f, w - 16), x + 8, y + h - textH - h * 0.04, w - 16, "center")
  end
end

---------------------------------------------------------------- библиотека

local function isFav(g)
  local v = state.favs[g.path]
  if v == nil then return g.fav end
  return v
end

local function lastPlayed(g)
  return math.max(g.last or 0, state.history[g.path] or 0)
end

local function rebuildLists()
  recent, favorites = {}, {}
  for _, g in ipairs(games) do
    if lastPlayed(g) > 0 then recent[#recent + 1] = g end
    if isFav(g) then favorites[#favorites + 1] = g end
  end
  table.sort(recent, function(a, b) return lastPlayed(a) > lastPlayed(b) end)
  table.sort(favorites, function(a, b) return a.name:lower() < b.name:lower() end)

  tiles = {
    { kind = "search", label = "Поиск" },
    { kind = "recent", label = "Недавние", count = #recent },
    { kind = "favs", label = "Избранное", count = #favorites, icon = "★" },
  }
  local n = 0
  for i, s in ipairs(systems) do
    if (s.count or 0) > 0 then
      n = n + 1
      s.color = TILE_COLORS[(n - 1) % #TILE_COLORS + 1]
      tiles[#tiles + 1] = { kind = "system", sys = i, label = s.fullname or s.name,
                            count = s.count, color = s.color }
    end
  end
end

local function loadLibrary(force)
  systems = lib.parseSystems(lib.readFile(lib.ES_SYSTEMS) or "")
  settings = lib.parseSettings(lib.readFile(lib.ES_SETTINGS))
  local stamp = lib.stamp(systems)
  local cache = not force and loadLua("index.lua")
  if cache and cache.stamp == stamp and cache.games then
    games = cache.games
    for i, s in ipairs(systems) do s.count = cache.counts[i] or 0 end
  else
    games = lib.scan(systems, SELF)
    local counts = {}
    for i, s in ipairs(systems) do counts[i] = s.count end
    love.filesystem.write("index.lua", "return " .. serialize({ stamp = stamp, games = games, counts = counts }))
  end
  table.sort(games, function(a, b) return a.name:lower() < b.name:lower() end)
  rebuildLists()
end

local function sysKey(sys) return sys.name .. "|" .. sys.path end

-- Свои эмулятор/ядро поверх настроек ES: для системы и для отдельной игры
local function launchArgs(g)
  local sys = systems[g.sys]
  local so = state.sysOpts[sysKey(sys)]
  local set = settings
  if so then
    set = setmetatable({ [sys.name .. ".emulator"] = so.emulator, [sys.name .. ".core"] = so.core },
                       { __index = settings })
  end
  local go = state.gameOpts[g.path]
  local game = g
  if go then
    game = setmetatable({ emulator = go.emulator or g.emulator, core = go.core or g.core }, { __index = g })
  end
  return sys, game, set
end

-- Экран запуска. Его же Home.sh превращает в loading.gif, который ArkOS (perfmax)
-- показывает, пока грузится эмулятор, — вместо «ArkOS now loading».
local function drawLoading(g)
  local sys = systems[g.sys]
  love.graphics.setColor(C.bg)
  love.graphics.rectangle("fill", 0, 0, W, H)
  local pad = padImage(sys)
  if pad then
    love.graphics.setColor(1, 1, 1, 0.8)
    drawContain(pad, W / 2 - 120, 96, 240, 140)
  end
  local f = font(26, true)
  local _, lines = f:getWrap(shortName(g.name), W - 80)
  love.graphics.setColor(C.text)
  love.graphics.setFont(f)
  for i = 1, math.min(2, #lines) do
    love.graphics.printf(lines[i], 40, 268 + (i - 1) * f:getHeight(), W - 80, "center")
  end
  love.graphics.setColor(C.dim)
  love.graphics.setFont(font(15))
  love.graphics.printf(sys and (sys.fullname or sys.name) or "", 40, 276 + math.min(2, #lines) * f:getHeight(),
    W - 80, "center")
  local ac = accent()
  for k = -1, 1 do
    love.graphics.setColor(ac[1], ac[2], ac[3], 1 - math.abs(k) * 0.45)
    love.graphics.circle("fill", W / 2 + k * 18, H - 64, 5)
  end
end

local function launch(g)
  local sys = systems[g.sys]
  if not sys then return end
  state.history[g.path] = os.time()
  saveState()
  local f = io.open(LAUNCH_FILE, "w")
  if not f then return end
  f:write("#!/bin/bash\n", lib.buildCommand(launchArgs(g)), "\n")
  f:close()
  pcall(function()
    local cv = love.graphics.newCanvas(W, H)
    love.graphics.push("all")
    love.graphics.setCanvas(cv)
    love.graphics.origin()
    drawLoading(g)
    love.graphics.pop()
    cv:newImageData():encode("png", "loading.png")
  end)
  launching = { game = g, t = 0 }
end

local function toggleFav(g)
  state.favs[g.path] = not isFav(g)
  saveState()
  rebuildLists()
end

---------------------------------------------------------------- общие элементы

local function drawBar(hints)
  local f = font(14)
  love.graphics.setColor(C.bar)
  love.graphics.rectangle("fill", 0, H - 28, W, 28)
  love.graphics.setFont(f)
  local x = 14
  for _, h in ipairs(hints) do
    local key, label = h[1], h[2]
    local kw = math.max(18, f:getWidth(key) + 10)
    love.graphics.setColor(accent())
    love.graphics.rectangle("fill", x, H - 22, kw, 16, 8)
    love.graphics.setColor(C.bg)
    love.graphics.print(key, x + (kw - f:getWidth(key)) / 2, H - 22 + (16 - f:getHeight()) / 2)
    love.graphics.setColor(C.dim)
    love.graphics.print(label, x + kw + 6, H - 28 + (28 - f:getHeight()) / 2)
    x = x + kw + 6 + f:getWidth(label) + 16
  end
end

local function drawStatus(y)
  local f = font(15)
  love.graphics.setFont(f)
  local x = W - 18
  if charging or battery then
    local s = charging and "⚡ зарядка" or ("≈" .. battery .. "%")
    x = x - f:getWidth(s)
    love.graphics.setColor((battery or 100) <= 15 and not charging and {1, 0.4, 0.35} or C.dim)
    love.graphics.print(s, x, y)
    x = x - 12
  end
  if wifi then
    x = x - f:getWidth("Wi‑Fi")
    love.graphics.setColor(C.dim)
    love.graphics.print("Wi‑Fi", x, y)
    x = x - 12
  end
  local t = os.date("%H:%M")
  x = x - f:getWidth(t)
  love.graphics.setColor(C.text)
  love.graphics.print(t, x, y)
end

local function focusRing(x, y, w, h, r)
  love.graphics.setColor(accent())
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", x - 3, y - 3, w + 6, h + 6, r + 3)
  love.graphics.setLineWidth(1)
end

---------------------------------------------------------------- система

local toastText, toastT = nil, 0
function toast(t) toastText, toastT = t, 4 end

local wifiCache, wifiCacheT = nil, -10
-- Включён, если радио включено и модуль на месте (net.sh off отключает его от USB)
function wifiOn()
  local now = love.timer.getTime()
  if now - wifiCacheT > 2 then
    local p = io.popen("nmcli radio wifi 2>/dev/null")
    wifiCache = (p and p:read("*l") or "") == "enabled"
    if p then p:close() end
    local dev = io.open("/sys/bus/usb/devices/1-1/uevent")
    if dev then dev:close() else wifiCache = false end
    wifiCacheT = now
  end
  return wifiCache
end

-- net.sh on/off/remote: глубокое выключение модуля, как в ArkOS
function setWifi(on)
  os.execute("(sudo -n /roms/ports/home/net.sh " .. (on and "on" or "off") .. " >/dev/null 2>&1 &)")
  wifiCache, wifiCacheT = on, love.timer.getTime() + 8
  toast(on and "Wi‑Fi включается…" or "Wi‑Fi выключен")
end

-- Громкость — ALSA «Playback», яркость — подсветка (ark в группе video)
local BACKLIGHT = "/sys/class/backlight/backlight/"

function getVolume()
  local p = io.popen("amixer sget Playback 2>/dev/null")
  local s = p and p:read("*a") or ""
  if p then p:close() end
  return tonumber(s:match("%[(%d+)%%%]")) or 0
end

local quietUntil = 0                 -- свои изменения из меню не показываем ползунком поверх

function setVolume(v)
  v = math.max(0, math.min(100, v))
  os.execute("amixer -q sset Playback " .. v .. "% 2>/dev/null")
  quietUntil = love.timer.getTime() + 0.6
end

function getBrightness()
  local cur = tonumber(readLine(BACKLIGHT .. "brightness") or "")
  local max = tonumber(readLine(BACKLIGHT .. "max_brightness") or "")
  if not cur or not max or max == 0 then return 0 end
  return math.floor(cur / max * 100 + 0.5)
end

function setBrightness(pct)
  local max = tonumber(readLine(BACKLIGHT .. "max_brightness") or "")
  if not max then return end
  pct = math.max(5, math.min(100, pct))
  local f = io.open(BACKLIGHT .. "brightness", "w")
  if f then f:write(tostring(math.floor(max * pct / 100 + 0.5))); f:close() end
  quietUntil = love.timer.getTime() + 0.6
end

-- Кнопки громкости (и яркости через F) обрабатывает ogage, Home о них не знает.
-- «amixer events» пишет строку в файл на каждое изменение микшера, Home раз в 0,25 с
-- смотрит размер файла. Не поток с io.popen: пока поток ждёт строку, он держит
-- блокировку stdio, и любой popen главного потока виснет навсегда (проверено на приставке).
-- Обёртка снимает блокировку сигналов, иначе amixer не умрёт от SIGTERM при выключении.
local VOL_LOG = "/dev/shm/home_mixer.log"
local AMIXER = [=[python3 -c "import os,signal
signal.pthread_sigmask(signal.SIG_SETMASK,[])
os.execvp('stdbuf',['stdbuf','-oL','amixer','events'])"]=]
local osd                             -- { kind = "volume"/"bright", value, t }
local lastBright, brightT = nil, 0
local volSize, osdReady = nil, 0
local wantShot = false               -- captureScreenshot на Mali ничего не пишет — снимаем через холст

local function fileSize(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local n = f:seek("end")
  f:close()
  return n
end

local function stopOsd() os.execute("pkill -9 -f '^amixer events' 2>/dev/null") end

local function startOsd()
  stopOsd()
  os.execute(": > " .. VOL_LOG .. "; (" .. AMIXER .. " >> " .. VOL_LOG .. " 2>/dev/null &)")
  osdReady = love.timer.getTime() + 2       -- при старте amixer перечисляет все регуляторы
  lastBright = readLine(BACKLIGHT .. "brightness")
end

local function showOsd(kind, value)
  if love.timer.getTime() < quietUntil then return end
  osd = { kind = kind, value = value, t = 1.6 }
end

local function updateOsd(dt)
  brightT = brightT + dt
  if brightT > 0.25 then
    brightT = 0
    local n = fileSize(VOL_LOG)
    if n and volSize and n > volSize and love.timer.getTime() > osdReady then showOsd("volume", getVolume()) end
    if n and n > 65536 then os.execute(": > " .. VOL_LOG); n = 0 end
    volSize = n
    -- снимок экрана для отладки по SSH: touch /tmp/home_shot → save/love/home/shot.png
    if os.remove("/tmp/home_shot") then wantShot = true end
    local b = readLine(BACKLIGHT .. "brightness")
    if b ~= lastBright then
      if lastBright then showOsd("bright", getBrightness()) end
      lastBright = b
    end
  end
  if osd then
    osd.t = osd.t - dt
    if osd.t <= 0 then osd = nil end
  end
end

local function drawOsd()
  if not osd then return end
  local a = math.min(1, osd.t / 0.3)
  local w, h = 300, 54
  local x, y = (W - w) / 2, 22
  love.graphics.setColor(0.05, 0.06, 0.08, 0.78 * a)
  love.graphics.rectangle("fill", x, y, w, h, 14)
  local ix, iy = x + 30, y + h / 2
  love.graphics.setColor(1, 1, 1, a)
  love.graphics.setLineWidth(2.5)
  if osd.kind == "volume" then
    love.graphics.polygon("fill", ix - 12, iy - 5, ix - 6, iy - 5, ix + 1, iy - 11, ix + 1, iy + 11, ix - 6, iy + 5, ix - 12, iy + 5)
    if osd.value > 0 then love.graphics.arc("line", "open", ix + 3, iy, 7, -0.8, 0.8) end
    if osd.value > 50 then love.graphics.arc("line", "open", ix + 3, iy, 12, -0.8, 0.8) end
    if osd.value == 0 then love.graphics.line(ix + 6, iy - 5, ix + 14, iy + 5); love.graphics.line(ix + 14, iy - 5, ix + 6, iy + 5) end
  else
    love.graphics.circle("fill", ix, iy, 6)
    for k = 0, 7 do
      local an = k * math.pi / 4
      love.graphics.line(ix + math.cos(an) * 9, iy + math.sin(an) * 9, ix + math.cos(an) * 13, iy + math.sin(an) * 13)
    end
  end
  love.graphics.setLineWidth(1)
  local bx, bw = x + 62, w - 62 - 62
  love.graphics.setColor(1, 1, 1, 0.18 * a)
  love.graphics.rectangle("fill", bx, iy - 4, bw, 8, 4)
  local ac = accent()
  love.graphics.setColor(ac[1], ac[2], ac[3], a)
  love.graphics.rectangle("fill", bx, iy - 4, math.max(8, bw * osd.value / 100), 8, 4)
  love.graphics.setColor(1, 1, 1, a)
  love.graphics.setFont(font(16, true))
  local v = osd.value .. "%"
  love.graphics.print(v, x + w - 18 - font(16, true):getWidth(v), iy - font(16, true):getHeight() / 2)
end

-- Что делать после выхода: boot.sh читает файл (es / poweroff)
function exitTo(what)
  local f = io.open("/tmp/home_exit", "w")
  if f then f:write(what); f:close() end
  saveState()
  love.event.quit()
end

local function drawToast()
  if not toastText then return end
  local f = font(15, true)
  local w = f:getWidth(toastText) + 30
  love.graphics.setColor(0.18, 0.21, 0.27, 0.95)
  love.graphics.rectangle("fill", (W - w) / 2, H - 70, w, 32, 10)
  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(f)
  love.graphics.printf(toastText, 0, H - 70 + 7, W, "center")
end

---------------------------------------------------------------- экран списка

local List = {}
List.__index = List

local function openList(title, items, emptyText)
  local s = setmetatable({ title = title, items = items, sel = 1, top = 1,
                           empty = emptyText or "Пусто", still = 0 }, List)
  return s
end

function List:move(d)
  if #self.items == 0 then return end
  self.sel = math.max(1, math.min(#self.items, self.sel + d))
  self.still = 0
end

function List:press(b)
  local g = self.items[self.sel]
  if b == "dpup" then self:move(-1)
  elseif b == "dpdown" then self:move(1)
  elseif b == "dpleft" or b == "leftshoulder" then self:move(-10)
  elseif b == "dpright" or b == "rightshoulder" then self:move(10)
  elseif b == "a" and g then launch(g)
  elseif b == "y" and g then toggleFav(g)
  elseif b == "back" and g then overlay = openOpts(systems[g.sys], g)
  elseif b == "b" then screen = self.back
  end
end

function List:update(dt) self.still = self.still + dt end

function List:draw()
  love.graphics.setColor(C.text)
  love.graphics.setFont(font(22, true))
  love.graphics.print(fit(self.title, font(22, true), 380), 18, 12)
  love.graphics.setFont(font(15))
  love.graphics.setColor(C.dim)
  love.graphics.print(#self.items .. " игр", 18, 42)
  drawStatus(16)

  if #self.items == 0 then
    love.graphics.setFont(font(18))
    love.graphics.setColor(C.dim)
    love.graphics.printf(self.empty, 18, 200, W - 36, "center")
    drawBar({ { "B", "Назад" } })
    return
  end

  local rowH, listY, listW = 30, 72, 300
  local rows = math.floor((H - 28 - listY - 6) / rowH)
  if self.sel < self.top then self.top = self.sel end
  if self.sel >= self.top + rows then self.top = self.sel - rows + 1 end
  local f = font(16)
  love.graphics.setFont(f)
  for i = self.top, math.min(#self.items, self.top + rows - 1) do
    local g = self.items[i]
    local y = listY + (i - self.top) * rowH
    if i == self.sel then
      love.graphics.setColor(accent())
      love.graphics.rectangle("fill", 10, y, listW, rowH - 4, 8)
      love.graphics.setColor(C.bg)
    else
      love.graphics.setColor(C.text)
    end
    local star = isFav(g) and "★ " or ""
    love.graphics.print(fit(star .. shortName(g.name), f, listW - 20), 20, y + (rowH - 4 - f:getHeight()) / 2)
  end

  -- предпросмотр справа
  local g = self.items[self.sel]
  local px, pw = 326, W - 326 - 14
  local ph = math.floor(pw * 3 / 4)
  love.graphics.setColor(C.card)
  love.graphics.rectangle("fill", px, listY, pw, ph, 10)
  local img = self.still > 0.12 and getImage(g.image) or images[g.image or ""]
  if img then
    love.graphics.setColor(1, 1, 1)
    love.graphics.stencil(function() love.graphics.rectangle("fill", px, listY, pw, ph, 10) end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    drawContain(img, px, listY, pw, ph)
    love.graphics.setStencilTest()
  elseif not g.image or images[g.image] == false then
    love.graphics.stencil(function() love.graphics.rectangle("fill", px, listY, pw, ph, 10) end, "replace", 1)
    love.graphics.setStencilTest("greater", 0)
    drawPlaceholder(systems[g.sys], px, listY, pw, ph)
    love.graphics.setStencilTest()
  end
  local y = listY + ph + 10
  love.graphics.setColor(C.text)
  love.graphics.setFont(font(17, true))
  love.graphics.printf(shortName(g.name), px, y, pw, "left")
  local _, lines = font(17, true):getWrap(shortName(g.name), pw)
  y = y + #lines * font(17, true):getHeight() + 4
  local sys = systems[g.sys]
  local meta = { sys and (sys.fullname or sys.name) or "", g.year, g.genre }
  local m = {}
  for _, v in ipairs(meta) do if v and v ~= "" then m[#m + 1] = v end end
  love.graphics.setFont(font(13))
  love.graphics.setColor(C.dim)
  local metaText = table.concat(m, " · ")
  love.graphics.printf(metaText, px, y, pw, "left")
  local _, ml = font(13):getWrap(metaText, pw)
  y = y + #ml * font(13):getHeight() + 4
  local lp = lastPlayed(g)
  if lp > 0 then
    love.graphics.print("Запускали " .. ago(lp), px, y)
    y = y + 18
  end
  if g.desc then
    love.graphics.setColor(C.faint)
    local _, dl = font(13):getWrap(g.desc, pw)
    local maxLines = math.floor((H - 34 - y) / font(13):getHeight())
    for i = 1, math.min(#dl, maxLines) do
      love.graphics.print(dl[i], px, y + (i - 1) * font(13):getHeight())
    end
  end

  drawBar({ { "A", "Играть" }, { "Y", isFav(g) and "Из избранного" or "В избранное" },
            { "SELECT", "Параметры" }, { "L1/R1", "Листать" }, { "B", "Назад" } })
end

---------------------------------------------------------------- поиск

local KEYS = {
  "A", "B", "C", "D", "E", "F", "G", "H", "I", "J",
  "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T",
  "U", "V", "W", "X", "Y", "Z", "1", "2", "3", "4",
  "5", "6", "7", "8", "9", "0", "␣", "⌫", "OK",
}
local Search = {}
Search.__index = Search

local function openSearch()
  return setmetatable({ q = "", sel = 1, results = {} }, Search)
end

function Search:refresh()
  local q = self.q:lower()
  self.results = {}
  if q == "" then return end
  for _, g in ipairs(games) do
    if g.name:lower():find(q, 1, true) then self.results[#self.results + 1] = g end
  end
end

function Search:done()
  local l = openList("Поиск: " .. self.q, self.results, "Ничего не нашлось")
  l.back = self
  screen = l
end

function Search:press(b)
  local cols = 10
  if b == "dpleft" then self.sel = math.max(1, self.sel - 1)
  elseif b == "dpright" then self.sel = math.min(#KEYS, self.sel + 1)
  elseif b == "dpup" then self.sel = math.max(1, self.sel - cols)
  elseif b == "dpdown" then self.sel = math.min(#KEYS, self.sel + cols)
  elseif b == "a" then
    local k = KEYS[self.sel]
    if k == "⌫" then self.q = self.q:sub(1, -2)
    elseif k == "OK" then if self.q ~= "" then self:done() end return
    elseif k == "␣" then self.q = self.q .. " "
    else self.q = self.q .. k end
    self:refresh()
  elseif b == "x" then self.q = self.q:sub(1, -2); self:refresh()
  elseif b == "start" then if self.q ~= "" then self:done() end
  elseif b == "b" then
    if self.q ~= "" then self.q = self.q:sub(1, -2); self:refresh() else screen = self.back end
  end
end

function Search:update() end

function Search:draw()
  love.graphics.setColor(C.text)
  love.graphics.setFont(font(22, true))
  love.graphics.print("Поиск", 18, 12)
  drawStatus(16)

  love.graphics.setColor(C.card)
  love.graphics.rectangle("fill", 18, 52, W - 36, 44, 10)
  love.graphics.setFont(font(22))
  love.graphics.setColor(self.q == "" and C.faint or C.text)
  love.graphics.print(self.q == "" and "название игры…" or (self.q .. "_"), 32, 52 + (44 - font(22):getHeight()) / 2)
  love.graphics.setFont(font(15))
  love.graphics.setColor(C.dim)
  local cnt = self.q == "" and "" or (#self.results .. " найдено")
  love.graphics.print(cnt, W - 36 - font(15):getWidth(cnt), 52 + 14)

  local cols, kw, kh, gap = 10, 56, 44, 4
  local x0 = (W - (cols * kw + (cols - 1) * gap)) / 2
  local y0 = 112
  for i, k in ipairs(KEYS) do
    local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
    local x, y = x0 + c * (kw + gap), y0 + r * (kh + gap)
    local w = kw
    if k == "OK" then w = kw * 2 + gap end
    love.graphics.setColor(i == self.sel and accent() or C.card)
    love.graphics.rectangle("fill", x, y, w, kh, 8)
    love.graphics.setColor(i == self.sel and C.bg or C.text)
    love.graphics.setFont(font(20, true))
    love.graphics.printf(k, x, y + (kh - font(20, true):getHeight()) / 2, w, "center")
  end

  -- первые совпадения
  love.graphics.setFont(font(15))
  local y = y0 + 4 * (kh + gap) + 10
  for i = 1, math.min(4, #self.results) do
    love.graphics.setColor(C.dim)
    love.graphics.print(fit(shortName(self.results[i].name), font(15), W - 40), 22, y)
    y = y + 20
  end
  drawBar({ { "A", "Ввод" }, { "X", "Стереть" }, { "START", "Найти" }, { "B", "Назад" } })
end

---------------------------------------------------------------- меню

local Menu = {}
Menu.__index = Menu

local function openMenu()
  return setmetatable({ sel = 1, page = "main" }, Menu)
end

local function tileStyleIndex()
  for i, s in ipairs(TILE_STYLES) do if s.id == state.tileStyle then return i end end
  return 1
end

local MENU_TITLES = { main = "Меню", look = "Оформление", power = "Питание" }

function Menu:items()
  if self.page == "look" then
    return {
      { label = "Цвет акцента", value = ACCENTS[state.accent].name, kind = "accent" },
      { label = "Плитки систем", value = TILE_STYLES[tileStyleIndex()].name, kind = "tiles" },
    }
  elseif self.page == "power" then
    return {
      { label = "Сон", kind = "sleep" },
      { label = "Перезагрузить", kind = "reboot" },
      { label = "Выключить приставку", kind = "poweroff" },
    }
  end
  return {
    { label = "Громкость", value = getVolume() .. "%", kind = "volume", bar = getVolume() / 100 },
    { label = "Яркость", value = getBrightness() .. "%", kind = "bright", bar = getBrightness() / 100 },
    { label = "Wi‑Fi", value = wifiOn() and "вкл" or "выкл", kind = "wifi" },
    { label = "Доступ по сети (SSH)", kind = "remote" },
    { label = "Оформление", kind = "page", page = "look", sub = true },
    { label = "Скрапер картинок", kind = "scraper", sub = true },
    { label = "Перечитать библиотеку", kind = "rescan" },
    { label = "EmulationStation", kind = "es" },
    { label = "Питание", kind = "page", page = "power", sub = true },
  }
end

function Menu:press(b)
  local items = self:items()
  local it = items[self.sel]
  local function cycle(d)
    if it.kind == "wifi" then
      setWifi(not wifiOn())
      return
    elseif it.kind == "volume" then
      setVolume(getVolume() + d * 5)
      return
    elseif it.kind == "bright" then
      setBrightness(getBrightness() + d * 10)
      return
    elseif it.kind == "accent" then
      state.accent = (state.accent - 1 + d) % #ACCENTS + 1
    elseif it.kind == "tiles" then
      state.tileStyle = TILE_STYLES[(tileStyleIndex() - 1 + d) % #TILE_STYLES + 1].id
    else
      return
    end
    saveState()
  end
  if b == "dpup" then self.sel = math.max(1, self.sel - 1)
  elseif b == "dpdown" then self.sel = math.min(#items, self.sel + 1)
  elseif b == "dpleft" then cycle(-1)
  elseif b == "dpright" then cycle(1)
  elseif b == "a" then
    if it.kind == "accent" or it.kind == "tiles" or it.kind == "wifi" then cycle(1)
    elseif it.kind == "page" then self.back, self.page, self.sel = self.sel, it.page, 1
    elseif it.kind == "scraper" then overlay = nil; local s = openScraper(); s.back = screen; screen = s
    elseif it.kind == "rescan" then overlay = nil; images, imageOrder = {}, {}; loadLibrary(true)
    elseif it.kind == "remote" then
      os.execute("(sudo -n /roms/ports/home/net.sh remote >/dev/null 2>&1 &)")
      toast("Включаю Wi‑Fi и SSH, это до минуты")
    elseif it.kind == "es" then exitTo("es")
    elseif it.kind == "sleep" then overlay = nil; os.execute("sudo -n systemctl suspend")
    elseif it.kind == "reboot" then exitTo("reboot")
    elseif it.kind == "poweroff" then exitTo("poweroff")
    end
  elseif b == "b" and self.page ~= "main" then self.page, self.sel = "main", self.back or 1
  elseif b == "b" or b == "start" then overlay = nil
  end
end

function Menu:draw()
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", 0, 0, W, H)
  local items = self:items()
  local w, rowH = 400, 34
  local h = #items * rowH + 56
  local x, y = (W - w) / 2, (H - h) / 2
  love.graphics.setColor(C.bg2)
  love.graphics.rectangle("fill", x, y, w, h, 14)
  love.graphics.setFont(font(20, true))
  if self.page ~= "main" then
    love.graphics.setColor(C.faint)
    love.graphics.print("Меню ›", x + 20, y + 14)
    love.graphics.setColor(C.text)
    love.graphics.print(MENU_TITLES[self.page], x + 26 + font(20, true):getWidth("Меню ›"), y + 14)
  else
    love.graphics.setColor(C.text)
    love.graphics.print("Меню", x + 20, y + 14)
  end
  love.graphics.setFont(font(16))
  for i, it in ipairs(items) do
    local ry = y + 48 + (i - 1) * rowH
    if i == self.sel then
      love.graphics.setColor(accent())
      love.graphics.rectangle("fill", x + 10, ry, w - 20, rowH - 6, 8)
      love.graphics.setColor(C.bg)
    else
      love.graphics.setColor(C.text)
    end
    love.graphics.print(it.label, x + 22, ry + (rowH - 6 - font(16):getHeight()) / 2)
    if it.value then
      local v = "‹ " .. it.value .. " ›"
      love.graphics.print(v, x + w - 22 - font(16):getWidth(v), ry + (rowH - 6 - font(16):getHeight()) / 2)
    elseif it.sub then
      love.graphics.print("›", x + w - 26 - font(16):getWidth("›"), ry + (rowH - 6 - font(16):getHeight()) / 2)
    end
    if it.bar then
      -- ползунок между названием и значением
      local bx, bw = x + 150, w - 150 - 96
      local by = ry + (rowH - 6) / 2 - 3
      love.graphics.setColor(i == self.sel and {0, 0, 0, 0.25} or C.card)
      love.graphics.rectangle("fill", bx, by, bw, 6, 3)
      love.graphics.setColor(i == self.sel and C.bg or accent())
      love.graphics.rectangle("fill", bx, by, math.max(6, bw * math.min(1, it.bar)), 6, 3)
    end
  end
end

---------------------------------------------------------------- параметры запуска

local Opts = {}
Opts.__index = Opts

function openOpts(sys, game)
  if not sys then return nil end
  return setmetatable({ sys = sys, game = game, sel = 1 }, Opts)
end

function Opts:store()
  local key = self.game and self.game.path or sysKey(self.sys)
  local tab = self.game and state.gameOpts or state.sysOpts
  tab[key] = tab[key] or {}
  return tab[key]
end

function Opts:rows()
  local o = self:store()
  local emus = { false }
  for _, e in ipairs(self.sys.emulators) do emus[#emus + 1] = e.name end
  local emuName = o.emulator or select(1, lib.pick(launchArgs(self.game or { sys = self:sysIndex(), path = "" })))
  local cores = { false }
  for _, e in ipairs(self.sys.emulators) do
    if e.name == (o.emulator or emuName) then
      for _, c in ipairs(e.cores) do cores[#cores + 1] = c end
    end
  end
  return { { label = "Эмулятор", key = "emulator", list = emus }, { label = "Ядро", key = "core", list = cores } }
end

function Opts:sysIndex()
  for i, s in ipairs(systems) do if s == self.sys then return i end end
end

function Opts:press(b)
  local rows = self:rows()
  local r = rows[self.sel]
  local o = self:store()
  local function cycle(d)
    if #r.list < 2 then return end
    local idx = 1
    for i, v in ipairs(r.list) do if v == (o[r.key] or false) then idx = i end end
    idx = (idx - 1 + d) % #r.list + 1
    o[r.key] = r.list[idx] or nil
    if r.key == "emulator" then o.core = nil end
    saveState()
  end
  if b == "dpup" then self.sel = math.max(1, self.sel - 1)
  elseif b == "dpdown" then self.sel = math.min(#rows, self.sel + 1)
  elseif b == "dpleft" then cycle(-1)
  elseif b == "dpright" or b == "a" then cycle(1)
  elseif b == "b" or b == "back" or b == "start" then overlay = nil
  end
end

function Opts:draw()
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", 0, 0, W, H)
  local w, h = 440, 220
  local x, y = (W - w) / 2, (H - h) / 2
  love.graphics.setColor(C.bg2)
  love.graphics.rectangle("fill", x, y, w, h, 14)
  love.graphics.setColor(C.text)
  love.graphics.setFont(font(18, true))
  local title = self.game and shortName(self.game.name) or (self.sys.fullname or self.sys.name)
  love.graphics.print(fit(title, font(18, true), w - 40), x + 20, y + 14)
  love.graphics.setFont(font(13))
  love.graphics.setColor(C.dim)
  love.graphics.print(self.game and "Параметры этой игры" or "Параметры для всех игр системы", x + 20, y + 40)
  if #self.sys.emulators == 0 then
    love.graphics.setFont(font(15))
    love.graphics.printf("У этой системы один способ запуска, выбирать нечего.", x + 20, y + 90, w - 40, "left")
    return
  end
  local o = self:store()
  love.graphics.setFont(font(16))
  for i, r in ipairs(self:rows()) do
    local ry = y + 70 + (i - 1) * 40
    if i == self.sel then
      love.graphics.setColor(accent())
      love.graphics.rectangle("fill", x + 10, ry, w - 20, 34, 8)
      love.graphics.setColor(C.bg)
    else
      love.graphics.setColor(C.text)
    end
    love.graphics.print(r.label, x + 22, ry + 8)
    local v = "‹ " .. (o[r.key] or "как в ES") .. " ›"
    love.graphics.print(v, x + w - 22 - font(16):getWidth(v), ry + 8)
  end
  local g = self.game or { sys = self:sysIndex(), path = "" }
  local emu, core = lib.pick(launchArgs(g))
  love.graphics.setFont(font(13))
  love.graphics.setColor(C.dim)
  love.graphics.print("Запустится: " .. emu .. (core ~= "" and (" · " .. core) or ""), x + 22, y + h - 30)
end

---------------------------------------------------------------- скрапер

local SCRAPE_KINDS = { { id = "Named_Snaps", name = "скриншот" }, { id = "Named_Boxarts", name = "обложка" },
                       { id = "Named_Titles", name = "титульный экран" } }
local Scraper = {}
Scraper.__index = Scraper

local function fileExists(p)
  local f = p and io.open(p, "rb")
  if f then f:close() return true end
  return false
end

function openScraper()
  local s = setmetatable({ sel = 1, scope = 0, kind = 1, overwrite = false, sys = {} }, Scraper)
  for i, sys in ipairs(systems) do
    if (sys.count or 0) > 0 and lib.LIBRETRO[sys.name] then s.sys[#s.sys + 1] = i end
  end
  s:recount()
  return s
end

-- Какие игры пойдут в работу: без картинки (или с битой ссылкой), либо все при перезаписи
function Scraper:targets()
  local want = {}
  for k, i in ipairs(self.sys) do
    if self.scope == 0 or self.scope == k then want[i] = true end
  end
  local jobs, n = {}, 0
  for _, g in ipairs(games) do
    if want[g.sys] and (self.overwrite or not fileExists(g.image)) then
      local sys = systems[g.sys]
      local j = jobs[g.sys]
      if not j then
        j = { dir = sys.path, title = sys.fullname or sys.name, playlist = lib.LIBRETRO[sys.name], games = {} }
        jobs[g.sys] = j
      end
      j.games[#j.games + 1] = { path = g.path, base = lib.baseName(g.path), name = g.name }
      n = n + 1
    end
  end
  local list = {}
  for _, j in pairs(jobs) do list[#list + 1] = j end
  table.sort(list, function(a, b) return a.title < b.title end)
  return list, n
end

function Scraper:recount() self.jobs, self.count = self:targets() end

function Scraper:rows()
  local scope = "все (" .. #self.sys .. ")"
  if self.scope > 0 then
    local sys = systems[self.sys[self.scope]]
    scope = sys.fullname or sys.name
  end
  return {
    { label = "Системы", value = scope, key = "scope" },
    { label = "Картинка", value = SCRAPE_KINDS[self.kind].name, key = "kind" },
    { label = "Заменять готовые", value = self.overwrite and "да" or "нет", key = "overwrite" },
    { label = "Начать (" .. self.count .. " игр)", key = "start" },
  }
end

function Scraper:start()
  if self.count == 0 then toast("Все картинки уже на месте") return end
  for _, name in ipairs({ "scrape", "scrape_ctl" }) do
    local ch = love.thread.getChannel(name)
    while ch:pop() do end
  end
  self.thread = love.thread.newThread("scrape.lua")
  self.thread:start({ jobs = self.jobs, kind = SCRAPE_KINDS[self.kind].id, overwrite = self.overwrite,
                      cacert = love.filesystem.getSource() .. "/cacert.pem", wifiOff = not wifiOn() })
  self.run = { status = "Запускаю…", i = 0, n = self.count, found = 0 }
end

function Scraper:busy() return self.run and not self.run.done end

function Scraper:update()
  if not self.run or self.run.done then return end
  local ch = love.thread.getChannel("scrape")
  while true do
    local m = ch:pop()
    if not m then break end
    if m.kind == "status" then self.run.status = m.text
    elseif m.kind == "progress" then
      self.run.status, self.run.title = nil, m.title
      self.run.i, self.run.n, self.run.found, self.run.game = m.i, m.n, m.found, m.game
    elseif m.kind == "done" then
      self.run.done, self.run.found, self.run.err, self.run.stopped = true, m.found, m.err, m.stopped
      images, imageOrder = {}, {}
      loadLibrary(true)
      self:recount()
    end
  end
  local err = self.thread and self.thread:getError()
  if err and not self.run.done then self.run.done, self.run.err = true, err end
end

function Scraper:press(b)
  if self.run and not self.run.done then
    if b == "b" and not self.run.stopping then
      love.thread.getChannel("scrape_ctl"):push("stop")
      self.run.stopping = true
    end
    return
  end
  if self.run then
    if b == "a" or b == "b" then self.run = nil end
    return
  end
  local rows = self:rows()
  local r = rows[self.sel]
  local function cycle(d)
    if r.key == "scope" then self.scope = (self.scope + d) % (#self.sys + 1)
    elseif r.key == "kind" then self.kind = (self.kind - 1 + d) % #SCRAPE_KINDS + 1
    elseif r.key == "overwrite" then self.overwrite = not self.overwrite
    else return end
    self:recount()
  end
  if b == "dpup" then self.sel = math.max(1, self.sel - 1)
  elseif b == "dpdown" then self.sel = math.min(#rows, self.sel + 1)
  elseif b == "dpleft" then cycle(-1)
  elseif b == "dpright" then cycle(1)
  elseif b == "a" then if r.key == "start" then self:start() else cycle(1) end
  elseif b == "b" then screen = self.back
  end
end

function Scraper:draw()
  love.graphics.setColor(C.text)
  love.graphics.setFont(font(22, true))
  love.graphics.print("Скрапер картинок", 18, 12)
  drawStatus(16)
  love.graphics.setFont(font(13))
  love.graphics.setColor(C.dim)
  love.graphics.printf("Картинки из открытой базы libretro-thumbnails. Ищет по имени файла игры, " ..
    "нужен Wi‑Fi: если он выключен, включится на время работы.", 18, 44, W - 36, "left")

  if self.run then
    local r = self.run
    local y = 120
    love.graphics.setFont(font(18, true))
    love.graphics.setColor(C.text)
    local head = r.done and (r.err and "Не получилось" or (r.stopped and "Остановлено" or "Готово"))
                 or r.status or r.title or ""
    love.graphics.print(fit(head, font(18, true), W - 36), 18, y)
    y = y + 36
    love.graphics.setColor(C.card)
    love.graphics.rectangle("fill", 18, y, W - 36, 12, 6)
    love.graphics.setColor(accent())
    love.graphics.rectangle("fill", 18, y, math.max(12, (W - 36) * (r.n > 0 and r.i / r.n or 0)), 12, 6)
    y = y + 26
    love.graphics.setFont(font(16))
    love.graphics.setColor(C.dim)
    love.graphics.print(r.i .. " из " .. r.n .. " · найдено " .. r.found, 18, y)
    y = y + 28
    love.graphics.setColor(C.faint)
    love.graphics.setFont(font(14))
    if r.err then
      love.graphics.setColor(1, 0.5, 0.45)
      love.graphics.printf(tostring(r.err), 18, y, W - 36, "left")
    elseif not r.done and r.game then
      love.graphics.print(fit(shortName(r.game), font(14), W - 36), 18, y)
    elseif r.done then
      love.graphics.printf("Библиотека перечитана. Чего не нашлось — у тех игр имя файла не совпало с базой.",
        18, y, W - 36, "left")
    end
    if r.done then drawBar({ { "A", "Хорошо" } })
    else drawBar({ { "B", r.stopping and "Останавливаю…" or "Остановить" } }) end
    return
  end

  if #self.sys == 0 then
    love.graphics.setFont(font(16))
    love.graphics.setColor(C.dim)
    love.graphics.printf("Для ваших систем в базе ничего нет.", 18, 200, W - 36, "center")
    drawBar({ { "B", "Назад" } })
    return
  end
  local w, rowH, x, y = W - 36, 40, 18, 110
  love.graphics.setFont(font(17))
  for i, r in ipairs(self:rows()) do
    local ry = y + (i - 1) * rowH
    if i == self.sel then
      love.graphics.setColor(accent())
      love.graphics.rectangle("fill", x, ry, w, rowH - 6, 8)
      love.graphics.setColor(C.bg)
    else
      love.graphics.setColor(C.text)
    end
    local ty = ry + (rowH - 6 - font(17):getHeight()) / 2
    love.graphics.print(r.label, x + 14, ty)
    if r.value then
      local v = "‹ " .. fit(r.value, font(17), w - 260) .. " ›"
      love.graphics.print(v, x + w - 14 - font(17):getWidth(v), ty)
    end
  end
  love.graphics.setFont(font(13))
  love.graphics.setColor(C.faint)
  love.graphics.printf("Картинки ложатся в папку images системы и прописываются в gamelist.xml — " ..
    "их увидит и EmulationStation. Копия старого gamelist: gamelist.xml.home-bak.",
    18, y + 4 * rowH + 14, W - 36, "left")
  drawBar({ { "A", "Выбрать" }, { "←→", "Изменить" }, { "B", "Назад" } })
end

---------------------------------------------------------------- главный экран

local Home = { row = 1, card = 1, cardLeft = 1, tile = 1, tileTop = 0 }
local CARDS_SHOWN, CARD_MAX = 3, 10
local COLS = 4

function Home:press(b)
  local nCards = math.min(#recent, CARD_MAX)
  if self.row == 1 and nCards == 0 then self.row = 2 end
  if self.row == 1 then
    if b == "dpleft" then self.card = math.max(1, self.card - 1)
    elseif b == "dpright" then self.card = math.min(nCards, self.card + 1)
    elseif b == "dpdown" then self.row = 2
    elseif b == "a" then launch(recent[self.card])
    elseif b == "y" then toggleFav(recent[self.card])
    elseif b == "back" then overlay = openOpts(systems[recent[self.card].sys], recent[self.card])
    end
  else
    local t = self.tile
    if b == "dpleft" then self.tile = math.max(1, t - 1)
    elseif b == "dpright" then self.tile = math.min(#tiles, t + 1)
    elseif b == "dpdown" then self.tile = math.min(#tiles, t + COLS)
    elseif b == "dpup" then
      if t <= COLS then if nCards > 0 then self.row = 1 end else self.tile = t - COLS end
    elseif b == "back" and tiles[t].kind == "system" then
      overlay = openOpts(systems[tiles[t].sys])
    elseif b == "a" then
      local tile = tiles[t]
      local l
      if tile.kind == "search" then
        l = openSearch()
      elseif tile.kind == "recent" then
        l = openList("Недавние", recent, "Вы ещё ничего не запускали")
      elseif tile.kind == "favs" then
        l = openList("Избранное", favorites, "Отметьте игру кнопкой Y")
      else
        local items = {}
        for _, g in ipairs(games) do if g.sys == tile.sys then items[#items + 1] = g end end
        l = openList(tile.label, items)
      end
      l.back = self
      screen = l
    end
  end
  if b == "x" then
    local s = openSearch(); s.back = self; screen = s
  end
end

function Home:update() end

function Home:draw()
  -- шапка
  local d = os.date("*t")
  love.graphics.setColor(C.text)
  love.graphics.setFont(font(24, true))
  love.graphics.print(WEEKDAYS[d.wday] .. ", " .. d.day .. " " .. MONTHS[d.month], 18, 12)
  drawStatus(18)
  love.graphics.setFont(font(13))
  love.graphics.setColor(C.faint)
  local total = #games .. " игр"
  love.graphics.print(total, W - 18 - font(13):getWidth(total), 40)

  -- Продолжить
  local nCards = math.min(#recent, CARD_MAX)
  local y = 48
  love.graphics.setFont(font(14, true))
  love.graphics.setColor(C.dim)
  love.graphics.print("Продолжить", 18, y)
  y = y + 22
  local cw, ch, gap = 190, 128, 12
  if nCards == 0 then
    love.graphics.setColor(C.card)
    love.graphics.rectangle("fill", 18, y, W - 36, ch, 12)
    love.graphics.setColor(C.faint)
    love.graphics.setFont(font(15))
    love.graphics.printf("Здесь появятся игры, которые вы запускали", 18, y + ch / 2 - 10, W - 36, "center")
  else
    if self.card < self.cardLeft then self.cardLeft = self.card end
    if self.card >= self.cardLeft + CARDS_SHOWN then self.cardLeft = self.card - CARDS_SHOWN + 1 end
    for i = self.cardLeft, math.min(nCards, self.cardLeft + CARDS_SHOWN - 1) do
      local g = recent[i]
      local x = (W - (CARDS_SHOWN * cw + (CARDS_SHOWN - 1) * gap)) / 2 + (i - self.cardLeft) * (cw + gap)
      love.graphics.setColor(C.card)
      love.graphics.rectangle("fill", x, y, cw, ch, 12)
      local img = getImage(g.image)
      local imgH = ch - 44
      love.graphics.stencil(function() love.graphics.rectangle("fill", x, y, cw, ch, 12) end, "replace", 1)
      love.graphics.setStencilTest("greater", 0)
      if img and img:getWidth() < img:getHeight() * 1.15 then
        -- значки и вертикальные обложки целиком, а не обрезкой
        love.graphics.setColor(C.bg2)
        love.graphics.rectangle("fill", x, y, cw, imgH)
        love.graphics.setColor(1, 1, 1)
        drawContain(img, x, y + 6, cw, imgH - 12)
      elseif img then
        love.graphics.setColor(1, 1, 1)
        drawCover(img, x, y, cw, imgH)
      else
        drawPlaceholder(systems[g.sys], x, y, cw, imgH)
      end
      love.graphics.setStencilTest()
      local sys = systems[g.sys]
      love.graphics.setColor(C.text)
      love.graphics.setFont(font(14, true))
      love.graphics.print(fit(shortName(g.name), font(14, true), cw - 16), x + 8, y + imgH + 5)
      love.graphics.setColor(C.dim)
      love.graphics.setFont(font(12))
      local sub = (sys and (sys.name:upper()) or "") .. " · " .. ago(lastPlayed(g))
      love.graphics.print(fit(sub, font(12), cw - 16), x + 8, y + imgH + 24)
      if isFav(g) then
        love.graphics.setColor(1, 0.8, 0.2)
        love.graphics.setFont(font(16, true))
        love.graphics.print("★", x + cw - 22, y + 4)
      end
      if self.row == 1 and i == self.card then focusRing(x, y, cw, ch, 12) end
    end
    -- стрелки, если есть ещё
    love.graphics.setColor(C.faint)
    love.graphics.setFont(font(16, true))
    if self.cardLeft > 1 then love.graphics.print("‹", 4, y + ch / 2 - 10) end
    if self.cardLeft + CARDS_SHOWN - 1 < nCards then love.graphics.print("›", W - 12, y + ch / 2 - 10) end
  end

  -- Библиотека
  y = y + ch + 12
  love.graphics.setFont(font(14, true))
  love.graphics.setColor(C.dim)
  love.graphics.print("Библиотека", 18, y)
  y = y + 22
  local tw, th, tg = 140, 92, 12
  local visibleRows = 2
  local row = math.floor((self.tile - 1) / COLS)
  if row < self.tileTop then self.tileTop = row end
  if row >= self.tileTop + visibleRows then self.tileTop = row - visibleRows + 1 end
  for i, tile in ipairs(tiles) do
    local r, c = math.floor((i - 1) / COLS), (i - 1) % COLS
    if r >= self.tileTop and r < self.tileTop + visibleRows then
      local x = (W - (COLS * tw + (COLS - 1) * tg)) / 2 + c * (tw + tg)
      local ty = y + (r - self.tileTop) * (th + 10)
      local sys = tile.kind == "system" and systems[tile.sys]
      local minimal = state.tileStyle == "minimal"
      local cap = sys and state.tileStyle == "covers" and sysArt(sys, "capsule")
      local logo = sys and not cap and not minimal and sysArt(sys, "logo")
      love.graphics.setColor(minimal and C.card or tile.color or accent())
      love.graphics.rectangle("fill", x, ty, tw, th, 12)
      if minimal then
        -- одноцветный геймпад системы и подпись; у служебных плиток — значок цвета акцента
        local focused = self.row == 2 and i == self.tile
        local pad = sys and padImage(sys)
        if pad then
          love.graphics.setColor(1, 1, 1, focused and 0.95 or 0.7)
          drawContain(pad, x + 18, ty + 12, tw - 36, th - 42)
        end
        love.graphics.setColor(focused and C.text or C.dim)
        love.graphics.setFont(font(13, true))
        love.graphics.printf(fit(sys and sys.name:upper() or tile.label, font(13, true), tw - 16),
          x + 8, ty + th - 24, tw - 16, "center")
      elseif cap then
        -- обложка 192×288: вырезаем полосу вокруг логотипа (он ниже середины)
        love.graphics.stencil(function() love.graphics.rectangle("fill", x, ty, tw, th, 12) end, "replace", 1)
        love.graphics.setStencilTest("greater", 0)
        local iw, ih = cap:getDimensions()
        local s = tw / iw
        local srcH = th / s
        local top = math.max(0, math.min(ih - srcH, ih * 0.64 - srcH / 2))
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(cap, love.graphics.newQuad(0, top, iw, srcH, iw, ih), x, ty, 0, s, s)
        love.graphics.setStencilTest()
      elseif logo then
        love.graphics.setColor(1, 1, 1)
        drawContain(logo, x + 10, ty + 18, tw - 20, th - 40)
      end
      -- значки служебных плиток: в минимализме крупно по центру, иначе в углу
      local ix, iy, k = x + 26, ty + 26, 1
      if minimal then ix, iy, k = x + tw / 2, ty + 36, 1.5 end
      love.graphics.setColor(minimal and accent() or {0, 0, 0, 0.55})
      love.graphics.setLineWidth(3)
      if tile.kind == "search" then
        love.graphics.circle("line", ix - 2 * k, iy - 4 * k, 9 * k)
        love.graphics.line(ix + 5 * k, iy + 3 * k, ix + 12 * k, iy + 10 * k)
      elseif tile.kind == "recent" then
        love.graphics.circle("line", ix, iy, 11 * k)
        love.graphics.line(ix, iy - 7 * k, ix, iy, ix + 5 * k, iy + 4 * k)
      elseif tile.icon then
        local f = font(minimal and 34 or 28, true)
        love.graphics.setFont(f)
        if minimal then love.graphics.print(tile.icon, ix - f:getWidth(tile.icon) / 2, iy - f:getHeight() / 2)
        else love.graphics.print(tile.icon, x + 12, ty + 8) end
      end
      love.graphics.setLineWidth(1)
      if not cap and not logo and not minimal then
        love.graphics.setColor(0.05, 0.06, 0.08)
        love.graphics.setFont(font(15, true))
        local _, lines = font(15, true):getWrap(tile.label, tw - 20)
        local ly = ty + th - 10 - #lines * font(15, true):getHeight()
        for li, l in ipairs(lines) do
          if li <= 2 then love.graphics.print(l, x + 10, ly + (li - 1) * font(15, true):getHeight()) end
        end
      end
      if tile.count then
        love.graphics.setFont(font(13, true))
        local cs = tostring(tile.count)
        local cw2 = font(13, true):getWidth(cs) + 12
        love.graphics.setColor(minimal and {1, 1, 1, 0.08} or {0, 0, 0, sys and 0.55 or 0.25})
        love.graphics.rectangle("fill", x + tw - 8 - cw2, ty + 8, cw2, 20, 10)
        love.graphics.setColor(minimal and C.dim or sys and C.text or {0, 0, 0, 0.7})
        love.graphics.print(cs, x + tw - 8 - cw2 + 6, ty + 8 + (20 - font(13, true):getHeight()) / 2)
      end
      if self.row == 2 and i == self.tile then focusRing(x, ty, tw, th, 12) end
    end
  end
  local totalRows = math.ceil(#tiles / COLS)
  if totalRows > visibleRows then
    love.graphics.setColor(C.faint)
    love.graphics.setFont(font(12))
    love.graphics.print((self.tileTop + 1) .. "–" .. math.min(totalRows, self.tileTop + visibleRows) .. " из " .. totalRows,
      W - 80, y - 20)
  end

  local hints = { { "A", self.row == 1 and "Играть" or "Открыть" } }
  if self.row == 1 then hints[#hints + 1] = { "Y", "Избранное" } end
  if self.row == 1 or (tiles[self.tile] and tiles[self.tile].kind == "system") then
    hints[#hints + 1] = { "SELECT", "Параметры" }
  end
  hints[#hints + 1] = { "X", "Поиск" }
  hints[#hints + 1] = { "START", "Меню" }
  drawBar(hints)
end

---------------------------------------------------------------- LÖVE

-- Процент от датчика RK817 врёт, поэтому считаем по напряжению:
-- под нагрузкой оно проседает, добавляем ток × внутреннее сопротивление.
local OCV = { {4.20, 100}, {4.10, 90}, {4.00, 80}, {3.92, 70}, {3.85, 60}, {3.79, 50},
              {3.75, 40}, {3.71, 30}, {3.67, 20}, {3.62, 12}, {3.55, 6}, {3.45, 2}, {3.30, 0} }
local R_INT = 0.15
local smoothV

local function voltagePercent(v)
  if v >= OCV[1][1] then return 100 end
  for i = 2, #OCV do
    local hi, lo = OCV[i - 1], OCV[i]
    if v >= lo[1] then
      return math.floor(lo[2] + (hi[2] - lo[2]) * (v - lo[1]) / (hi[1] - lo[1]) + 0.5)
    end
  end
  return 0
end

local function readSystemStatus()
  local st = readLine("/sys/class/power_supply/battery/status") or ""
  charging = st == "Charging" or st == "Full"
  local v = tonumber(readLine("/sys/class/power_supply/battery/voltage_now") or "")
  local i = tonumber(readLine("/sys/class/power_supply/battery/current_now") or "") or 0
  if v and not charging then
    local ocv = v / 1e6 - (i / 1e6) * R_INT       -- при разряде ток отрицательный
    smoothV = smoothV and (smoothV * 0.7 + ocv * 0.3) or ocv
    battery = voltagePercent(smoothV)
  else
    smoothV, battery = nil, nil
  end
  wifi = (readLine("/sys/class/net/wlan0/operstate") or "") == "up"
end

local splash = 0              -- кадры заставки; false — библиотека готова

function love.load()
  W, H = love.graphics.getDimensions()
  love.graphics.setBackgroundColor(C.bg)
  if love.filesystem.getInfo("gamecontrollerdb.txt") then
    love.joystick.loadGamepadMappings("gamecontrollerdb.txt")
  end
  local s = loadLua("state.lua")
  if s then for k, v in pairs(s) do state[k] = v end end
  if not ACCENTS[state.accent] then state.accent = 1 end
  if state.plainTiles ~= nil then
    state.tileStyle = state.plainTiles and "color" or "covers"
    state.plainTiles = nil
  end
  readSystemStatus()
  startOsd()
  screen = Home
end

function love.joystickadded(j) stick = stick or j end

local function press(b)
  if launching or splash then return end
  if overlay then overlay:press(b) return end
  if b == "start" and screen == Home then overlay = openMenu() return end
  screen:press(b)
end

local REPEATABLE = { dpup = true, dpdown = true, dpleft = true, dpright = true }

function love.gamepadpressed(_, b)
  press(b)
  if REPEATABLE[b] then repeatBtn, repeatT = b, 0.35 end
end
function love.gamepadreleased(_, b) if b == repeatBtn then repeatBtn = nil end end

local KEYMAP = { up = "dpup", down = "dpdown", left = "dpleft", right = "dpright",
  ["return"] = "a", space = "a", escape = "b", backspace = "b", x = "x", y = "y",
  s = "start", q = "leftshoulder", e = "rightshoulder" }
function love.keypressed(k) if KEYMAP[k] then press(KEYMAP[k]) end end

function love.update(dt)
  if splash then
    splash = splash + 1
    if splash > 2 then loadLibrary(false); splash = false end
    return
  end
  if launching then
    launching.t = launching.t + dt
    if launching.t > 0.15 then love.event.quit() end
    return
  end
  if stick then
    local ax, ay = stick:getGamepadAxis("leftx"), stick:getGamepadAxis("lefty")
    local d
    if math.max(math.abs(ax), math.abs(ay)) > 0.55 then
      if math.abs(ax) > math.abs(ay) then d = ax > 0 and "dpright" or "dpleft"
      else d = ay > 0 and "dpdown" or "dpup" end
    elseif math.max(math.abs(ax), math.abs(ay)) > 0.3 then
      d = stickDir                        -- зона гистерезиса: не дребезжать
    end
    if d ~= stickDir then
      stickDir = d
      if d then press(d); stickT = 0.35 end
    elseif d then
      stickT = stickT - dt
      if stickT <= 0 then press(d); stickT = 0.07 end
    end
  end
  if repeatBtn and stick and stick:isGamepadDown(repeatBtn) then
    repeatT = repeatT - dt
    if repeatT <= 0 then press(repeatBtn); repeatT = 0.07 end
  elseif repeatBtn then
    repeatBtn = nil
  end
  if toastT > 0 then toastT = toastT - dt; if toastT <= 0 then toastText = nil end end
  updateOsd(dt)
  sysTimer = sysTimer + dt
  if sysTimer > 10 then sysTimer = 0; readSystemStatus() end
  if screen.update then screen:update(dt) end
end

local function drawFrame()
  love.graphics.clear(C.bg)
  if splash then
    -- последний кадр загрузочного видео, чтобы переход был незаметен
    love.graphics.clear(0, 0, 0)
    logo.draw(nil, W / 2, H / 2, 132, font(30, true), font(15))
    love.graphics.setColor(C.faint)
    love.graphics.setFont(font(13))
    love.graphics.printf("Собираю библиотеку…", 0, H - 44, W, "center")
    return
  end
  if launching then drawLoading(launching.game) return end
  screen:draw()
  if overlay then overlay:draw() end
  drawToast()
  drawOsd()
end

function love.draw()
  if wantShot then
    wantShot = false
    pcall(function()
      local cv = love.graphics.newCanvas(W, H)
      love.graphics.push("all")
      love.graphics.setCanvas({ cv, stencil = true })
      drawFrame()
      love.graphics.pop()
      cv:newImageData():encode("png", "shot.png")
    end)
  end
  drawFrame()
end

-- amixer events висит в потоке на чтении: гасим его, чтобы LÖVE вышел сразу
function love.quit() saveState(); stopOsd() end

-- При ошибке не показывать экран LÖVE, который ждёт клавиатуру: пишем в лог
-- и выходим — boot.sh откроет EmulationStation.
function love.errorhandler(msg)
  print("HOME ERROR: " .. tostring(msg) .. "\n" .. debug.traceback())
  stopOsd()
  return function() return 1 end
end

-- Свой цикл: без ввода экран перерисовывается раз в секунду,
-- иначе LÖVE рисует 60 кадров в секунду и зря жжёт батарею.
function love.run()
  love.load(love.arg.parseGameArguments(arg), arg)
  love.timer.step()
  local busyUntil, lastDraw = 0, -1
  return function()
    love.event.pump()
    for name, a, b, c, d, e, f in love.event.poll() do
      if name == "quit" then
        if not love.quit or not love.quit() then return a or 0 end
      end
      love.handlers[name](a, b, c, d, e, f)
      busyUntil = love.timer.getTime() + 0.6
    end
    love.update(love.timer.step())
    local now = love.timer.getTime()
    if splash or launching or repeatBtn or stickDir or toastText or osd or (screen.busy and screen:busy()) then
      busyUntil = math.max(busyUntil, now + 0.1)
    end
    local busy = now < busyUntil
    if busy or now - lastDraw >= 1 then
      love.graphics.origin()
      love.draw()
      love.graphics.present()
      lastDraw = now
    end
    love.timer.sleep(busy and 0.016 or 0.1)
  end
end
