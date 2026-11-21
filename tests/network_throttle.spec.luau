--!strict
-- Throttle · система network · lune-тест. Запуск из папки игры: lune run tests/network_throttle.spec

local Throttle = require("../src/shared/Network/Throttle")
local T = require("./TestKit")

local t = Throttle.new()
T.check("первый запрос проходит", t:allow(1, "SHOP_BUY", 0.2, 10))
T.check("второй через 0.1 с — отказ", not t:allow(1, "SHOP_BUY", 0.2, 10.1))
T.check("через 0.2 с — снова можно", t:allow(1, "SHOP_BUY", 0.2, 10.3))
T.check("другой игрок не мешает", t:allow(2, "SHOP_BUY", 0.2, 10.3))
T.check("другой канал не мешает", t:allow(1, "SHOP_SELL", 0.2, 10.3))

local passed = 0
for i = 1, 100 do
	if t:allow(3, "SPAM", 0.05, 20 + i * 0.01) then
		passed += 1
	end
end
T.check(
	"спам 100 запросов в секунду при лимите 0.05 — проходит не больше 20",
	passed <= 20,
	tostring(passed)
)
T.eq("отказы посчитаны", t:stats().SPAM.rejected, 100 - passed)
T.eq("причина отказа", t:stats().SPAM.reasons.Throttled, 100 - passed)

t:count("SHOP_BUY")
t:reject("SHOP_BUY", "BadRequest")
T.eq("счётчик вызовов", t:stats().SHOP_BUY.calls, 1)
T.eq("свой отказ", t:stats().SHOP_BUY.reasons.BadRequest, 1)

T.eq("держим трёх игроков", t:tracked(), 3)
t:forget(1)
t:forget(2)
t:forget(3)
T.eq("после ухода никого", t:tracked(), 0)

T.finish()
