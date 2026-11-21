--!strict
--[[ ━━━ CoreChannels · система core · общее, все плейсы
  Что: сетевые каналы системы core — их нет.
  Почему так: сдвиг часов и готовность сервера уходят клиенту атрибутами (CoreConfig.Attr), а не событиями.
  Не здесь: каналы других систем — в их <S>Channels.
━━━ ]]

local CoreChannels = {}

CoreChannels.Spec = {}

return CoreChannels
