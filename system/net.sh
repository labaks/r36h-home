#!/bin/bash
# Wi‑Fi для R36H. Запускать от root (sudo -n).
#   on      включить и дождаться подключения (до 30 с)
#   off     выключить вместе с удалённым доступом и отключить модуль от USB
#   remote  включить и запустить SSH/Samba, как «Enable Remote Services»
#   apply   при загрузке: если радио выключено, отключить модуль
#   status  enabled / disabled
#
# Замер 26.10: радио выкл экономит ~70 мА, а модуль, отключённый от USB, —
# ещё ~105 мА (впаянный RTL8188ETV висит на ff300000.usb, порт 1-1).

USBDEV=/sys/bus/usb/devices/1-1
DWC2=/sys/bus/platform/drivers/dwc2

wait_connected() {
  for i in $(seq 1 30); do
    nmcli -t -f DEVICE,STATE dev | grep -qE "^wlan[0-9]:connected$" && return 0
    sleep 1
  done
  return 1
}

module_off() {
  [ -e "$USBDEV/remove" ] && echo 1 > "$USBDEV/remove"
}

# Вернуть модуль: переподключить USB-контроллер, драйвер подхватится сам
module_on() {
  [ -e "$USBDEV" ] && return 0
  echo ff300000.usb > "$DWC2/unbind" 2>/dev/null
  sleep 1
  echo ff300000.usb > "$DWC2/bind"
  for i in $(seq 1 15); do
    [ -e /sys/class/net/wlan0 ] && return 0
    sleep 1
  done
  modprobe 8188eu 2>/dev/null
}

case "$1" in
  on)
    module_on
    rfkill unblock wifi 2>/dev/null
    nmcli radio wifi on
    wait_connected
    ;;
  off)
    systemctl stop ssh smbd nmbd 2>/dev/null
    pkill filebrowser 2>/dev/null
    nmcli radio wifi off
    sleep 1
    module_off
    ;;
  remote)
    module_on
    rfkill unblock wifi 2>/dev/null
    nmcli radio wifi on
    wait_connected || exit 1
    timedatectl set-ntp 1 &
    systemctl start smbd nmbd ssh
    ;;
  apply)
    [ "$(nmcli radio wifi)" = "disabled" ] && module_off
    ;;
  status)
    nmcli radio wifi
    ;;
esac
exit 0
