--!strict
--[[ ━━━ GameVersion · система core · общее, все плейсы
  Что: строка версии игры «0.1.0+87» — номер из CoreConfig.Version плюс PlaceVersion плейса.
  Почему так: одна строка в Boot, логах, багрепортах и в углу экрана — сборки отличимы даже без нового номера.
  Не здесь: надпись в углу рисует UiController (система ui).
━━━ ]]

local CoreConfig = require(script.Parent.CoreConfig)

local GameVersion = {}

function GameVersion.get(): string
	return string.format("%s+%d", CoreConfig.Version, game.PlaceVersion)
end

return GameVersion
