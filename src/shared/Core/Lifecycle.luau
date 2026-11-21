--!strict
--[[ ━━━ Lifecycle · система core · общее, все плейсы
  Что: база синглтонов (…Service, …Controller): Init → Start → Destroy, _log, уборка _bind/_spawn/_delay.
  Почему так: Init — только ссылки и безусловный сброс состояния, Start — работа. Всё, что переживает
    вызов, кладётся через _bind/_spawn/_delay — Destroy уберёт само. Синглтон не создаётся через new:
    модуль возвращает сам себя, служебные поля ставит ModuleLoader до Init.
  Не здесь: объекты, которых много, — Entity; порядок фаз — ModuleLoader.
━━━ ]]

local Class = require(script.Parent.Class)
local Logger = require(script.Parent.Logger)
local ConnectionUtil = require(script.Parent.ConnectionUtil)

export type Lifecycle = {
	name: string,
	dependencies: { string }?,
	autoload: boolean?,
	Init: (self: any) -> (),
	Start: (self: any) -> (),
	Destroy: (self: any) -> (),
	_log: Logger.Logger,
	_connections: { any },
	_destroyed: boolean,
	_bind: (self: any, connection: any) -> any,
	_spawn: (self: any, fn: (...any) -> (), ...any) -> thread,
	_delay: (self: any, seconds: number, fn: () -> ()) -> thread,
}

local Lifecycle = Class:extend()

function Lifecycle.Init(_self: any) end

function Lifecycle.Start(_self: any) end

-- Под уборку: связь, поток, Instance, таблицу с Disconnect, функцию. Возвращает то же.
function Lifecycle._bind(self: any, connection: any): any
	if connection == nil then
		return nil
	end
	if self._destroyed then
		ConnectionUtil.disconnect(connection)
		return nil
	end
	self._connections = self._connections or {}
	table.insert(self._connections, connection)
	return connection
end

-- Поток, живущий не дольше синглтона; закончился — сам уходит из списка уборки (как _delay).
function Lifecycle._spawn(self: any, fn: (...any) -> (), ...: any): thread
	local finished = false
	local thread: thread
	thread = task.spawn(function(...)
		fn(...)
		finished = true
		local list = self._connections
		local index = thread and list and table.find(list, thread)
		if index then
			table.remove(list, index)
		end
	end, ...)
	if finished then
		return thread -- отработал без ожидания: убирать нечего
	end
	return self:_bind(thread)
end

-- Отложенный вызов; после срабатывания сам уходит из списка уборки.
function Lifecycle._delay(self: any, seconds: number, fn: () -> ()): thread
	local thread: thread
	thread = task.delay(seconds, function()
		local list = self._connections
		local index = list and table.find(list, thread)
		if index then
			table.remove(list, index)
		end
		if not self._destroyed then
			fn()
		end
	end)
	return self:_bind(thread)
end

-- Переопределяешь — зови Lifecycle.Destroy(self) в конце. Флаг опускает только ModuleLoader.
function Lifecycle.Destroy(self: any)
	if self._destroyed then
		return
	end
	self._destroyed = true
	ConnectionUtil.disconnectAll(self._connections)
	self._connections = {}
	if self._log then
		self._log:Debug("Destroyed")
	end
end

return Lifecycle
