--!strict
--[[ ━━━ ServerMain · система core · сервер, все плейсы
  Что: загрузчик сервера: сеть (каналы всех систем) → синглтоны …Service → атрибут ServerReady → строка Boot.
  Почему так: один скрипт на плейс, не правится никогда — новый сервис = новый файл в src/server/<S>/.
  Не здесь: фазы и отчёт — ModuleLoader; поиск сервисов — Bootstrap; каналы — Network.
━━━ ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local Core = Shared.Core

local Bootstrap = require(Core.Bootstrap)
local CoreConfig = require(Core.CoreConfig)
local CoreEvents = require(Core.CoreEvents)
local EventBus = require(Core.EventBus)
local GameVersion = require(Core.GameVersion)
local Logger = require(Core.Logger)
local Network = require(Shared.Network.Network)

local log = Logger.new("Boot", true)
local began = os.clock()

-- Каналы всех систем: объявлены в <S>Channels, ошибка объявления — громко и сразу.
Network.start(Shared)

local folders: { Instance } = { ServerStorage.Server }
local placeServer = ServerStorage:FindFirstChild("PlaceServer")
if placeServer then
	table.insert(folders, placeServer)
end
local loader = Bootstrap.run("SERVER", "Service", folders)

ReplicatedStorage:SetAttribute(CoreConfig.Attr.ServerReady, true)

local ms = (os.clock() - began) * 1000
local placeKey = ReplicatedStorage:GetAttribute(CoreConfig.Attr.PlaceKey)
log:Info(
	"Boot · %s · плейс %s · сервер · OK %d · FAILED %d · SKIPPED %d · %.0fмс",
	GameVersion.get(),
	tostring(placeKey),
	loader:count("OK"),
	loader:count("FAILED"),
	loader:count("SKIPPED"),
	ms
)
EventBus:emit(
	CoreEvents.ModulesStarted,
	{
		side = "SERVER",
		ok = loader:count("OK"),
		failed = loader:count("FAILED"),
		skipped = loader:count("SKIPPED"),
		ms = ms,
	} :: CoreEvents.ModulesStarted
)
