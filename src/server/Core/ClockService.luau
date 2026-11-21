--!strict
--[[ ━━━ ClockService · система core · сервер, все плейсы
  Что: следит за сменой игрового дня и шлёт DayChanged (по тику и сразу после сдвига часов).
  Почему так: одно место, где «наступил новый день», — daily и quests сбрасываются в одну секунду,
    тестовый сдвиг /core time skip 1d виден всем системам без перезапуска.
  Не здесь: само время — ServerClock; что делать в новый день — системы, подписанные на DayChanged.
━━━ ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Core = Shared.Core

local Lifecycle = require(Core.Lifecycle)
local EventBus = require(Core.EventBus)
local ServerClock = require(Core.ServerClock)
local CoreConfig = require(Core.CoreConfig)
local CoreEvents = require(Core.CoreEvents)

local ClockService = Lifecycle:extend()
ClockService.name = "ClockService"
ClockService.dependencies = {}

function ClockService:Init()
	self._day = 0
end

function ClockService:Start()
	self._day = ServerClock.day()
	self._log:Info(
		"часы: %s, день %d, до сброса %ds",
		ServerClock.format(),
		self._day,
		ServerClock.secondsToReset()
	)
	self:_bind(ServerClock.offsetChanged():Connect(function()
		self:CheckDay()
	end))
	self:_spawn(function()
		while true do
			task.wait(CoreConfig.Clock.CheckPeriod)
			self:CheckDay()
		end
	end)
end

function ClockService:CurrentDay(): number
	return self._day
end

function ClockService:CheckDay()
	local day = ServerClock.day()
	if day == self._day then
		return
	end
	local previous = self._day
	self._day = day
	self._log:Info(
		"новый день %d (был %d), сдвиг %ds",
		day,
		previous,
		ServerClock.offset()
	)
	EventBus:emit(
		CoreEvents.DayChanged,
		{ day = day, previous = previous } :: CoreEvents.DayChanged
	)
end

return ClockService
