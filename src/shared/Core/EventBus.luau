--!strict
--[[ ━━━ EventBus · система core · общее, все плейсы
  Что: события внутри одной стороны: on, once, emit. Данные — одна таблица, тип в <S>Events.
  Почему так: имена только из <S>Events (строки ловит линтер L18); каждый обработчик в pcall,
    обход по снимку, мёртвые подписки выметаются, когда их накопилось много.
  Не здесь: сервер ↔ клиент — Network; сигнал конкретного объекта — Signal.
━━━ ]]

export type Connection = { Disconnect: (self: Connection) -> () }

type Record = { active: boolean, fn: (any) -> () }
type Bucket = { records: { Record }, dead: number }

local EventBus = {}

local buckets: { [string]: Bucket } = {}

local function compact(bucket: Bucket)
	local write = 1
	for read = 1, #bucket.records do
		if bucket.records[read].active then
			bucket.records[write] = bucket.records[read]
			write += 1
		end
	end
	for i = #bucket.records, write, -1 do
		bucket.records[i] = nil
	end
	bucket.dead = 0
end

function EventBus.on(_self: any, eventName: string, handler: (any) -> ()): Connection
	assert(
		type(eventName) == "string" and eventName ~= "",
		"EventBus:on — пустое имя события"
	)
	assert(
		type(handler) == "function",
		"EventBus:on — нужен обработчик-функция"
	)
	local bucket = buckets[eventName]
	if not bucket then
		bucket = { records = {}, dead = 0 }
		buckets[eventName] = bucket
	end
	local record: Record = { active = true, fn = handler }
	table.insert(bucket.records, record)
	local owner = bucket
	return {
		Disconnect = function(_connection: Connection)
			if record.active then
				record.active = false
				owner.dead += 1
			end
		end,
	}
end

function EventBus.once(self: any, eventName: string, handler: (any) -> ()): Connection
	local connection: Connection
	connection = EventBus.on(self, eventName, function(data: any)
		connection:Disconnect()
		handler(data)
	end)
	return connection
end

function EventBus.emit(_self: any, eventName: string, data: any?)
	local bucket = buckets[eventName]
	if not bucket or #bucket.records == 0 then
		return
	end
	local count = #bucket.records
	local snapshot = table.create(count)
	table.move(bucket.records, 1, count, 1, snapshot)
	for i = 1, count do
		local record = snapshot[i]
		if record.active then
			local ok, err = pcall(record.fn, data)
			if not ok then
				warn(
					string.format(
						"[EventBus] обработчик '%s' упал: %s",
						eventName,
						tostring(err)
					)
				)
			end
		end
	end
	if bucket.dead > 8 and bucket.dead * 2 > #bucket.records then
		compact(bucket)
	end
end

function EventBus.listenerCount(_self: any, eventName: string): number
	local bucket = buckets[eventName]
	local n = 0
	for _, record in ipairs(bucket and bucket.records or {}) do
		if record.active then
			n += 1
		end
	end
	return n
end

function EventBus.clearAll(_self: any)
	for _, bucket in pairs(buckets) do
		for _, record in ipairs(bucket.records) do
			record.active = false
		end
	end
	buckets = {}
end

return EventBus
