--!strict
--[[ ━━━ CoinsService · система coins (пример) · сервер
  Что: принимает пачку кликов, считает награду, пишет её в профиль одной правкой и объявляет CoinsEarned.
  Почему так: полный путь запроса в каркасе — канал с лимитом и validate → сервис-владелец поля Coins →
    DataService:Update (профиль в памяти сервера) → клиент получает DATA_CHANGED → событие на шине.
  Не здесь: числа — CoinsConfig; формула — CoinsMath; показ — CoinsController.
━━━ ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Core = Shared.Core

local Lifecycle = require(Core.Lifecycle)
local Registry = require(Core.ServiceRegistry)
local EventBus = require(Core.EventBus)
local Network = require(Shared.Network.Network)
local Validate = require(Shared.Network.Validate)
local DataTypes = require(Shared.Data.DataTypes)
local CoinsChannels = require(Shared.Coins.CoinsChannels)
local CoinsConfig = require(Shared.Coins.CoinsConfig)
local CoinsEvents = require(Shared.Coins.CoinsEvents)
local CoinsMath = require(Shared.Coins.CoinsMath)

local CoinsService = Lifecycle:extend()
CoinsService.name = "CoinsService"
CoinsService.dependencies = { "DataService" }

function CoinsService:Init()
	self._data = Registry:get("DataService") :: DataTypes.DataService
end

function CoinsService:Start()
	self:_bind(
		Network.onServerEvent(
			CoinsChannels.COINS_CLICK,
			function(player: Player, payload: CoinsChannels.Click)
				self:_onClicks(player, payload.count)
			end,
			{
				-- Форма и границы данных: без этого обработчик не зарегистрируется.
				validate = Validate.shape({ count = Validate.int(1, CoinsConfig.MaxBatch) }),
			}
		)
	)
end

function CoinsService:_onClicks(player: Player, count: number)
	local earned, total = 0, 0
	-- Правка профиля в памяти сервера; в DataStore он уйдёт автосохранением и при выходе.
	local ok = self._data:Update(player, function(data)
		local coins = data.Coins
		earned = CoinsMath.forBatch(coins.clicks, count, CoinsConfig)
		coins.clicks += count
		coins.coins += earned
		total = coins.coins
		return true
	end, "coins.click")
	if ok then
		EventBus:emit(
			CoinsEvents.CoinsEarned,
			{ player = player, amount = earned, total = total } :: CoinsEvents.CoinsEarned
		)
	end
end

function CoinsService:Get(player: Player): number
	local data = self._data:Get(player)
	return if data then data.Coins.coins else 0
end

return CoinsService
