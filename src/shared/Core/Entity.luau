--!strict
--[[ ━━━ Entity · система core · общее, все плейсы
  Что: база объектов игры: id «Класс#N», свой лог, ленивые сигналы, _bind, destroy с уборкой.
  Почему так: объектов много (окна, тосты, PlayerScope) — сигналы создаются только при подписке.
    Модель не уничтожается сама: ей может владеть пул; владелец решает в своём destroy.
  Не здесь: синглтоны — Lifecycle.
━━━ ]]

local Class = require(script.Parent.Class)
local Signal = require(script.Parent.Signal)
local Logger = require(script.Parent.Logger)
local ConnectionUtil = require(script.Parent.ConnectionUtil)

local nextId = 0

export type EntityOptions = { id: string?, model: Instance?, [string]: any }

export type Entity = {
	id: string,
	className: string,
	model: Instance?,
	Destroying: Signal.Signal,
	_log: Logger.Logger,
	_connections: { any },
	_destroyed: boolean,
	signal: (self: any, name: string) -> Signal.Signal,
	emit: (self: any, name: string, ...any) -> (),
	_bind: (self: any, connection: any) -> any,
	destroy: (self: any) -> (),
	isDestroyed: (self: any) -> boolean,
}

local Entity = Class:extend()
Entity.className = "Entity"

function Entity.init(self: any, options: EntityOptions?)
	local opts: EntityOptions = options or {}
	nextId += 1
	self.id = opts.id or string.format("%s#%d", self.className or "Entity", nextId)
	self.model = opts.model
	self._log = Logger.new(self.id)
	self._connections = {}
	self._signals = nil
	self._destroyed = false
	self.Destroying = Signal.new()
end

function Entity.signal(self: any, name: string): Signal.Signal
	local signals = self._signals
	if not signals then
		signals = {}
		self._signals = signals
	end
	local existing = signals[name]
	if existing then
		return existing
	end
	local created = Signal.new()
	signals[name] = created
	return created
end

function Entity.emit(self: any, name: string, ...: any)
	local signals = self._signals
	local signal = signals and signals[name]
	if signal then
		signal:Fire(...)
	end
end

function Entity._bind(self: any, connection: any): any
	if connection == nil then
		return nil
	end
	if self._destroyed then
		ConnectionUtil.disconnect(connection)
		return nil
	end
	table.insert(self._connections, connection)
	return connection
end

function Entity.isDestroyed(self: any): boolean
	return self._destroyed == true
end

-- Порядок: флаг → Destroying (подписчики видят живой объект) → подписки и сигналы.
function Entity.destroy(self: any)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self.Destroying:Fire(self)
	self.Destroying:DisconnectAll()
	ConnectionUtil.disconnectAll(self._connections)
	self._connections = {}
	if self._signals then
		for _, signal in pairs(self._signals) do
			signal:DisconnectAll()
		end
		self._signals = nil
	end
	self.model = nil
end

return Entity
