--!strict
--[[ ━━━ PlayerScope · система player · сервер, все плейсы
  Что: контейнер уборки на игрока: связи, объекты, потоки, таймеры, временные модификаторы.
    Add, Spawn, Delay; уничтожается после сохранения профиля на выходе.
  Почему так: системы не чистят игрока руками ([player] = … без очистки — утечки и ошибки на ушедшем).
    Всё, что положено сюда, уберётся само, в обратном порядке.
  Не здесь: порядок выхода (PlayerLeaving → сохранение → scope) — PlayerService.
━━━ ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Entity = require(ReplicatedStorage.Shared.Core.Entity)
local ConnectionUtil = require(ReplicatedStorage.Shared.Core.ConnectionUtil)

local PlayerScope = Entity:extend()
PlayerScope.className = "PlayerScope"

function PlayerScope.init(self: any, opts: { name: string })
	Entity.init(self, { id = "Scope:" .. opts.name })
	self._items = {} :: { any }
end

function PlayerScope.Add(self: any, item: any): any
	if item == nil then
		return nil
	end
	if self._destroyed then
		ConnectionUtil.disconnect(item)
		return nil
	end
	table.insert(self._items, item)
	return item
end

function PlayerScope.Spawn(self: any, fn: (...any) -> (), ...: any): thread
	local finished = false
	local thread: thread
	thread = task.spawn(function(...)
		fn(...)
		finished = true
		local index = thread and table.find(self._items, thread)
		if index then
			table.remove(self._items, index)
		end
	end, ...)
	-- task.spawn может завершиться до возврата потока: хранить его уже не нужно.
	return if finished then thread else self:Add(thread)
end

-- Отложенный вызов; сработал — ушёл из списка; scope уничтожен — не сработает.
function PlayerScope.Delay(self: any, seconds: number, fn: () -> ()): thread
	local thread: thread
	thread = task.delay(seconds, function()
		local index = table.find(self._items, thread)
		if index then
			table.remove(self._items, index)
		end
		if not self._destroyed then
			fn()
		end
	end)
	return self:Add(thread)
end

-- Сколько живого держим (для /player scope).
function PlayerScope.Count(self: any): number
	local n = 0
	for _, item in ipairs(self._items) do
		if typeof(item) == "thread" and coroutine.status(item) == "dead" then
			continue
		end
		if typeof(item) == "RBXScriptConnection" and not item.Connected then
			continue
		end
		n += 1
	end
	return n
end

function PlayerScope.IsAlive(self: any): boolean
	return not self._destroyed
end

function PlayerScope.destroy(self: any)
	if self._destroyed then
		return
	end
	local items = self._items
	self._items = {}
	Entity.destroy(self)
	ConnectionUtil.disconnectAll(items)
end

return PlayerScope
