--!strict
--[[ ━━━ Remotes · система network · общее, все плейсы
  Что: папка ReplicatedStorage.Remotes и объекты каналов: сервер создаёт, клиент ждёт с тайм-аутом.
  Почему так: сырые RemoteEvent / RemoteFunction / UnreliableRemoteEvent живут только в системе network
    (правило L15); папка берётся лениво — require(Network) не блокирует ни Edit, ни тесты.
  Не здесь: проверки, лимиты и направления — Network.
━━━ ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Logger = require(script.Parent.Parent.Core.Logger)

local log = Logger.new("Network")

local IS_SERVER = RunService:IsServer()
local FOLDER = "Remotes"
local CLIENT_WAIT = 30

local CLASS = {
	Event = "RemoteEvent",
	Unreliable = "UnreliableRemoteEvent",
	Function = "RemoteFunction",
}

local Remotes = {}

local cached: Instance? = nil

local function folder(): Instance
	if cached and cached.Parent then
		return cached
	end
	local found = ReplicatedStorage:FindFirstChild(FOLDER)
	if not found and IS_SERVER then
		found = Instance.new("Folder")
		found.Name = FOLDER
		found.Parent = ReplicatedStorage
	elseif not found then
		found = ReplicatedStorage:WaitForChild(FOLDER, CLIENT_WAIT)
	end
	assert(
		found,
		"[Network] папка Remotes не появилась — сервер не поднялся?"
	)
	cached = found
	return found
end

-- Объект канала: на сервере создаётся при первом обращении, клиент ждёт до 30 с.
function Remotes.get(name: string, kind: string): Instance?
	local found = folder():FindFirstChild(name)
	if found then
		return found
	end
	if IS_SERVER then
		local remote = Instance.new(CLASS[kind] or "RemoteEvent")
		remote.Name = name
		remote.Parent = folder()
		return remote
	end
	found = folder():WaitForChild(name, CLIENT_WAIT)
	if not found then
		log:Critical("канал '%s' не создан сервером", name)
	end
	return found
end

function Remotes.fireClient(remote: Instance, player: Player, payload: any)
	(remote :: any):FireClient(player, payload)
end

function Remotes.fireAll(remote: Instance, payload: any)
	(remote :: any):FireAllClients(payload)
end

function Remotes.fireServer(remote: Instance, payload: any)
	(remote :: any):FireServer(payload)
end

function Remotes.invokeServer(remote: Instance, payload: any): any
	return (remote :: any):InvokeServer(payload)
end

function Remotes.onServer(remote: Instance, fn: (Player, any) -> ()): RBXScriptConnection
	return (remote :: any).OnServerEvent:Connect(fn)
end

function Remotes.onClient(remote: Instance, fn: (any) -> ()): RBXScriptConnection
	return (remote :: any).OnClientEvent:Connect(fn)
end

function Remotes.setInvoke(remote: Instance, fn: (Player, any) -> any)
	(remote :: RemoteFunction).OnServerInvoke = fn
end

return Remotes
