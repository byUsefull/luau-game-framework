--!strict
--[[ ━━━ Network · система network · общее, все плейсы
  Что: единственный путь между клиентом и сервером: onServerEvent, onServerInvoke, fireClient, fireClients,
    fireAllClients, onClientEvent, fireServer, invokeServer — только по каналам из <S>Channels.
  Почему так: start собирает объявления всех систем и создаёт remotes на старте (ошибка — громко сразу).
    Сервер слушает только с validate; лимит частоты из объявления канала; запросы до готовности
    игрока отклоняются кодом NotReady; каждый обработчик в pcall; отказ → событие RemoteRejected.
    Направление и вид канала проверяются в момент вызова. Ушедшему игроку ничего не шлётся.
  Не здесь: проверки данных — Validate; сверка объявлений — NetworkRegistry; лимиты — Throttle;
    объекты remotes — Remotes.
━━━ ]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Core = script.Parent.Parent.Core

local EventBus = require(Core.EventBus)
local Logger = require(Core.Logger)
local NetworkRegistry = require(script.Parent.NetworkRegistry)
local NetworkEvents = require(script.Parent.NetworkEvents)
local Remotes = require(script.Parent.Remotes)
local Throttle = require(script.Parent.Throttle)
local Validate = require(script.Parent.Validate)
local ErrorCodes = require(script.Parent.ErrorCodes)

local log = Logger.new("Network")

local IS_SERVER = RunService:IsServer()

export type HandlerOptions = {
	validate: Validate.Validator,
	-- true — можно до готовности игрока (PLAYER_READY и подобные). По умолчанию отказ NotReady.
	beforeReady: boolean?,
}

local channels: { [string]: NetworkRegistry.Channel } = {}
local started = false
local throttle = Throttle.new()
local readyCheck: ((Player) -> boolean)? = nil

local Network = {}

local function specOf(
	name: string,
	want: NetworkRegistry.Direction,
	what: string
): NetworkRegistry.Channel
	assert(started, "[Network] нет start (ServerMain)")
	local channel = channels[name]
	if not channel then
		error(string.format("[Network] %s: нет канала %s", what, tostring(name)), 3)
	end
	if not NetworkRegistry.allows(channel, want) then
		error(
			string.format("[Network] %s: канал '%s' — %s", what, name, channel.direction),
			3
		)
	end
	return channel
end

local function remote(channel: NetworkRegistry.Channel): Instance?
	return Remotes.get(channel.name, channel.kind)
end

-- Сбор объявлений всех <S>Channels под shared и (на сервере) создание всех remotes.
function Network.start(shared: Instance)
	if started then
		return
	end
	local modules: { [string]: any } = {}
	local moduleCount = 0
	for _, child in ipairs(shared:GetDescendants()) do
		if child:IsA("ModuleScript") and string.sub(child.Name, -8) == "Channels" then
			local ok, result = pcall(require, child)
			if ok then
				modules[child.Name] = result
				moduleCount += 1
			else
				log:Critical("require %s упал: %s", child:GetFullName(), tostring(result))
			end
		end
	end
	local collected, errors = NetworkRegistry.collect(modules)
	for _, message in ipairs(errors) do
		log:Critical("объявление канала: %s", message)
	end
	channels = collected
	started = true
	local count = 0
	for _, channel in pairs(channels) do
		count += 1
		if IS_SERVER then
			remote(channel)
		end
	end
	if IS_SERVER then
		Players.PlayerRemoving:Connect(function(player)
			throttle:forget(player.UserId)
		end)
	end
	log:Info("каналов %d · систем %d · ошибок %d", count, moduleCount, #errors)
	if #errors > 0 and IS_SERVER then
		error(string.format("[Network] ошибок объявления: %d", #errors), 0)
	end
end

-- Проверка готовности игрока (регистрирует player). Без неё готовы все.
function Network.setReadyCheck(fn: (Player) -> boolean)
	readyCheck = fn
end

local function rejectWith(player: Player, channel: string, reason: string, counted: boolean?)
	if not counted then
		throttle:reject(channel, reason)
	end
	log:Debug("отказ %s · %s · %s", channel, player.Name, reason)
	EventBus:emit(
		NetworkEvents.RemoteRejected,
		{ player = player, channel = channel, reason = reason } :: NetworkEvents.RemoteRejected
	)
end

local function guard(
	player: Player,
	channel: NetworkRegistry.Channel,
	payload: any,
	opts: HandlerOptions
): boolean
	throttle:count(channel.name)
	if not throttle:allow(player.UserId, channel.name, channel.rate, os.clock()) then
		rejectWith(player, channel.name, ErrorCodes.Throttled, true)
		return false
	end
	if not opts.beforeReady and readyCheck and not readyCheck(player) then
		rejectWith(player, channel.name, ErrorCodes.NotReady)
		return false
	end
	local ok, valid = pcall(opts.validate, payload, player)
	if not ok then
		log:Critical("валидатор '%s' упал: %s", channel.name, tostring(valid))
	end
	if not ok or not valid then
		rejectWith(player, channel.name, if ok then ErrorCodes.BadRequest else "ValidatorError")
		return false
	end
	return true
end

local function requireOptions(name: string, options: HandlerOptions?): HandlerOptions
	if not options or type(options.validate) ~= "function" then
		error(string.format("[Network] %s: нужен validate", name), 3)
	end
	return options
end

function Network.onServerEvent(
	name: string,
	handler: (Player, any) -> (),
	options: HandlerOptions?
): RBXScriptConnection
	assert(IS_SERVER, "onServerEvent — только сервер")
	local channel = specOf(name, "ClientToServer", "onServerEvent")
	assert(channel.kind ~= "Function", "onServerEvent: Function → onServerInvoke")
	local opts = requireOptions(name, options)
	return Remotes.onServer(remote(channel) :: Instance, function(player: Player, payload: any)
		if not guard(player, channel, payload, opts) then
			return
		end
		local ok, err = pcall(handler, player, payload)
		if not ok then
			log:Critical("%s (%s) упал: %s", name, player.Name, tostring(err))
		end
	end)
end

-- Ответ — результат обработчика; отказ — { ok = false, errorCode }.
function Network.onServerInvoke(
	name: string,
	handler: (Player, any) -> any,
	options: HandlerOptions?
)
	assert(IS_SERVER, "onServerInvoke — только сервер")
	local channel = specOf(name, "ClientToServer", "onServerInvoke")
	assert(channel.kind == "Function", "onServerInvoke: нужен канал вида Function")
	local opts = requireOptions(name, options)
	Remotes.setInvoke(remote(channel) :: Instance, function(player: Player, payload: any): any
		if not guard(player, channel, payload, opts) then
			return { ok = false, errorCode = ErrorCodes.BadRequest }
		end
		local ok, result = pcall(handler, player, payload)
		if not ok then
			log:Critical("invoke '%s' (%s) упал: %s", name, player.Name, tostring(result))
			return { ok = false, errorCode = ErrorCodes.Failed }
		end
		return result
	end)
end

function Network.fireClient(name: string, player: Player, payload: any?)
	assert(IS_SERVER, "fireClient — только сервер")
	local channel = specOf(name, "ServerToClient", "fireClient")
	if player.Parent == Players then
		Remotes.fireClient(remote(channel) :: Instance, player, payload)
	end
end

function Network.fireClients(name: string, players: { Player }, payload: any?)
	assert(IS_SERVER, "fireClients — только сервер")
	local target = remote(specOf(name, "ServerToClient", "fireClients")) :: Instance
	for _, player in ipairs(players) do
		if player.Parent == Players then
			Remotes.fireClient(target, player, payload)
		end
	end
end

function Network.fireAllClients(name: string, payload: any?)
	assert(IS_SERVER, "fireAllClients — только сервер")
	Remotes.fireAll(remote(specOf(name, "ServerToClient", "fireAllClients")) :: Instance, payload)
end

function Network.onClientEvent(name: string, handler: (any) -> ()): RBXScriptConnection?
	assert(not IS_SERVER, "onClientEvent — только клиент")
	local target = remote(specOf(name, "ServerToClient", "onClientEvent"))
	if not target then
		return nil
	end
	return Remotes.onClient(target, function(payload: any)
		local ok, err = pcall(handler, payload)
		if not ok then
			log:Critical("клиент %s упал: %s", name, tostring(err))
		end
	end)
end

function Network.fireServer(name: string, payload: any?)
	assert(not IS_SERVER, "fireServer — только клиент")
	local target = remote(specOf(name, "ClientToServer", "fireServer"))
	if target then
		Remotes.fireServer(target, payload)
	end
end

-- Ждёт ответа сервера. Ошибка → { ok = false, errorCode = "Failed" }.
function Network.invokeServer(name: string, payload: any?): any
	assert(not IS_SERVER, "invokeServer — только клиент")
	local target = remote(specOf(name, "ClientToServer", "invokeServer"))
	local ok, result = pcall(function()
		return Remotes.invokeServer(target :: Instance, payload)
	end)
	if not ok then
		log:Warn("invokeServer '%s' упал: %s", name, tostring(result))
		return { ok = false, errorCode = ErrorCodes.Failed }
	end
	return result
end

-- Объявления каналов и счётчики (для /network stats).
function Network.channels(): { [string]: NetworkRegistry.Channel }
	return channels
end

function Network.stats(): { [string]: Throttle.Stat }
	return throttle:stats()
end

function Network.trackedPlayers(): number
	return throttle:tracked()
end

return Network
