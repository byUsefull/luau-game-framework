--!strict
--[[ ━━━ CoinsMath · система coins (пример) · общее
  Что: чистый расчёт награды: сколько монет дают count кликов, если до них сделано done кликов.
  Почему так: без Roblox API и состояния — проверяется lune (tests/coins_math.spec.luau).
  Не здесь: числа — CoinsConfig; запись — CoinsService.
━━━ ]]

export type Config = { PerClick: number, Milestone: number, MilestoneBonus: number }

local CoinsMath = {}

-- Награда за один клик, когда за всё время уже сделано done кликов.
function CoinsMath.perClick(done: number, cfg: Config): number
	return cfg.PerClick + math.floor(done / cfg.Milestone) * cfg.MilestoneBonus
end

-- Награда за пачку из count кликов: бонус может смениться посреди пачки.
function CoinsMath.forBatch(done: number, count: number, cfg: Config): number
	local total = 0
	for i = 0, count - 1 do
		total += CoinsMath.perClick(done + i, cfg)
	end
	return total
end

return CoinsMath
