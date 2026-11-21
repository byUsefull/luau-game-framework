--!strict
--[[ ━━━ NetworkEvents · система network · общее, все плейсы
  Что: события шины системы network и типы их данных.
  Почему так: отказ канала — факт, на который подпишется moderation (сводка подозрений), а не вызов.
  Не здесь: счётчики отказов — Throttle, команда /network stats.
━━━ ]]

local NetworkEvents = {
	RemoteRejected = "RemoteRejected", -- сервер · запрос отклонён: лимит, проверка данных, NotReady
}

export type RemoteRejected = { player: Player, channel: string, reason: string }

return NetworkEvents
