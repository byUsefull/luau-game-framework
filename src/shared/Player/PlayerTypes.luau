--!strict
--[[ ━━━ PlayerTypes · система player · общее, все плейсы
  Что: типы публичного API PlayerService, CharacterService, PlayerController, PlayerScope, GamePlayer.
  Почему так: типы живут у своей системы; Registry:get(...) :: PlayerTypes.X даёт автодополнение.
  Не здесь: данные событий — PlayerEvents.
━━━ ]]

export type PlayerScope = {
	-- Под уборку: связь, Instance, функция, поток, таблица с Disconnect/Destroy. Возвращает то же.
	Add: (self: any, item: any) -> any,
	-- Поток / отложенный вызов, живущие не дольше игрока.
	Spawn: (self: any, fn: (...any) -> (), ...any) -> thread,
	Delay: (self: any, seconds: number, fn: () -> ()) -> thread,
	Count: (self: any) -> number,
	IsAlive: (self: any) -> boolean,
}

export type GamePlayer = {
	player: Player,
	scope: PlayerScope,
	firstVisit: boolean,
	dataReady: boolean,
	visits: number,
	GetSessionTime: (self: any) -> number,
	-- Ранг в группе игры: один запрос на вход, ошибка → 0.
	GetGroupRank: (self: any) -> number,
	RefreshGroupRank: (self: any) -> number,
	-- Сессионное состояние систем (не сохраняется): ключ — id системы.
	GetState: (self: any, key: string) -> any,
	SetState: (self: any, key: string, value: any) -> (),
}

export type PlayerService = {
	Get: (self: any, player: Player) -> GamePlayer?,
	GetScope: (self: any, player: Player) -> PlayerScope?,
	-- Сохранённый онлайн текущего профиля + ещё не записанный отрезок текущего режима.
	PlayTime: (self: any, player: Player) -> number,
	-- Барьер ухода без yield; повторный вызов не повторяет игровые обработчики.
	PrepareDeparture: (self: any, player: Player, reason: string) -> boolean,
	-- Сначала подготовить всех; освобождение профилей выполняет владелец после этого барьера.
	PrepareShutdown: (self: any) -> number,
	-- Данные загружены и клиент слушает (атрибут ProfileReady).
	IsReady: (self: any, player: Player) -> boolean,
	-- Этапы входа и времена (для /player info).
	Describe: (self: any, player: Player) -> string,
}

export type CharacterService = {
	-- Загрузить (или перезагрузить) персонажа сейчас.
	Spawn: (self: any, player: Player) -> (),
	-- Где появляться: система спавна игры регистрирует себя. nil — место по умолчанию.
	SetSpawnProvider: (self: any, fn: (player: Player) -> CFrame?) -> (),
	-- Когда возрождать после смерти: health регистрирует. nil — не возрождать автоматически.
	SetRespawnPolicy: (self: any, fn: (player: Player) -> number?) -> (),
	-- Связи и объекты, которые живут до смерти или смены персонажа.
	GetCharacterScope: (self: any, player: Player) -> PlayerScope?,
	-- Насколько тело больше обычного, studs (регистрирует игровая система). nil — снять.
	SetReachProvider: (self: any, fn: ((player: Player) -> number)?) -> (),
	-- Запас тела игрока к дистанциям «от корня до точки» (промпты, звуки, эффекты, точки появления).
	Reach: (self: any, player: Player) -> number,
	Respawns: (self: any, player: Player) -> number,
}

export type PlayerController = {
	IsReady: (self: any) -> boolean,
	-- fn сразу, если ProfileReady уже есть, иначе один раз, когда появится.
	WhenReady: (self: any, fn: () -> ()) -> (),
}

return {}
