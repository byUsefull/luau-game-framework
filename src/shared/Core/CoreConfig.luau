--!strict
--[[ ━━━ CoreConfig · система core · общее, все плейсы
  Что: версия игры, уровни логов, настройки часов и загрузки, имена атрибутов ядра.
  Почему так: числа каркаса правятся здесь, без правки кода; атрибуты объявлены один раз на игру.
  Не здесь: строка версии целиком — GameVersion; сами часы — ServerClock.
━━━ ]]

local CoreConfig = {
	-- Номер версии из changelog игры. Поднимать с каждым обновлением: к нему добавится PlaceVersion.
	Version = "0.1.0",

	-- Уровни логов: 1 Debug · 2 Info · 3 Warn · 4 Critical.
	Log = {
		StudioLevel = 2,
		LiveLevel = 2,
		-- Области со своим порогом: ["Network"] = 1
		Scopes = {} :: { [string]: number },
	},

	Clock = {
		-- Час UTC, когда начинается новый игровой день.
		DayResetHourUtc = 0,
		-- Как часто сервер проверяет смену дня, секунды.
		CheckPeriod = 1,
	},

	Boot = {
		-- Сколько клиент ждёт ServerReady, секунды.
		ServerReadyTimeout = 60,
		-- Сколько самых медленных модулей называть в отчёте загрузки.
		SlowTop = 3,
		-- Модули быстрее этого в «дольше всего» не попадают, мс.
		SlowFloorMs = 1,
	},

	Attr = {
		ServerReady = "ServerReady",
		PlaceKey = "PlaceKey",
		ClockOffset = "ClockOffset",
		Author = "Author",
		Card = "Card",
		Source = "Source",
		Variant = "Variant",
	},
}

return CoreConfig
