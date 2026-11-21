--!strict
--[[ ━━━ PlayerEvents · система player · общее, все плейсы
  Что: загрузка игрока, уход с завершающим барьером и готовность персонажа.
  Почему так: один порядок входа и выхода для всех систем; других «загрузочных» событий не заводим.
  Не здесь: профиль загружен / отпущен — DataEvents.
━━━ ]]

local PlayerEvents = {
	PlayerReady = "PlayerReady", -- сервер · профиль загружен (данные есть), клиент может ещё грузиться
	ClientReady = "ClientReady", -- сервер · данные есть и клиент слушает — слать стартовое состояние
	PlayerLeaving = "PlayerLeaving", -- сервер · игрок уходит: завершить своё быстро, без yield
	PlayerLeavingFinished = "PlayerLeavingFinished", -- сервер · все обработчики ухода завершены, профиль ещё доступен
	CharacterReady = "CharacterReady", -- сервер · у персонажа есть Humanoid, корень и Animator
}

export type PlayerReady = { player: Player, firstVisit: boolean, visits: number }
export type ClientReady = { player: Player }
export type PlayerLeaving = { player: Player, sessionTime: number, reason: string }
export type PlayerLeavingFinished = {
	player: Player,
	sessionTime: number,
	reason: string,
	profileLoaded: boolean,
}
export type CharacterReady =
	{ player: Player, character: Model, humanoid: Humanoid, root: BasePart }

return PlayerEvents
