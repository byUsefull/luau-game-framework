--!strict
-- ClockMath · система core · lune-тест. Запуск из папки игры: lune run tests/core_clock_math.spec

local ClockMath = require("../src/shared/Core/ClockMath")
local T = require("./TestKit")

local DAY = 86400
-- 2026-10-02 00:00:00 UTC
local BASE = 1790899200

T.eq("дата: начало дня", ClockMath.formatUtc(BASE), "2026-10-02 00:00:00 UTC")
T.eq(
	"дата: время внутри дня",
	ClockMath.formatUtc(BASE + 21 * 3600 + 15 * 60 + 3),
	"2026-10-02 21:15:03 UTC"
)
T.eq("дата: эпоха", ClockMath.formatUtc(0), "1970-01-01 00:00:00 UTC")
T.eq(
	"дата: високосный 29 февраля",
	ClockMath.formatUtc(951782400),
	"2000-02-29 00:00:00 UTC"
)

T.eq(
	"день: последний миг суток",
	ClockMath.dayNumber(BASE + DAY - 1, 0),
	ClockMath.dayNumber(BASE, 0)
)
T.eq(
	"день: новые сутки",
	ClockMath.dayNumber(BASE + DAY, 0),
	ClockMath.dayNumber(BASE, 0) + 1
)
T.eq(
	"день со сдвигом сброса: 03:00 ещё вчера при сбросе в 4",
	ClockMath.dayNumber(BASE + 3 * 3600, 4),
	ClockMath.dayNumber(BASE, 0) - 1
)

T.eq(
	"до сброса в начале дня — сутки",
	ClockMath.secondsToReset(BASE, 0),
	DAY
)
T.eq(
	"до сброса за секунду до полуночи",
	ClockMath.secondsToReset(BASE + DAY - 1, 0),
	1
)
T.eq("до сброса в 4 утра с 03:00", ClockMath.secondsToReset(BASE + 3 * 3600, 4), 3600)

T.eq("разбор 1d", ClockMath.parseDuration("1d"), DAY)
T.eq("разбор 3h", ClockMath.parseDuration("3h"), 3 * 3600)
T.eq("разбор 1d12h", ClockMath.parseDuration("1d12h"), DAY + 12 * 3600)
T.eq("разбор 90m", ClockMath.parseDuration("90m"), 5400)
T.eq("разбор голых секунд", ClockMath.parseDuration("45"), 45)
T.eq("разбор минуса", ClockMath.parseDuration("-1d"), -DAY)
T.eq("мусор не разбирается", ClockMath.parseDuration("1x"), nil)
T.eq("пустое не разбирается", ClockMath.parseDuration(""), nil)
T.eq("хвост мусора не разбирается", ClockMath.parseDuration("1dz"), nil)

T.eq("длительность: минуты", ClockMath.formatDuration(125), "2m 05s")
T.eq(
	"длительность: часы",
	ClockMath.formatDuration(3 * 3600 + 3 * 60 + 9),
	"3h 03m 09s"
)
T.eq("длительность: дни", ClockMath.formatDuration(2 * DAY + 4 * 3600), "2d 4h")
T.eq(
	"длительность: отрицательное = 0",
	ClockMath.formatDuration(-5),
	"0m 00s"
)

T.finish()
