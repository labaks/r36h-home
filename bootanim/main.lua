-- Кадры загрузочного видео: 30 к/с, 3 с, последний кадр = заставка Home
local logo = require("logo")
function love.load()
  local big = love.graphics.newFont("fonts/DejaVuSans-Bold.ttf", 30)
  local small = love.graphics.newFont("fonts/DejaVuSans.ttf", 15)
  local cv = love.graphics.newCanvas(640, 480, { msaa = 4 })
  for f = 0, 89 do
    love.graphics.setCanvas(cv)
    love.graphics.clear(0, 0, 0)
    logo.draw(f / 30, 320, 240, 132, big, small)
    love.graphics.setCanvas()
    cv:newImageData():encode("png", string.format("f%03d.png", f))
  end
  love.event.quit()
end
