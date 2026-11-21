--!strict
--[[ ━━━ ServerClock · система core · общее, все плейсы
  Что: время сервера, номер дня UTC, отсчёт до сброса, тестовый сдвиг (/core time skip 1d).
  Почему так: одни часы на всю игру — daily, quests, boosts, offline не заводят свои и видят сдвиг сразу.
    Клиент считает по GetServerTimeNow (его часы игрок подкрутить не может), сдвиг приходит атрибутом.
    Сдвиг живёт только в памяти сервера — не сохраняется и пропадает с перезапуском.
  Не здесь: событие смены дня — ClockService; математика дат — ClockMath.
━━━ ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClockMath = require(script.Parent.ClockMath)
local CoreConfig = require(script.Parent.CoreConfig)

local ATTR = CoreConfig.Attr.ClockOffset

local ServerClock = {}

function ServerClock.offset(): number
	local value = ReplicatedStorage:GetAttribute(ATTR)
	return if type(value) == "number" then value else 0
end

-- Секунды Unix по часам сервера, со сдвигом.
function ServerClock.now(): number
	return Workspace:GetServerTimeNow() + ServerClock.offset()
end

function ServerClock.day(): number
	return ClockMath.dayNumber(ServerClock.now(), CoreConfig.Clock.DayResetHourUtc)
end

function ServerClock.secondsToReset(): number
	return ClockMath.secondsToReset(ServerClock.now(), CoreConfig.Clock.DayResetHourUtc)
end

function ServerClock.format(t: number?): string
	return ClockMath.formatUtc(t or ServerClock.now())
end

-- Только сервер. Сдвиг копится: skip(1d) дважды = +2 дня.
function ServerClock.skip(seconds: number)
	assert(RunService:IsServer(), "ServerClock.skip — только сервер")
	ReplicatedStorage:SetAttribute(ATTR, ServerClock.offset() + seconds)
end

function ServerClock.resetOffset()
	assert(RunService:IsServer(), "ServerClock.resetOffset — только сервер")
	ReplicatedStorage:SetAttribute(ATTR, nil)
end

-- Сигнал смены сдвига (ClockService проверяет день сразу, без ожидания тика).
function ServerClock.offsetChanged(): RBXScriptSignal
	return ReplicatedStorage:GetAttributeChangedSignal(ATTR)
end

return ServerClock
