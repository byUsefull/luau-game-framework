--!strict
--[[ ━━━ CoinsChannels · система coins (пример) · общее
  Что: один канал — клиент присылает пачку кликов.
  Почему так: клиент сообщает только «сколько раз кликнул», монеты считает сервер. Лимит частоты —
    здесь, в объявлении; без validate сервер обработчик не зарегистрирует.
  Не здесь: обработчик — CoinsService; отправка — CoinsController.
━━━ ]]

local CoinsChannels = {
	COINS_CLICK = "COINS_CLICK",
}

CoinsChannels.Spec = {
	[CoinsChannels.COINS_CLICK] = {
		kind = "Event",
		direction = "ClientToServer",
		rate = 0.2,
		note = "пачка кликов { count } не чаще раза в 0.2 с",
	},
}

export type Click = { count: number }

return CoinsChannels
