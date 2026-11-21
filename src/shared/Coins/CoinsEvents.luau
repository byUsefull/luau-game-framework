--!strict
--[[ ━━━ CoinsEvents · система coins (пример) · общее
  Что: событие шины «монеты начислены».
  Почему так: квесты, аналитика и награды подписываются сами — CoinsService о них не знает.
  Не здесь: начисление — CoinsService.
━━━ ]]

local CoinsEvents = {
	CoinsEarned = "CoinsEarned", -- сервер · монеты начислены за клики
}

export type CoinsEarned = { player: Player, amount: number, total: number }

return CoinsEvents
