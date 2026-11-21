--!strict
--[[ ━━━ CoinsController · система coins (пример) · клиент
  Что: копит клики (ЛКМ или тап) и раз в SendInterval шлёт пачку на сервер; показывает баланс из
    копии профиля (DataController) простой надписью.
  Почему так: клиент ничего не начисляет — только сообщает, сколько кликнул, и показывает то, что прислал
    сервер. Пачка вместо события на каждый клик — меньше трафика и запросов под лимитом канала.
  Не здесь: начисление — CoinsService; формула — CoinsMath.
━━━ ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage.Shared
local Core = Shared.Core

local Lifecycle = require(Core.Lifecycle)
local Registry = require(Core.ServiceRegistry)
local Network = require(Shared.Network.Network)
local CoinsChannels = require(Shared.Coins.CoinsChannels)
local CoinsConfig = require(Shared.Coins.CoinsConfig)

local CoinsController = Lifecycle:extend()
CoinsController.name = "CoinsController"
CoinsController.dependencies = { "DataController" }

function CoinsController:Init()
	self._dataCtl = Registry:get("DataController")
	self._pending = 0
	self._label = nil :: TextLabel?
end

function CoinsController:Start()
	self._label = self:_buildLabel()
	self:_bind(UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			self._pending = math.min(self._pending + 1, CoinsConfig.MaxBatch)
		end
	end))
	self:_bind(self._dataCtl:OnChanged(function(key: string)
		if key == "Coins" or key == "*" then
			self:_show()
		end
	end))
	self:_spawn(function()
		while true do
			task.wait(CoinsConfig.SendInterval)
			if self._pending > 0 then
				Network.fireServer(CoinsChannels.COINS_CLICK, { count = self._pending })
				self._pending = 0
			end
		end
	end)
end

function CoinsController:_show()
	local coins = self._dataCtl:Get("Coins")
	if self._label and coins then
		self._label.Text = string.format("Coins: %d", coins.coins)
	end
end

-- Пример без готового GUI: надпись создаётся кодом. В игре окно лежит в StarterGui и находится по имени.
function CoinsController:_buildLabel(): TextLabel
	local gui = Instance.new("ScreenGui")
	gui.Name = "CoinsExample"
	gui.ResetOnSpawn = false
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.fromScale(0.5, 0.04)
	label.Size = UDim2.fromScale(0.3, 0.06)
	label.BackgroundTransparency = 0.3
	label.TextScaled = true
	label.Text = "Coins: …"
	label.Parent = gui
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	return label
end

return CoinsController
