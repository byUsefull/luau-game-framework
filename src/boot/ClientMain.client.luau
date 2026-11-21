--!strict
--[[ ━━━ ClientMain · система core · клиент, все плейсы
  Что: загрузчик клиента: ждёт ServerReady → сеть → синглтоны …Controller → строка Boot → ModulesStarted.
  Почему так: один скрипт на плейс, не правится никогда — новый контроллер = новый файл в src/client/<S>/.
    ModulesStarted ловит PlayerController и только тогда сообщает серверу, что клиент слушает.
  Не здесь: фазы и отчёт — ModuleLoader; поиск контроллеров — Bootstrap; экран загрузки — система loading.
━━━ ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Core = Shared:WaitForChild("Core", 60)

local Bootstrap = require(Core.Bootstrap)
local BootGate = require(Core.BootGate)
local CoreConfig = require(Core.CoreConfig)
local CoreEvents = require(Core.CoreEvents)
local EventBus = require(Core.EventBus)
local GameVersion = require(Core.GameVersion)
local Logger = require(Core.Logger)
local Network = require(Shared.Network.Network)

local log = Logger.new("Boot", true)
local began = os.clock()

if
	not BootGate.waitForAttribute(
		ReplicatedStorage,
		CoreConfig.Attr.ServerReady,
		CoreConfig.Boot.ServerReadyTimeout
	)
then
	log:Critical(
		"сервер не поднялся за %dс — клиент стартует как есть",
		CoreConfig.Boot.ServerReadyTimeout
	)
end

Network.start(Shared)

local folders: { Instance } = { ReplicatedStorage:WaitForChild("Client", 30) }
local placeClient = ReplicatedStorage:FindFirstChild("PlaceClient")
if placeClient then
	table.insert(folders, placeClient)
end
local loader = Bootstrap.run("CLIENT", "Controller", folders)

local ms = (os.clock() - began) * 1000
log:Info(
	"Boot · %s · клиент · OK %d · FAILED %d · SKIPPED %d · %.0fмс",
	GameVersion.get(),
	loader:count("OK"),
	loader:count("FAILED"),
	loader:count("SKIPPED"),
	ms
)
EventBus:emit(
	CoreEvents.ModulesStarted,
	{
		side = "CLIENT",
		ok = loader:count("OK"),
		failed = loader:count("FAILED"),
		skipped = loader:count("SKIPPED"),
		ms = ms,
	} :: CoreEvents.ModulesStarted
)
