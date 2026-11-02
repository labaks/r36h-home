#!/bin/bash
# Установка системной части на R36H (от root): служба питания, Wi‑Fi, загрузка в Home.
#   install.sh            всё
#   install.sh uninstall  вернуть как было (ES при загрузке, без службы питания)
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
DROPIN=/etc/systemd/system/emulationstation.service.d

if [ "$1" = "uninstall" ]; then
  systemctl disable --now r36-powerd 2>/dev/null || true
  rm -f /etc/systemd/system/r36-powerd.service "$DROPIN/home.conf" /etc/modprobe.d/r36-8188eu.conf
  systemctl daemon-reload
  amixer -q cset name="Playback Path" 3
  [ -f /boot/boot.steam.mp4 ] && cp /boot/boot.steam.mp4 /boot/boot.mp4
  [ -f /roms/launchimages/loading.gif.arkos ] && cp /roms/launchimages/loading.gif.arkos /roms/launchimages/loading.gif
  echo "откат сделан"
  exit 0
fi

install -m 755 "$SRC/powerd.py" /usr/local/bin/r36-powerd.py
install -m 755 "$SRC/net.sh" /roms/ports/home/net.sh
install -m 755 "$SRC/boot.sh" /roms/ports/home/boot.sh

# Загрузочное видео и экран запуска Home; прежние сохраняем для отката
[ -f /boot/boot.mp4 ] && [ ! -f /boot/boot.steam.mp4 ] && cp /boot/boot.mp4 /boot/boot.steam.mp4
cp "$SRC/boot.mp4" /boot/boot.mp4
[ -f /roms/launchimages/loading.gif.arkos ] || cp /roms/launchimages/loading.gif /roms/launchimages/loading.gif.arkos

cat > /etc/systemd/system/r36-powerd.service <<EOF
[Unit]
Description=R36H power: amp off when idle, battery log
After=sound.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/r36-powerd.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# rtw_power_mgnt=0 от обрывов Wi‑Fi не помог (26.10) — убираем, если остался
rm -f /etc/modprobe.d/r36-8188eu.conf

mkdir -p "$DROPIN"
cat > "$DROPIN/home.conf" <<EOF
[Service]
ExecStart=
ExecStart=/roms/ports/home/boot.sh
EOF

systemctl daemon-reload
systemctl enable --now r36-powerd
echo "установлено"
