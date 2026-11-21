--!strict
-- NetworkRegistry · система network · lune-тест. Запуск из папки игры: lune run tests/network_registry.spec

local NetworkRegistry = require("../src/shared/Network/NetworkRegistry")
local T = require("./TestKit")

local function hasError(errors: { string }, needle: string): boolean
	for _, message in ipairs(errors) do
		if string.find(message, needle, 1, true) then
			return true
		end
	end
	return false
end

T.eq(
	"префикс простой системы",
	NetworkRegistry.prefixOf("Currency"),
	"CURRENCY_"
)
T.eq(
	"префикс составной системы",
	NetworkRegistry.prefixOf("SocialRewards"),
	"SOCIAL_REWARDS_"
)

do
	local channels, errors = NetworkRegistry.collect({
		CurrencyChannels = {
			CURRENCY_STATE = "CURRENCY_STATE",
			CURRENCY_SPEND_REQUEST = "CURRENCY_SPEND_REQUEST",
			Spec = {
				CURRENCY_STATE = {
					kind = "Event",
					direction = "ServerToClient",
					note = "снимок",
				},
				CURRENCY_SPEND_REQUEST = {
					kind = "Event",
					direction = "ClientToServer",
					rate = 0.2,
					note = "трата",
				},
			},
		},
	})
	T.eq("чистое объявление без ошибок", #errors, 0)
	T.eq(
		"лимит по умолчанию",
		channels.CURRENCY_STATE.rate,
		NetworkRegistry.DEFAULT_RATE
	)
	T.eq("свой лимит", channels.CURRENCY_SPEND_REQUEST.rate, 0.2)
	T.eq("владелец канала", channels.CURRENCY_STATE.system, "Currency")
	T.check(
		"направление разрешено",
		NetworkRegistry.allows(channels.CURRENCY_STATE, "ServerToClient")
	)
	T.check(
		"обратное направление запрещено",
		not NetworkRegistry.allows(channels.CURRENCY_STATE, "ClientToServer")
	)
end

do
	local _, errors = NetworkRegistry.collect({
		ShopChannels = {
			SHOP_BUY = "SHOP_BUYY",
			Spec = { SHOP_BUY = { kind = "Event", direction = "ClientToServer", note = "x" } },
		},
	})
	T.check(
		"ключ ≠ значение — ошибка",
		hasError(errors, "ключ ≠ значение")
	)
end

do
	local _, errors = NetworkRegistry.collect({
		ShopChannels = {
			BUY = "BUY",
			Spec = { BUY = { kind = "Event", direction = "ClientToServer", note = "x" } },
		},
	})
	T.check("нет префикса системы — ошибка", hasError(errors, "SHOP_"))
end

do
	local _, errors = NetworkRegistry.collect({
		ShopChannels = {
			SHOP_A = "SHOP_A",
			SHOP_B = "SHOP_B",
			SHOP_C = "SHOP_C",
			Spec = {
				SHOP_A = { kind = "Event", direction = "Sideways", note = "x" },
				SHOP_B = { kind = "Event", direction = "ClientToServer" },
				SHOP_C = { kind = "Function", direction = "ServerToClient", note = "x" },
			},
		},
	})
	T.check("неверное направление", hasError(errors, "SHOP_A: direction"))
	T.check("нет note", hasError(errors, "SHOP_B: нет note"))
	T.check("Function к клиенту запрещён", hasError(errors, "InvokeClient"))
end

do
	local _, errors = NetworkRegistry.collect({
		ShopChannels = { SHOP_X = "SHOP_X", Spec = {} },
	})
	T.check(
		"канал без Spec — ошибка",
		hasError(errors, "нет записи в Spec")
	)
end

do
	local _, errors = NetworkRegistry.collect({
		ShopChannels = {
			Spec = { SHOP_GHOST = { kind = "Event", direction = "Both", note = "x" } },
		},
	})
	T.check(
		"Spec без канала — ошибка",
		hasError(errors, "канала нет в таблице")
	)
end

T.finish()
