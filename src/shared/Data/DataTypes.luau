--!strict
--[[ ━━━ DataTypes · система data · общее, все плейсы
  Что: типы публичного API DataService и DataController — для Registry:get(...) :: DataTypes.X.
  Почему так: типы живут у своей системы, а не в одном общем файле на всю игру.
  Не здесь: данные событий — DataEvents, данные каналов — DataChannels.
━━━ ]]

-- save — обычный; nosave — копия без записи (/data mode); fresh — тестовый профиль админа с нуля
export type Mode = "save" | "nosave" | "fresh"

-- Правка профиля: меняет переданную копию, без yield; вернуть false — отказ без ошибки.
export type Mutator = (data: { [string]: any }) -> boolean?
-- Преобразования только копии: синхронно, без yield; ошибка запрещает запись/подключение профиля.
export type SaveTransform = (snapshot: { [string]: any }, savedAt: number) -> ()
export type LoadTransform = (
	snapshot: { [string]: any },
	loadedAt: number,
	previousSaveTime: number?
) -> ()

export type DataService = {
	RegisterSaveTransform: (self: any, name: string, fn: SaveTransform) -> (),
	RegisterLoadTransform: (self: any, name: string, fn: LoadTransform) -> (),
	-- Открыть сессию (ждёт; зовёт PlayerService при входе). true — профиль готов.
	Load: (self: any, player: Player) -> boolean,
	IsLoaded: (self: any, player: Player) -> boolean,
	-- Живая таблица профиля ТОЛЬКО ДЛЯ ЧТЕНИЯ. Писать — через Update.
	Get: (self: any, player: Player) -> { [string]: any }?,
	-- Атомарная правка: всё или ничего. (ok, ошибка)
	Update: (self: any, player: Player, fn: Mutator, reason: string) -> (boolean, string?),
	-- Только объявленные разделы: callback получает их копии, чтения/записи других полей нет.
	UpdateFields: (
		self: any,
		player: Player,
		fields: { string },
		fn: Mutator,
		reason: string
	) -> (boolean, string?),
	-- Два профиля одной записью (обмен). Оба должны быть загружены на этом сервере.
	UpdatePair: (
		self: any,
		a: Player,
		b: Player,
		fn: (dataA: { [string]: any }, dataB: { [string]: any }) -> boolean?,
		reason: string
	) -> (boolean, string?),
	-- Записать в DataStore и дождаться подтверждения (покупки, обмены).
	SaveAndWait: (self: any, player: Player, reason: string) -> boolean,
	-- Сохранить и закрыть сессию (выход, телепорт). После неё Update отклоняется.
	Release: (self: any, player: Player, reason: string) -> boolean,
	-- Сообщение в профиль игрока по UserId (не в сети, другой сервер). Доходит при входе.
	SendMessage: (self: any, userId: number, message: { [string]: any }) -> boolean,
	-- Обработчик сообщений вида kind: fn(player, message) -> true, если обработано (тогда удаляется).
	OnMessage: (
		self: any,
		kind: string,
		fn: (player: Player, message: { [string]: any }) -> boolean
	) -> (),
	-- Удаление данных по UserId (запросы Roblox): свои хранилища систем подключают хуки.
	RegisterEraseHook: (self: any, name: string, fn: (userId: number) -> ()) -> (),
	Erase: (self: any, userId: number) -> (boolean, string),
	GetMode: (self: any, player: Player) -> Mode,
	SetMode: (self: any, player: Player, mode: Mode) -> (boolean, string),
	-- Флаг тестового профиля в НАСТОЯЩЕМ профиле; в режимах без записи — отдельной короткой сессией.
	SetFreshFlag: (self: any, player: Player, on: boolean) -> boolean,
	Wipe: (self: any, player: Player) -> boolean,
	SizeOf: (self: any, player: Player) -> number,
	-- Тест: следующие SaveAndWait игрока вернут false (имитация отказа DataStore).
	SetSaveFailure: (self: any, player: Player, on: boolean) -> (),
}

export type DataController = {
	IsReady: (self: any) -> boolean,
	-- Копия поля верхнего уровня (или всего снимка без key).
	Get: (self: any, key: string?) -> any,
	-- fn(key, value) на каждое изменение ключа; fn("*", снимок) на снимок. Возвращает связь.
	-- reason — причина записи на сервере (DataService:Update); снимок — nil.
	OnChanged: (
		self: any,
		fn: (key: string, value: any, reason: string?) -> ()
	) -> { Disconnect: (any) -> () },
}

return {}
