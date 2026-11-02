#!/usr/bin/env python3
# Служба питания R36H.
# 1. Гасит усилитель (ALSA «Playback Path» = OFF), когда звук никто не играет:
#    EmulationStation держит поток открытым всегда, а в Home и на паузе усилитель
#    только шипит, пищит помехами и ест ~60 мА.
# 2. Раз в минуту пишет журнал батареи: датчик процента врёт, а по журналу
#    полного разряда видно реальную кривую напряжения и время работы.

import os
import subprocess
import time

PCM_STATUS = "/proc/asound/card0/pcm0p/sub0/status"
CONTROL = "Playback Path"
IDLE_OFF_SEC = 1.5
BATT = "/sys/class/power_supply/battery/"
LOG = "/roms/battery_log.csv"
LOG_MAX = 5 * 1024 * 1024


def pcm_active():
    try:
        with open(PCM_STATUS) as f:
            return not f.readline().startswith("closed")
    except OSError:
        return False


def get_path():
    out = subprocess.run(["amixer", "cget", "name=" + CONTROL],
                         stdout=subprocess.PIPE, universal_newlines=True).stdout
    for line in out.splitlines():
        line = line.strip()
        if line.startswith(": values="):
            return int(line.split("=")[1])
    return None


def set_path(v):
    subprocess.run(["amixer", "-q", "cset", "name=" + CONTROL, str(v)])


def read(name):
    try:
        with open(BATT + name) as f:
            return f.read().strip()
    except OSError:
        return ""


def log_battery():
    new = not os.path.exists(LOG)
    if not new and os.path.getsize(LOG) > LOG_MAX:
        os.replace(LOG, LOG + ".old")
        new = True
    v = read("voltage_now")
    i = read("current_now")
    row = "%s,%s,%s,%s,%s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), read("status"),
                                 int(v) // 1000 if v else "", int(i) // 1000 if i else "",
                                 read("capacity"))
    with open(LOG, "a") as f:
        if new:
            f.write("time,status,voltage_mV,current_mA,capacity_pct\n")
        f.write(row)


def main():
    # Wi‑Fi выключен с прошлого раза — отключаем модуль от USB (минус ~105 мА)
    subprocess.run(["/roms/ports/home/net.sh", "apply"])
    saved = get_path() or 3          # 3 = SPK_HP; audiopath сам переключает наушники
    off = False
    idle_since = None
    last_check = 0
    last_log = 0
    while True:
        now = time.monotonic()
        if pcm_active():
            idle_since = None
            if off:
                set_path(saved)
                off = False
        else:
            if idle_since is None:
                idle_since = now
            if not off and now - idle_since >= IDLE_OFF_SEC:
                cur = get_path()
                if cur:
                    saved = cur
                set_path(0)
                off = True
            elif off and now - last_check >= 2:
                # audiopath мог переключить путь (вставили наушники) — запоминаем и снова гасим
                last_check = now
                cur = get_path()
                if cur:
                    saved = cur
                    set_path(0)
        if now - last_log >= 60:
            last_log = now
            try:
                log_battery()
            except OSError:
                pass
        time.sleep(0.25)


if __name__ == "__main__":
    main()
