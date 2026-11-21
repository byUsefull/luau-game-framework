--!strict
-- Validate · система network · lune-тест. Запуск из папки игры: lune run tests/network_validate.spec

local Validate = require("../src/shared/Network/Validate")
local T = require("./TestKit")

local NAN = 0 / 0

local buy = Validate.shape({
	key = Validate.key(32),
	count = Validate.int(1, 99),
	note = Validate.optional(Validate.str(10)),
})

T.check("правильный пакет", buy({ key = "sword", count = 3 }))
T.check(
	"с необязательным полем",
	buy({ key = "sword", count = 3, note = "hi" })
)
T.check("nil — отказ", not buy(nil))
T.check("строка вместо таблицы — отказ", not buy("sword"))
T.check("NaN — отказ", not buy({ key = "sword", count = NAN }))
T.check("inf — отказ", not buy({ key = "sword", count = math.huge }))
T.check(
	"дробь вместо целого — отказ",
	not buy({ key = "sword", count = 1.5 })
)
T.check("за пределом — отказ", not buy({ key = "sword", count = 100 }))
T.check("лишний ключ — отказ", not buy({ key = "sword", count = 1, price = 0 }))
T.check(
	"строка в 1 МБ — отказ",
	not buy({ key = string.rep("a", 1024 * 1024), count = 1 })
)
T.check("ключ с пробелом — отказ", not buy({ key = "a b", count = 1 }))
T.check("пустой ключ — отказ", not buy({ key = "", count = 1 }))
T.check(
	"таблица с метатаблицей — отказ",
	not buy(setmetatable({ key = "sword", count = 1 }, {}))
)

local ids = Validate.array(Validate.int(1, 1000), 3)
T.check("массив", ids({ 1, 2, 3 }))
T.check("длиннее предела — отказ", not ids({ 1, 2, 3, 4 }))
T.check("словарь — отказ", not ids({ a = 1 }))
T.check("с дырой — отказ", not ids({ [1] = 1, [3] = 3 }))

local mode = Validate.oneOf({ "fast", "slow" })
T.check("значение из списка", mode("fast"))
T.check("не из списка — отказ", not mode("turbo"))
T.check("nil не из списка", not mode(nil))

T.check("none пропускает всё", Validate.none({ anything = true }))
T.check("empty — только nil", Validate.empty(nil) and not Validate.empty({}))
T.check(
	"value оборачивает проверку",
	Validate.value(Validate.str(3))("abc") and not Validate.value(Validate.str(3))("abcd")
)
T.check("bool", Validate.bool(true) and not Validate.bool("true"))

T.finish()
