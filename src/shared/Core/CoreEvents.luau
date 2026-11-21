--!strict
--[[ ━━━ CoreEvents · система core · общее, все плейсы
  Что: события шины каркаса и типы их данных.
  Почему так: имена из одного места — опечатка не даёт тихий «призрак».
  Не здесь: события входа и выхода игрока (PlayerReady, ClientReady, PlayerLeaving, CharacterReady) — PlayerEvents.
━━━ ]]

local CoreEvents = {
	ModulesStarted = "ModulesStarted", -- обе стороны · все синглтоны прошли Start
	DayChanged = "DayChanged", -- сервер · сменился игровой день (или сдвиг часов)
}

export type ModulesStarted =
	{ side: string, ok: number, failed: number, skipped: number, ms: number }
export type DayChanged = { day: number, previous: number }

return CoreEvents
