--!strict
-- CoinsMath · система coins (пример) · lune-тест. Запуск: lune run tests/coins_math.spec

local CoinsMath = require("../src/shared/Coins/CoinsMath")
local T = require("./TestKit")

local cfg = { PerClick = 1, Milestone = 100, MilestoneBonus = 1 }

T.eq("первый клик — базовая награда", CoinsMath.perClick(0, cfg), 1)
T.eq("99-й клик ещё без бонуса", CoinsMath.perClick(99, cfg), 1)
T.eq("100-й клик — бонус +1", CoinsMath.perClick(100, cfg), 2)
T.eq("пачка без смены бонуса", CoinsMath.forBatch(10, 5, cfg), 5)
T.eq(
	"бонус сменился посреди пачки",
	CoinsMath.forBatch(98, 4, cfg),
	1 + 1 + 2 + 2
)
T.eq("пустая пачка — ноль", CoinsMath.forBatch(0, 0, cfg), 0)

T.finish()
