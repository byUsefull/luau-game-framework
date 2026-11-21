--!strict
--[[ ━━━ DataConfig · система data · общее, все плейсы
  Что: имя хранилища, версия и схема профиля по умолчанию, приватные поля, тексты киков, лимиты.
  Почему так: схема одна на игру; у каждого поля верхнего уровня один владелец-сервис (подписан ниже).
    Новое поле — сюда, оно само дольётся старым игрокам. Смысл поля поменялся — версия + DataMigrations.
  Не здесь: запись — только DataService:Update; миграции — DataMigrations.
━━━ ]]

local DataConfig = {
	-- Смена имени хранилища = все игроки с нуля. Менять только осознанно.
	StoreName = "PlayerData",
	-- В Studio своё хранилище: тесты не трогают живые данные.
	StudioStoreSuffix = "_Studio",
	KeyPrefix = "Player_",

	Version = 1,
	VersionField = "_version",
	-- Приватный барьер SaveAndWait: подтверждение только снимка с этим или более новым номером.
	SaveRevisionKey = "_saveRevision",

	-- Схема профиля. Только JSON-совместимое: без Instance, Vector3, Color3, NaN, массивов с дырами.
	-- У каждого поля верхнего уровня один владелец-сервис.
	Default = {
		_version = 1,
		_saveRevision = 0,
		-- player (PlayerService): входы, первый вход, наигранное время
		Player = { visits = 0, firstJoin = 0, lastJoin = 0, playTime = 0 },
		-- settings: значения настроек игрока (ключ → значение; нет ключа — по умолчанию)
		Settings = { values = {} },
		-- coins (CoinsService): пример системы — монеты за клики
		Coins = { coins = 0, clicks = 0 },
	},

	-- Поля верхнего уровня, которые не уходят клиенту.
	Private = {
		_version = true,
		_saveRevision = true,
	} :: { [string]: boolean },

	-- Тестовый профиль админа: флаг — Settings.values[FreshKey] (строка настроек только для админа).
	-- Вход с флагом: настоящая сессия закрывается без правок, игрок играет на Mock-сессии с данными по
	-- умолчанию (режим fresh) — в DataStore ничего не пишется, каждый вход как новый игрок.
	FreshKey = "freshProfile",

	KickOnLoadFail = true,
	KickOnLockLost = true,
	Text = {
		LoadFailed = "Could not load your data. Please rejoin in a minute.",
		LockLost = "Your data was opened on another server. Please rejoin.",
	},

	-- Сколько ждать подтверждения записи в SaveAndWait, секунды.
	SaveConfirmTimeout = 10,
	-- Если player не отпустил профиль после выхода — data отпускает сам через столько секунд.
	ReleaseFallback = 15,
	-- Предупреждение о размере профиля (лимит Roblox — 4 МБ), байты.
	SizeWarnBytes = 3_000_000,
}

return DataConfig
