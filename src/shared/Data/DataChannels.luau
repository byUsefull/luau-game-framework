--!strict
--[[ ━━━ DataChannels · система data · общее, все плейсы
  Что: каналы data: снимок профиля клиенту после ClientReady и изменения по ключам верхнего уровня.
  Почему так: клиент держит копию только для чтения; приватные поля (DataConfig.Private) не уходят.
  Не здесь: обработчики — DataService (отправка) и DataController (приём).
━━━ ]]

local DataChannels = {
	DATA_SNAPSHOT = "DATA_SNAPSHOT",
	DATA_CHANGED = "DATA_CHANGED",
}

DataChannels.Spec = {
	[DataChannels.DATA_SNAPSHOT] = {
		kind = "Event",
		direction = "ServerToClient",
		note = "полный публичный снимок профиля после ClientReady",
	},
	[DataChannels.DATA_CHANGED] = {
		kind = "Event",
		direction = "ServerToClient",
		note = "изменённые ключи верхнего уровня после Update",
	},
}

export type Snapshot = { data: { [string]: any } }
export type Changed = { values: { [string]: any }, removed: { string }, reason: string }

return DataChannels
