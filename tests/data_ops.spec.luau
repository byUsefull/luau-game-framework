--!strict
-- DataOps · система data · lune-тест. Запуск из папки игры: lune run tests/data_ops.spec

local DataOps = require("../src/shared/Data/DataOps")
local T = require("./TestKit")

local function profile()
	return { Currency = { cash = 100 }, Inventory = { items = { "sword" } }, _version = 1 }
end

do
	local data = profile()
	local result = DataOps.applyAtomic(data, function(copy)
		copy.Currency.cash -= 30
		table.insert(copy.Inventory.items, "shield")
		return true
	end)
	T.check("правка прошла", result.ok)
	T.eq("живые данные не тронуты до commit", data.Currency.cash, 100)
	T.eq("в копии списано", result.data.Currency.cash, 70)
	T.eq("в копии выдано", #result.data.Inventory.items, 2)
end

do
	-- составная запись: списание + выдача, выдача падает → откат всего
	local data = profile()
	local result = DataOps.applyAtomic(data, function(copy)
		copy.Currency.cash -= 30
		error("второй apply упал")
	end)
	T.check("ошибка во второй apply-функции — отказ", not result.ok)
	T.check(
		"текст ошибки сохранён",
		result.error ~= nil and string.find(result.error :: string, "второй apply") ~= nil
	)
	T.eq("деньги на месте", data.Currency.cash, 100)
end

do
	local data = profile()
	local result = DataOps.applyAtomic(data, function(copy)
		copy.Currency.cash = 0
		return false
	end)
	T.check(
		"false — отказ без ошибки",
		not result.ok and result.error == "отказ"
	)
	T.eq("отказ ничего не меняет", data.Currency.cash, 100)
end

do
	local data = profile()
	local result = DataOps.applyAtomic(data, function(copy)
		copy.Currency.cash = 1
		coroutine.yield()
		copy.Currency.cash = 2
		return true
	end)
	T.check("yield внутри правки — отказ", not result.ok)
	T.check(
		"yield назван в ошибке",
		result.error ~= nil and string.find(result.error :: string, "yield") ~= nil
	)
	T.eq("после yield данные целы", data.Currency.cash, 100)
end

do
	local result = DataOps.applyAtomic(profile(), function(copy)
		copy.Currency.cash = 0 / 0
		return true
	end)
	T.check("NaN в профиль не пишется", not result.ok)
	local holes = DataOps.applyAtomic(profile(), function(copy)
		copy.Inventory.items[5] = "gap"
		return true
	end)
	T.check("массив с дырами не пишется", not holes.ok)
	local mixed = DataOps.applyAtomic(profile(), function(copy)
		copy.Inventory.items.extra = true
		return true
	end)
	T.check("смешанные ключи не пишутся", not mixed.ok)
end

do
	local a = { Currency = { cash = 50 }, Items = {} }
	local b = { Currency = { cash = 0 }, Items = { "gem" } }
	local first, second = DataOps.applyPair(a, b, function(ca, cb)
		ca.Currency.cash -= 50
		cb.Currency.cash += 50
		table.insert(ca.Items, table.remove(cb.Items, 1))
		return true
	end)
	T.check("обмен прошёл", first.ok and second ~= nil and second.ok)
	T.eq("A получил предмет", second and first.data.Items[1], "gem")
	T.eq("B получил деньги", second and second.data.Currency.cash, 50)
	local failed, none = DataOps.applyPair(a, b, function(ca)
		ca.Currency.cash -= 50
		error("обмен сорвался")
	end)
	T.check(
		"сорванный обмен — отказ обоих",
		not failed.ok and none == nil
	)
	T.eq("A без изменений", a.Currency.cash, 50)
end

do
	local snap = DataOps.snapshot(
		{ Currency = { cash = 1 }, Purchases = { receipts = { "x" } } },
		{ Purchases = true }
	)
	T.check(
		"приватное поле не уходит клиенту",
		snap.Purchases == nil and snap.Currency.cash == 1
	)
end

do
	local keys = DataOps.changedKeys(
		{ A = 1, B = { x = 1 }, C = 3 },
		{ A = 1, B = { x = 2 }, D = 4 }
	)
	T.eq("изменённые ключи", table.concat(keys, ","), "B,C,D")
end

do
	local live = { Currency = { cash = 5 } }
	local ref = live
	DataOps.replaceContents(live, { Currency = { cash = 9 }, New = true })
	T.check(
		"содержимое заменено, ссылка та же",
		ref.Currency.cash == 9 and ref.New == true
	)
end

do
	local data = { Currency = { cash = 10 }, Player = {} }
	DataOps.reconcile(
		data,
		{ Currency = { cash = 0, gems = 0 }, Player = { visits = 0 }, Rewards = { pending = {} } }
	)
	T.eq("существующее не тронуто", data.Currency.cash, 10)
	T.eq("новое поле внутри долито", data.Currency.gems, 0)
	T.eq("новое поле игрока долито", data.Player.visits, 0)
	T.check(
		"новый раздел долит",
		data.Rewards ~= nil and data.Rewards.pending ~= nil
	)
end

T.finish()
