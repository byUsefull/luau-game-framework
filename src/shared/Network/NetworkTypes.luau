--!strict
--[[ ━━━ NetworkTypes · система network · общее, все плейсы
  Что: типы системы network — синглтонов нет, API модуля Network описан в его файле и в паспорте.
  Почему так: у каждой системы свой <S>Types; Network — обычный модуль, его require можно всем.
  Не здесь: вид ответа запроса — ErrorCodes.Result.
━━━ ]]

export type Result = { ok: boolean, result: any?, errorCode: string? }

return {}
