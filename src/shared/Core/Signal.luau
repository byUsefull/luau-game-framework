--!strict
--[[ ━━━ Signal · система core · общее, все плейсы
  Что: сигнал объекта: Connect, Once, Fire, Wait, DisconnectAll. Обработчики синхронно, каждый в pcall.
  Почему так: упавший подписчик не срывает рассылку; обход по снимку — подписка внутри обработчика безопасна.
  Не здесь: события «в игре случилось» — EventBus; сервер ↔ клиент — Network.
━━━ ]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, handler: (...any) -> ()) -> Connection,
	Once: (self: Signal, handler: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	Wait: (self: Signal) -> ...any,
	DisconnectAll: (self: Signal) -> (),
	CountConnections: (self: Signal) -> number,
}

type Record = { Connected: boolean, fn: (...any) -> () }

local Connection = {}
Connection.__index = Connection

local Signal = {}
Signal.__index = Signal

function Signal.new(): Signal
	return (setmetatable({ _records = {} :: { Record }, _dead = 0 }, Signal) :: any) :: Signal
end

local function compact(self: any)
	local records = self._records
	local write = 1
	for read = 1, #records do
		if records[read].Connected then
			records[write] = records[read]
			write += 1
		end
	end
	for i = #records, write, -1 do
		records[i] = nil
	end
	self._dead = 0
end

function Signal.Connect(self: any, handler: (...any) -> ()): Connection
	assert(
		type(handler) == "function",
		"Signal:Connect — нужен обработчик-функция"
	)
	local record: Record = { Connected = true, fn = handler }
	table.insert(self._records, record)
	local connection =
		setmetatable({ _record = record, _signal = self, Connected = true }, Connection)
	return (connection :: any) :: Connection
end

function Signal.Once(self: any, handler: (...any) -> ()): Connection
	local connection: Connection
	connection = Signal.Connect(self, function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal.Fire(self: any, ...: any)
	local records = self._records
	local count = #records
	if count == 0 then
		return
	end
	local snapshot = table.create(count)
	table.move(records, 1, count, 1, snapshot)
	for i = 1, count do
		local record = snapshot[i]
		if record.Connected then
			local ok, err = pcall(record.fn, ...)
			if not ok then
				warn(string.format("[Signal] обработчик упал: %s", tostring(err)))
			end
		end
	end
	if self._dead > 8 and self._dead * 2 > #records then
		compact(self)
	end
end

function Signal.Wait(self: any): ...any
	local thread = coroutine.running()
	Signal.Once(self, function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal.DisconnectAll(self: any)
	for _, record in ipairs(self._records) do
		record.Connected = false
	end
	self._records = {}
	self._dead = 0
end

function Signal.CountConnections(self: any): number
	local n = 0
	for _, record in ipairs(self._records) do
		if record.Connected then
			n += 1
		end
	end
	return n
end

function Connection.Disconnect(self: any)
	if not self.Connected then
		return
	end
	self.Connected = false
	self._record.Connected = false
	self._signal._dead += 1
end

return Signal
