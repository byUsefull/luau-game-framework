--!strict
--[[ ━━━ DataEvents · система data · общее, все плейсы
  Что: события шины data: профиль загружен, отпущен, изменён.
  Почему так: player ведёт порядок входа и выхода по ним; системы реагируют на изменения своих полей.
  Не здесь: PlayerReady / PlayerLeaving — PlayerEvents (система player).
━━━ ]]

local DataEvents = {
	ProfileLoaded = "ProfileLoaded", -- сервер · сессия открыта, схема долита, миграции прошли
	ProfileReleased = "ProfileReleased", -- сервер · сессия закрыта (выход, телепорт, смена режима)
	ProfileChanged = "ProfileChanged", -- сервер · после успешного Update / UpdatePair
	ProfileReloading = "ProfileReloading", -- сервер · до копирования/сохранения старой сессии при смене режима
}

export type ProfileLoaded = { player: Player, version: number, migrated: { number } }
export type ProfileReleased = { player: Player, saved: boolean, reason: string }
export type ProfileChanged = { player: Player, keys: { string }, reason: string }
export type ProfileReloading = { player: Player, fromMode: string, toMode: string }

return DataEvents
