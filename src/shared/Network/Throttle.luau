--!strict
--[[ ━━━ Throttle · система network · общее, все плейсы
  Что: лимит частоты по игроку и каналу плюс счётчики вызовов и отказов по каналам (для /network stats).
  Почему так: чистый класс без Roblox API и без require, время приходит аргументом — проверяет lune
    (tests/network_throttle.spec.luau). Лимит каждого канала — в его объявлении, не в ядре.
  Не здесь: кто зовёт и когда чистит игрока — Network (по уходу игрока).
━━━ ]]

export type Stat = { calls: number, rejected: number, reasons: { [string]: number } }

export type Throttle = {
	allow: (self: Throttle, key: number, channel: string, rate: number, now: number) -> boolean,
	count: (self: Throttle, channel: string) -> (),
	reject: (self: Throttle, channel: string, reason: string) -> (),
	forget: (self: Throttle, key: number) -> (),
	stats: (self: Throttle) -> { [string]: Stat },
	tracked: (self: Throttle) -> number,
}

local Throttle = {}
Throttle.__index = Throttle

function Throttle.new(): Throttle
	return (setmetatable({ _last = {}, _stats = {} }, Throttle) :: any) :: Throttle
end

local function statOf(self: any, channel: string): Stat
	local stat = self._stats[channel]
	if not stat then
		stat = { calls = 0, rejected = 0, reasons = {} }
		self._stats[channel] = stat
	end
	return stat
end

-- true — можно; false — слишком часто (отказ засчитан).
function Throttle.allow(self: any, key: number, channel: string, rate: number, now: number): boolean
	local byChannel = self._last[key]
	if not byChannel then
		byChannel = {}
		self._last[key] = byChannel
	end
	local last = byChannel[channel]
	if last and now - last < rate then
		Throttle.reject(self, channel, "Throttled")
		return false
	end
	byChannel[channel] = now
	return true
end

function Throttle.count(self: any, channel: string)
	statOf(self, channel).calls += 1
end

function Throttle.reject(self: any, channel: string, reason: string)
	local stat = statOf(self, channel)
	stat.rejected += 1
	stat.reasons[reason] = (stat.reasons[reason] or 0) + 1
end

-- Игрок ушёл — его отметки времени больше не нужны.
function Throttle.forget(self: any, key: number)
	self._last[key] = nil
end

function Throttle.stats(self: any): { [string]: Stat }
	return self._stats
end

-- Сколько игроков держим (для проверки, что ушедшие убраны).
function Throttle.tracked(self: any): number
	local n = 0
	for _ in pairs(self._last) do
		n += 1
	end
	return n
end

return Throttle
