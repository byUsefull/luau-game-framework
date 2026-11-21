--!strict
-- DataMigrations · система data · lune-тест. Запуск из папки игры: lune run tests/data_migrations.spec

local DataMigrations = require("../src/shared/Data/DataMigrations")
local DataOps = require("../src/shared/Data/DataOps")
local T = require("./TestKit")

-- Копия «старого профиля» версии 1: валюта называлась gold.
local OLD = { _version = 1, Currency = { gold = 250 } }

local steps = {
	[2] = function(data)
		data.Currency.cash = data.Currency.gold
		data.Currency.gold = nil
	end,
	[3] = function(data)
		data.Player = data.Player or { visits = 0 }
	end,
}

do
	local data = DataOps.deepCopy(OLD)
	local version, applied = DataMigrations.run(data, "_version", 3, steps)
	T.eq("версия поднята до текущей", version, 3)
	T.eq("версия записана в профиль", data._version, 3)
	T.eq("применены оба шага", table.concat(applied, ","), "2,3")
	T.eq("gold стал cash", data.Currency.cash, 250)
	T.check("старое поле убрано", data.Currency.gold == nil)
	T.check("оригинал не тронут", OLD.Currency.gold == 250)
end

do
	local data = { _version = 3, Currency = { cash = 5 } }
	local version, applied = DataMigrations.run(data, "_version", 3, steps)
	T.check("свежий профиль не мигрирует", version == 3 and #applied == 0)
end

do
	local data = { Currency = { gold = 1 } }
	local version = DataMigrations.run(data, "_version", 2, steps)
	T.check(
		"профиль без версии считается версией 1",
		version == 2 and data.Currency.cash == 1
	)
end

do
	local version, applied = DataMigrations.run({ _version = 1 }, "_version", 1)
	T.check(
		"без шагов и на текущей версии — ничего",
		version == 1 and #applied == 0
	)
end

T.finish()
