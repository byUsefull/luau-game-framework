--!strict
--[[ ━━━ PlayerController · система player · клиент, все плейсы
  Что: когда все контроллеры прошли Start (ModulesStarted) — шлёт серверу PLAYER_READY;
    отдаёт готовность профиля (атрибут ProfileReady) другим контроллерам.
  Почему так: сервер шлёт стартовое состояние только тем, кто уже подписан — HUD не мигает нулями.
    Ожидание — сигналом атрибута, без циклов.
  Не здесь: порядок входа на сервере — PlayerService; экран загрузки — система loading.
━━━ ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Core = Shared.Core

local Lifecycle = require(Core.Lifecycle)
local EventBus = require(Core.EventBus)
local CoreEvents = require(Core.CoreEvents)
local Network = require(Shared.Network.Network)
local PlayerChannels = require(Shared.Player.PlayerChannels)
local PlayerConfig = require(Shared.Player.PlayerConfig)

local PlayerController = Lifecycle:extend()
PlayerController.name = "PlayerController"
PlayerController.dependencies = {}

function PlayerController:Init()
	self._sent = false
	self._waiting = {} :: { () -> () }
end

function PlayerController:Start()
	local player = Players.LocalPlayer
	self:_bind(EventBus:once(CoreEvents.ModulesStarted, function()
		if not self._sent then
			self._sent = true
			Network.fireServer(PlayerChannels.PLAYER_READY)
			self._log:Info("клиент готов — PLAYER_READY")
		end
	end))
	self:_bind(player:GetAttributeChangedSignal(PlayerConfig.Attr.ProfileReady):Connect(function()
		self:_flush()
	end))
	self:_flush()
end

function PlayerController:IsReady(): boolean
	return Players.LocalPlayer:GetAttribute(PlayerConfig.Attr.ProfileReady) == true
end

function PlayerController:WhenReady(fn: () -> ())
	if self:IsReady() then
		task.spawn(fn)
	else
		table.insert(self._waiting, fn)
	end
end

function PlayerController:_flush()
	if not self:IsReady() then
		return
	end
	local waiting = self._waiting
	self._waiting = {}
	for _, fn in ipairs(waiting) do
		task.spawn(fn)
	end
end

return PlayerController
