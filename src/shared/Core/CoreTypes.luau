--!strict
--[[ ━━━ CoreTypes · система core · общее, все плейсы
  Что: типы публичного API синглтонов системы core — для Registry:get(...) :: CoreTypes.X.
  Почему так: типы живут у своей системы, а не в одном общем файле на всю игру.
  Не здесь: данные событий — CoreEvents.
━━━ ]]

export type ClockService = {
	-- Проверить смену дня сейчас (после сдвига часов). Шлёт DayChanged, если день другой.
	CheckDay: (self: any) -> (),
	CurrentDay: (self: any) -> number,
}

return {}
