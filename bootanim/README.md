# Загрузочное видео Home

Кадры рисует `main.lua` (LÖVE 11.4) логотипом из `../home/app/logo.lua`:
скопировать `logo.lua` и шрифты DejaVu в эту папку, запустить `love .` —
90 кадров `f000.png…f089.png` лягут в папку сохранений LÖVE (`%APPDATA%\LOVE\bootanim`).
Звук `chime.wav` — синтезированный аккорд (код в истории сессии 26.10).

Сборка на приставке (там есть libx264):

    ffmpeg -framerate 30 -i f%03d.png -i chime.wav -c:v libx264 -preset slow -crf 20 \
      -pix_fmt yuv420p -c:a aac -b:a 96k -shortest boot.mp4

Готовый файл — `../system/boot.mp4`, ставит `install.sh` (стимовский сохраняется как /boot/boot.steam.mp4).
