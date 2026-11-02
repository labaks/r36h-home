#!/bin/bash
# Установка Home на R36H (ArkOS). Запускать на приставке из папки репозитория:
#   bash install.sh           лаунчер в Ports (EmulationStation остаётся главным)
#   bash install.sh --boot    плюс загрузка сразу в Home, своё загрузочное видео,
#                             служба питания (нужен sudo)
#   sudo bash system/install.sh uninstall   вернуть загрузку в EmulationStation
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
APP=/roms/ports/home

mkdir -p "$APP/app/fonts" "$APP/save"
cp -r "$SRC"/home/app/* "$APP/app/"
cp "$SRC/home/Home.sh" /roms/ports/Home.sh
sed -i 's/\r$//' /roms/ports/Home.sh && chmod +x /roms/ports/Home.sh
# шрифт с кириллицей и база геймпадов LÖVE — из самой ArkOS
cp -n /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf "$APP/app/fonts/"
cp -n /opt/love2d/gamecontrollerdb.txt "$APP/app/"

if [ "$1" = "--boot" ]; then
  sudo bash "$SRC/system/install.sh"
fi
sudo -n systemctl restart emulationstation 2>/dev/null || echo "перезапустите приставку — Home появится в Ports"
echo "Home установлен: Ports → Home"
