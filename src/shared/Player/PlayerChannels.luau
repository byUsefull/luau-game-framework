--!strict
--[[ ━━━ PlayerChannels · система player · общее, все плейсы
  Что: каналы player: клиент поднял контроллеры и слушает (PLAYER_READY).
  Почему так: стартовое состояние системам можно слать только после этого сигнала — иначе пустой HUD.
  Не здесь: готовность профиля — атрибут ProfileReady (PlayerConfig.Attr), не канал.
━━━ ]]

local PlayerChannels = {
	PLAYER_READY = "PLAYER_READY",
}

PlayerChannels.Spec = {
	[PlayerChannels.PLAYER_READY] = {
		kind = "Event",
		direction = "ClientToServer",
		rate = 1,
		note = "клиент поднял контроллеры и подписался — можно слать стартовое состояние",
	},
}

return PlayerChannels
