--!strict
--[[ ━━━ DataController · система data · клиент, все плейсы
  Что: клиентская копия профиля только для чтения: снимок после ClientReady, затем изменения по ключам;
    сигнал изменений для GUI.
  Почему так: клиент ничего не пишет — он показывает. Приватных полей у него нет (их не шлёт сервер).
  Не здесь: запись и правила — DataService на сервере; валюты в HUD — атрибуты своей системы.
━━━ ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Core = Shared.Core

local Lifecycle = require(Core.Lifecycle)
local Signal = require(Core.Signal)
local Network = require(Shared.Network.Network)
local DataChannels = require(Shared.Data.DataChannels)
local DataOps = require(Shared.Data.DataOps)

local DataController = Lifecycle:extend()
DataController.name = "DataController"
DataController.dependencies = {}

function DataController:Init()
	self._data = {} :: { [string]: any }
	self._ready = false
	self._changed = Signal.new()
end

function DataController:Start()
	self:_bind(
		Network.onClientEvent(DataChannels.DATA_SNAPSHOT, function(payload: DataChannels.Snapshot)
			self._data = payload.data or {}
			self._ready = true
			self._changed:Fire("*", self._data)
		end)
	)
	self:_bind(
		Network.onClientEvent(DataChannels.DATA_CHANGED, function(payload: DataChannels.Changed)
			-- причина записи (DataService:Update) — третьим аргументом: кто показывает прирост, отличит
			-- свой клик от автокликера и награды
			local reason = if type(payload.reason) == "string" then payload.reason else nil
			for key, value in pairs(payload.values or {}) do
				self._data[key] = value
				self._changed:Fire(key, value, reason)
			end
			for _, key in ipairs(payload.removed or {}) do
				self._data[key] = nil
				self._changed:Fire(key, nil, reason)
			end
		end)
	)
end

function DataController:IsReady(): boolean
	return self._ready
end

function DataController:Get(key: string?): any
	if key then
		return DataOps.deepCopy(self._data[key])
	end
	return DataOps.deepCopy(self._data)
end

function DataController:OnChanged(fn: (string, any, string?) -> ()): { Disconnect: (any) -> () }
	return self._changed:Connect(fn)
end

return DataController
