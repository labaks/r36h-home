#!/bin/bash
# Старт меню вместо EmulationStation: сначала Home, по выбору или при сбое — ES.
# Подключается через /etc/systemd/system/emulationstation.service.d/home.conf.
# Откат: удалить home.conf и выполнить systemctl daemon-reload.

export TERM=linux
export XDG_RUNTIME_DIR=/run/user/$UID/
sudo chmod 666 /dev/tty1

while true; do
  rm -f /tmp/home_exit
  /roms/ports/Home.sh
  # Home.sh сам выключает приставку; сюда попадаем при выборе ES или при сбое
  /usr/bin/emulationstation/emulationstation.sh
done
