#!/bin/bash
# Свой главный экран (LÖVE). Игры запускает теми же командами, что EmulationStation:
# экран пишет команду в /tmp/home_launch.sh и выходит, здесь она выполняется.
GAMEDIR=/roms/ports/home
LAUNCH=/tmp/home_launch.sh
SHOT="$GAMEDIR/save/love/home/loading.png"
cd "$GAMEDIR"
export LD_LIBRARY_PATH=/opt/love2d/lib:$LD_LIBRARY_PATH
export XDG_DATA_HOME="$GAMEDIR/save"
while true; do
  rm -f "$LAUNCH"
  /opt/love2d/love "$GAMEDIR/app" > "$GAMEDIR/log.txt" 2>&1
  [ -f "$LAUNCH" ] || break
  # экран запуска из Home вместо «ArkOS now loading»: perfmax показывает loading.gif
  if [ -f "$SHOT" ]; then
    # палитра из самой картинки: без неё ffmpeg рябит фон (0,45 с на приставке)
    ffmpeg -v quiet -y -i "$SHOT" -filter_complex "split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse=dither=none"       /roms/launchimages/loading.gif && rm -f "$SHOT"
  fi
  bash "$LAUNCH" > "$GAMEDIR/game.log" 2>&1
done
case "$(cat /tmp/home_exit 2>/dev/null)" in
  poweroff) sudo systemctl poweroff ;;
  reboot) sudo systemctl reboot ;;
esac
exit 0
