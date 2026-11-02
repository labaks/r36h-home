-- Поток скрапера: картинки из базы libretro-thumbnails (thumbnails.libretro.com).
-- Бесплатно и без ключа. Ищет по имени файла ROM (No-Intro/Redump), затем без
-- скобок с регионом, из нескольких регионов берёт USA/World/Europe.
-- Вход: {jobs = {{dir, title, playlist, games = {{path, base, name}}}}, kind, overwrite,
--        cacert, wifiOff}; выход — сообщения в канал "scrape", стоп — канал "scrape_ctl".

require("love.thread")
require("love.filesystem")
local lib = require("library")

local req = ...
local out = love.thread.getChannel("scrape")
local ctl = love.thread.getChannel("scrape_ctl")
local BASE = "https://thumbnails.libretro.com/"
local NET = "sudo -n /roms/ports/home/net.sh "

local stop = false
local function stopped()
  if ctl:pop() then stop = true end
  return stop
end

local function curl(args)
  local ca = req.cacert and (" --cacert " .. lib.shq(req.cacert)) or ""
  return "curl -sfL --retry 2 --connect-timeout 15" .. ca .. " " .. args
end

-- Через файл, а не io.popen: поток, ждущий чтения из popen, держит блокировку stdio,
-- и главный поток Home замирает на своих popen (громкость, Wi‑Fi) до конца загрузки.
local TMP = "/dev/shm/home_scrape.html"
local function fetch(url, maxTime)
  os.execute(curl("--max-time " .. (maxTime or 90) .. " -o " .. TMP .. " " .. lib.shq(url)) .. " 2>/dev/null")
  local s = lib.readFile(TMP)
  os.remove(TMP)
  return s ~= "" and s or nil
end

local function download(url, file)
  os.execute(curl("--max-time 40 -o " .. lib.shq(file) .. " " .. lib.shq(url)) .. " 2>/dev/null")
  local f = io.open(file, "rb")
  local head = f and f:read(4)
  if f then f:close() end
  if head == "\137PNG" then return true end
  os.remove(file)
  return false
end

local function urlenc(s)
  return (s:gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end))
end
local function urldec(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- Ключи сравнения: полный (с регионом) и базовый (без скобок, без артикля The)
local function key(s) return (s:lower():gsub("[^%w]", "")) end
local function baseKey(s)
  s = s:lower():gsub("%b()", ""):gsub("%b[]", ""):gsub("%s+$", "")
  s = s:gsub(",%s*the$", ""):gsub(",%s*the%s+%-", " -"):gsub("^the%s+", "")
  return (s:gsub("[^%w]", ""))
end

local function tags(name)
  local t = {}
  for inner in name:gmatch("%((.-)%)") do
    for w in inner:gmatch("[^,]+") do t[#t + 1] = w:lower():gsub("^%s+", ""):gsub("%s+$", "") end
  end
  return t
end

local function score(cand, romTags)
  local l = cand:lower()
  local s = 0
  if l:find("usa", 1, true) then s = s + 4 end
  if l:find("world", 1, true) then s = s + 3 end
  if l:find("europe", 1, true) then s = s + 2 end
  for _, bad in ipairs({ "beta", "proto", "demo", "sample", "[b]", "[h" }) do
    if l:find(bad, 1, true) then s = s - 5 end
  end
  for _, t in ipairs(romTags) do
    if t ~= "" and l:find(t, 1, true) then s = s + 1.5 end
  end
  return s - #cand / 1000
end

-- Список картинок папки: HTML-индекс сервера, ссылки вида href="Name%20(USA).png"
local function listing(playlist)
  local html = fetch(BASE .. urlenc(playlist) .. "/" .. req.kind .. "/", 60)
  if not html then return nil end
  local exact, byBase = {}, {}
  local pos = 1
  while true do
    local a = html:find('href="', pos, true)
    if not a then break end
    local b = html:find('"', a + 6, true)
    if not b then break end
    local href = html:sub(a + 6, b - 1)
    pos = b + 1
    if href:sub(-4) == ".png" and href:sub(1, 1) ~= "/" and href:sub(1, 1) ~= "?" then
      local name = urldec(href):sub(1, -5)
      exact[key(name)] = exact[key(name)] or name
      local bk = baseKey(name)
      byBase[bk] = byBase[bk] or {}
      table.insert(byBase[bk], name)
    end
  end
  return exact, byBase
end

local function match(g, exact, byBase)
  for _, n in ipairs({ g.base, g.name }) do
    local hit = n and exact[key(n)]
    if hit then return hit end
  end
  for _, n in ipairs({ g.base, g.name }) do
    local cands = n and byBase[baseKey(n)]
    if cands then
      local rt = tags(g.base)
      local best, bs
      for _, c in ipairs(cands) do
        local s = score(c, rt)
        if not bs or s > bs then best, bs = c, s end
      end
      return best
    end
  end
end

-- Догадки об имени в базе: регионы GoodTools (U)/(J)/(W)… → No-Intro (USA)/(Japan)/(World),
-- переводы и хаки [T+Rus…] отбрасываем. Обычно хватает одного-двух коротких запросов —
-- список папки (у NES 4,8 МБ) через слабый Wi‑Fi приставки качается минутами.
local GOOD = { U = "USA", E = "Europe", J = "Japan", W = "World", F = "France", G = "Germany",
               S = "Spain", I = "Italy", K = "Korea", A = "Australia", B = "Brazil", C = "China",
               JU = "Japan, USA", UE = "USA, Europe", JE = "Japan, Europe", JUE = "Japan, USA, Europe" }
local LIBRETRO_BAD = '[&%*/:`<>%?\\|"]'   -- эти символы libretro заменяет на «_»
local DEFAULT = { "USA", "World", "USA, Europe", "Europe", "Japan, USA", "Japan" }

local function clean(s)
  s = s:gsub("%b[]", ""):gsub("%b()", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  s = s:gsub("%s*:%s*", " - ")                         -- «Abadox : The…» из gamelist → «Abadox - The…»
  return (s:gsub(LIBRETRO_BAD, "_"))            -- так libretro переименовывает файлы
end

local function guesses(g)
  local out, seen = {}, {}
  local function add(n) if n and n ~= "" and not seen[n] then seen[n] = true; out[#out + 1] = n end end
  if not g.base:find("[", 1, true) then add((g.base:gsub(LIBRETRO_BAD, "_"))) end
  local regions = {}
  for inner in g.base:gmatch("%((.-)%)") do
    if GOOD[inner] then regions[#regions + 1] = GOOD[inner] end
    if inner:find("USA") or inner:find("Europe") or inner:find("Japan") or inner:find("World") then
      regions[#regions + 1] = inner
    end
  end
  for _, r in ipairs(DEFAULT) do regions[#regions + 1] = r end
  local titles = {}
  for _, n in ipairs({ g.base, g.name }) do
    local t = n and clean(n)
    if t and t ~= "" then
      titles[#titles + 1] = t
      local rest = t:match("^The (.+)$")
      if rest then
        local head, tail = rest:match("^(.-)( %- .+)$")
        titles[#titles + 1] = head and (head .. ", The" .. tail) or (rest .. ", The")
      end
    end
  end
  for _, t in ipairs(titles) do
    for _, r in ipairs(regions) do add(t .. " (" .. r .. ")") end
  end
  local lim = {}
  for i = 1, math.min(8, #out) do lim[i] = out[i] end
  return lim
end

local total, found = 0, 0
for _, j in ipairs(req.jobs) do total = total + #j.games end

if req.wifiOff then
  out:push({ kind = "status", text = "Включаю Wi‑Fi…" })
  os.execute(NET .. "on >/dev/null 2>&1")
end
out:push({ kind = "status", text = "Проверяю связь с базой…" })
if not fetch(BASE, 20) then
  if req.wifiOff then os.execute(NET .. "off >/dev/null 2>&1") end
  out:push({ kind = "done", found = 0, total = total, err = "Нет связи с thumbnails.libretro.com" })
  return
end

local done = 0
for _, j in ipairs(req.jobs) do
  if stopped() then break end
  local folder = BASE .. urlenc(j.playlist) .. "/" .. req.kind .. "/"
  local exact, byBase, listTried
  local hits = {}
  os.execute("mkdir -p " .. lib.shq(j.dir .. "/images"))
  for _, g in ipairs(j.games) do
    if stopped() then break end
    done = done + 1
    out:push({ kind = "progress", title = j.title, i = done, n = total, found = found, game = g.name })
    local file = j.dir .. "/images/" .. g.base .. "-image.png"
    local ok = false
    for _, n in ipairs(guesses(g)) do
      if download(folder .. urlenc(n) .. ".png", file) then ok = true break end
      if stopped() then break end
    end
    -- не угадали — один раз на систему берём список папки и ищем по нему (минута максимум)
    if not ok and not stop then
      if not listTried then
        listTried = true
        out:push({ kind = "progress", title = j.title, i = done, n = total, found = found, game = "загружаю список базы…" })
        exact, byBase = listing(j.playlist)
      end
      local name = exact and match(g, exact, byBase)
      ok = name and download(folder .. urlenc(name) .. ".png", file) or false
    end
    if ok then
      hits[g.path] = "./images/" .. g.base .. "-image.png"
      found = found + 1
    end
  end
  -- картинки качали только для игр без рабочей картинки или с перезаписью — пишем всегда
  if next(hits) then lib.setImages(j.dir, hits, true) end
end

if req.wifiOff then os.execute(NET .. "off >/dev/null 2>&1") end
out:push({ kind = "done", found = found, total = total, stopped = stop })
