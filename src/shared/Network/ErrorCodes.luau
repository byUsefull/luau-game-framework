--!strict
--[[ ━━━ ErrorCodes · система network · общее, все плейсы
  Что: общие коды ошибок ответов X_RESULT { ok, errorCode } и тексты игроку по коду (английские).
  Почему так: один список на игру — отказ показывается одинаково, через notify (error / warning).
  Не здесь: показ тоста — Notify.show; свои коды системы добавляет сюда строкой.
━━━ ]]

local ErrorCodes = {
	NotReady = "NotReady",
	Throttled = "Throttled",
	BadRequest = "BadRequest",
	NotAllowed = "NotAllowed",
	NotEnough = "NotEnough",
	NotFound = "NotFound",
	Busy = "Busy",
	Failed = "Failed",
}

-- Тексты игроку по коду.
ErrorCodes.Text = {
	NotReady = "Still loading, try again in a moment",
	NotLoaded = "Still loading, try again in a moment",
	Throttled = "Too fast, slow down",
	BadRequest = "Something went wrong",
	NotAllowed = "You can't do that right now",
	NotEnough = "Not enough",
	NotFound = "Not found",
	Busy = "Busy, try again",
	Failed = "Something went wrong, try again",
}

export type Result = { ok: boolean, result: any?, errorCode: string? }

return ErrorCodes
