-- Библиотека игр: читает то же, что EmulationStation, и собирает команду запуска.
-- Работает через io.*, потому что love.filesystem не видит /roms.

local M = {}

M.ES_SYSTEMS = "/etc/emulationstation/es_systems.cfg"
M.ES_SETTINGS = "/home/ark/.emulationstation/es_settings.cfg"
M.HOME = "/home/ark"
M.SKIP_DIRS = { media = true, images = true, videos = true, manuals = true,
                downloaded_images = true, snap = true, boxart = true }

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
M.readFile = readFile

local ENT = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }
local function unxml(s)
  if not s then return nil end
  s = s:gsub("&#(%d+);", function(n)
    n = tonumber(n)
    return n < 128 and string.char(n) or ""
  end)
  return (s:gsub("&(%a+);", function(e) return ENT[e] or ("&" .. e .. ";") end))
end

local function tag(block, name)
  local v = block:match("<" .. name .. ">(.-)</" .. name .. ">")
  return v and unxml(v:gsub("^%s+", ""):gsub("%s+$", ""))
end

---------------------------------------------------------------- es_systems

function M.parseSystems(src)
  local systems = {}
  for block in src:gmatch("<system>(.-)</system>") do
    local s = {
      name = tag(block, "name"),
      fullname = tag(block, "fullname"),
      path = tag(block, "path"),
      command = tag(block, "command"),
      platform = tag(block, "platform"),
      theme = tag(block, "theme"),
      exts = {},
      emulators = {},
    }
    for e in (tag(block, "extension") or ""):gmatch("%S+") do s.exts[e:lower()] = true end
    local emus = block:match("<emulators>(.-)</emulators>") or ""
    for ename, body in emus:gmatch('<emulator%s+name="([^"]+)"%s*/?>(.-)</emulator>') do
      local cores = {}
      for c in body:gmatch("<core>%s*(.-)%s*</core>") do cores[#cores + 1] = c end
      s.emulators[#s.emulators + 1] = { name = ename, cores = cores }
    end
    if s.name and s.path and s.command and s.platform ~= "ignore" then
      s.path = s.path:gsub("/+$", "")
      systems[#systems + 1] = s
    end
  end
  return systems
end

function M.parseSettings(src)
  local t = {}
  for kind, name, value in (src or ""):gmatch('<(%a+)%s+name="([^"]+)"%s+value="([^"]*)"') do
    if kind == "bool" then t[name] = value == "true"
    elseif kind == "int" then t[name] = tonumber(value)
    else t[name] = unxml(value) end
  end
  return t
end

---------------------------------------------------------------- gamelist.xml

-- ES пишет lastplayed как 20261025T183012
local function esTime(s)
  if not s then return 0 end
  local y, mo, d, h, mi, se = s:match("^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)(%d%d)")
  if not y then return 0 end
  return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                   hour = tonumber(h), min = tonumber(mi), sec = tonumber(se) }) or 0
end
M.esTime = esTime

local function resolve(dir, p)
  if not p or p == "" then return nil end
  if p:sub(1, 2) == "./" then return dir .. "/" .. p:sub(3) end
  if p:sub(1, 1) == "~" then return M.HOME .. p:sub(2) end
  if p:sub(1, 1) == "/" then return p end
  return dir .. "/" .. p
end

function M.parseGamelist(src, dir)
  local meta = {}
  for block in (src or ""):gmatch("<game[%s>].-</game>") do
    local path = resolve(dir, tag(block, "path"))
    if path then
      meta[path] = {
        name = tag(block, "name"),
        image = resolve(dir, tag(block, "image")),
        desc = tag(block, "desc"),
        developer = tag(block, "developer"),
        genre = tag(block, "genre"),
        year = (tag(block, "releasedate") or ""):match("^(%d%d%d%d)"),
        fav = tag(block, "favorite") == "true",
        hidden = tag(block, "hidden") == "true",
        last = esTime(tag(block, "lastplayed")),
        plays = tonumber(tag(block, "playcount") or "") or 0,
        emulator = tag(block, "emulator"),
        core = tag(block, "core"),
        governor = tag(block, "governor"),
      }
    end
  end
  return meta
end

---------------------------------------------------------------- сканирование

local function shq(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
M.shq = shq

local function listFiles(sys)
  local depth = sys.name == "ports" and 1 or 3
  local cmd = "find " .. shq(sys.path) .. " -mindepth 1 -maxdepth " .. depth .. " -type f 2>/dev/null"
  local p = io.popen(cmd)
  if not p then return {} end
  local out = {}
  for line in p:lines() do out[#out + 1] = line end
  p:close()
  return out
end
M.listFiles = listFiles

local function wanted(sys, path, self)
  if path == self then return false end
  local rel = path:sub(#sys.path + 2)
  for d in rel:gmatch("([^/]+)/") do
    if M.SKIP_DIRS[d:lower()] or d:sub(1, 1) == "." then return false end
  end
  local base = rel:match("([^/]+)$")
  if base:sub(1, 1) == "." then return false end
  local ext = base:match("(%.[^.]+)$")
  return ext and sys.exts[ext:lower()]
end

local function baseName(path)
  return (path:match("([^/]+)$"):gsub("%.[^.]+$", ""))
end
M.baseName = baseName

-- Ключ кэша: время изменения папок систем и их gamelist.xml
function M.stamp(systems)
  local args = {}
  for _, s in ipairs(systems) do
    args[#args + 1] = shq(s.path)
    args[#args + 1] = shq(s.path .. "/gamelist.xml")
  end
  local p = io.popen("stat -c '%n %Y' " .. table.concat(args, " ") .. " " .. shq(M.ES_SYSTEMS) .. " 2>/dev/null")
  if not p then return "" end
  local s = p:read("*a")
  p:close()
  return s
end

-- Полный проход: системы, файлы, метаданные. self — путь лаунчера, его не показываем.
function M.scan(systems, self)
  local games = {}
  for i, sys in ipairs(systems) do
    local meta = M.parseGamelist(M.readFile(sys.path .. "/gamelist.xml"), sys.path)
    local count = 0
    for _, path in ipairs(M.listFiles(sys)) do
      if wanted(sys, path, self) then
        local m = meta[path] or {}
        if not m.hidden then
          count = count + 1
          games[#games + 1] = {
            sys = i, path = path,     -- индекс: имена систем в es_systems повторяются
            name = m.name or baseName(path),
            image = m.image, desc = m.desc, developer = m.developer,
            genre = m.genre, year = m.year,
            fav = m.fav or false, last = m.last or 0, plays = m.plays or 0,
            emulator = m.emulator, core = m.core, governor = m.governor,
          }
        end
      end
    end
    sys.count = count
  end
  return games
end

---------------------------------------------------------------- скрапер

-- Папки libretro-thumbnails для систем ES
M.LIBRETRO = {
  nes = "Nintendo - Nintendo Entertainment System", fds = "Nintendo - Family Computer Disk System",
  snes = "Nintendo - Super Nintendo Entertainment System", n64 = "Nintendo - Nintendo 64",
  gb = "Nintendo - Game Boy", gbc = "Nintendo - Game Boy Color", gba = "Nintendo - Game Boy Advance",
  nds = "Nintendo - Nintendo DS", virtualboy = "Nintendo - Virtual Boy",
  genesis = "Sega - Mega Drive - Genesis", megadrive = "Sega - Mega Drive - Genesis",
  sega32x = "Sega - 32X", segacd = "Sega - Mega-CD - Sega CD", mastersystem = "Sega - Master System - Mark III",
  gamegear = "Sega - Game Gear", sg1000 = "Sega - SG-1000", dreamcast = "Sega - Dreamcast", saturn = "Sega - Saturn",
  psx = "Sony - PlayStation", psp = "Sony - PlayStation Portable",
  pcengine = "NEC - PC Engine - TurboGrafx 16", tg16 = "NEC - PC Engine - TurboGrafx 16",
  pcenginecd = "NEC - PC Engine CD - TurboGrafx-CD",
  atari2600 = "Atari - 2600", atari5200 = "Atari - 5200", atari7800 = "Atari - 7800",
  atarilynx = "Atari - Lynx", atarijaguar = "Atari - Jaguar",
  ngp = "SNK - Neo Geo Pocket", ngpc = "SNK - Neo Geo Pocket Color", neogeo = "SNK - Neo Geo",
  wonderswan = "Bandai - WonderSwan", wonderswancolor = "Bandai - WonderSwan Color",
  colecovision = "Coleco - ColecoVision", vectrex = "GCE - Vectrex", msx = "Microsoft - MSX",
  msx2 = "Microsoft - MSX2", c64 = "Commodore - 64", zxspectrum = "Sinclair - ZX Spectrum",
  amstradcpc = "Amstrad - CPC", ["3do"] = "The 3DO Company - 3DO", scummvm = "ScummVM",
  pico8 = "PICO-8", ["pico-8"] = "PICO-8", intellivision = "Mattel - Intellivision",
}

local function xmlEsc(s) return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end

-- Вписать картинки в gamelist.xml системы: found[полный путь] = "./images/…".
-- Существующие <image> меняет только при overwrite; игр без записи добавляет.
function M.setImages(dir, found, overwrite)
  local file = dir .. "/gamelist.xml"
  local src = readFile(file)
  if src and not src:find("</gameList>", 1, true) then return false end
  if src then
    os.execute("cp -n " .. shq(file) .. " " .. shq(file .. ".home-bak") .. " 2>/dev/null")
  else
    src = '<?xml version="1.0"?>\n<gameList>\n</gameList>\n'
  end
  local left = {}
  for p, v in pairs(found) do left[p] = v end
  local out = src:gsub("<game[%s>].-</game>", function(block)
    local p = resolve(dir, tag(block, "path"))
    local img = p and left[p]
    if not img then return nil end
    left[p] = nil
    local esc = xmlEsc(img)
    if block:find("<image>", 1, true) then
      if not overwrite then return nil end
      return (block:gsub("<image>.-</image>", function() return "<image>" .. esc .. "</image>" end, 1))
    end
    return (block:gsub("%s*</game>$", function() return "\n\t\t<image>" .. esc .. "</image>\n\t</game>" end))
  end)
  local add = {}
  for p, img in pairs(left) do
    add[#add + 1] = "\t<game>\n\t\t<path>" .. xmlEsc("./" .. p:sub(#dir + 2)) .. "</path>\n\t\t<name>" ..
      xmlEsc(baseName(p)) .. "</name>\n\t\t<image>" .. xmlEsc(img) .. "</image>\n\t</game>\n"
  end
  if #add > 0 then
    out = out:gsub("</gameList>%s*$", function() return table.concat(add) .. "</gameList>\n" end)
  end
  local f = io.open(file .. ".tmp", "wb")
  if not f then return false end
  f:write(out)
  f:close()
  return os.rename(file .. ".tmp", file)
end

---------------------------------------------------------------- запуск

local function set(v) return v and v ~= "" and v:lower() ~= "default" and v end

-- Какие эмулятор, ядро и режим процессора выберет запуск (как ES)
function M.pick(sys, game, settings)
  local emu = set(game.emulator) or set(settings[sys.name .. ".emulator"])
  local emuDef
  for _, e in ipairs(sys.emulators) do
    if e.name == emu then emuDef = e end
  end
  if not emuDef then emuDef = sys.emulators[1]; emu = emuDef and emuDef.name or "" end
  local core = set(game.core) or set(settings[sys.name .. ".core"])
  if emuDef and core then
    local ok = false
    for _, c in ipairs(emuDef.cores) do if c == core then ok = true end end
    if not ok and #emuDef.cores > 0 then core = nil end
  end
  core = core or (emuDef and emuDef.cores[1]) or ""
  local gov = set(game.governor) or set(settings[sys.name .. ".governor"]) or "performance"
  return emu, core, gov
end

function M.buildCommand(sys, game, settings)
  local emu, core, gov = M.pick(sys, game, settings)
  local vars = {
    ROM = shq(game.path), ROM_RAW = game.path, BASENAME = baseName(game.path),
    SYSTEM = sys.name, EMULATOR = emu, CORE = core, GOVERNOR = gov, HOME = M.HOME,
  }
  return (sys.command:gsub("%%([%u_]+)%%", function(k) return vars[k] end))
end

return M
