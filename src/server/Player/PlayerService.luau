--!strict
--[[ ━━━ PlayerService · система player · сервер, все плейсы
  Что: порядок входа и выхода для всех систем. Вход: профиль грузится сразу при PlayerAdded →
    PlayerReady; клиент прислал PLAYER_READY → ClientReady → атрибут ProfileReady. Выход и закрытие
    сервера: остаток времени → PlayerLeaving → PlayerLeavingFinished → Release → уничтожение PlayerScope.
  Почему так: системы знают, когда игрок готов и когда уходит; стартовое состояние — только после
    ClientReady; всё на игрока лежит в его scope и убирается после сохранения, в каком бы месте он ни вышел.
  Не здесь: сессии профиля — DataService; персонаж — CharacterService; точка появления — система спавна игры.
━━━ ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local Core = Shared.Core

local Lifecycle = require(Core.Lifecycle)
local Registry = require(Core.ServiceRegistry)
local EventBus = require(Core.EventBus)
local ServerClock = require(Core.ServerClock)
local Network = require(Shared.Network.Network)
local Validate = require(Shared.Network.Validate)
local DataTypes = require(Shared.Data.DataTypes)
local DataEvents = require(Shared.Data.DataEvents)
local PlayerChannels = require(Shared.Player.PlayerChannels)
local PlayerConfig = require(Shared.Player.PlayerConfig)
local PlayerEvents = require(Shared.Player.PlayerEvents)
local GamePlayer = require(ServerStorage.Server.Player.GamePlayer)

local PlayerService = Lifecycle:extend()
PlayerService.name = "PlayerService"
PlayerService.dependencies = { "DataService" }

function PlayerService:Init()
	self._data = Registry:get("DataService") :: DataTypes.DataService
	self._players = {} :: { [Player]: any }
	self._prepared = {} :: { [Player]: any }
end

function PlayerService:Start()
	self:_bind(EventBus:on(DataEvents.ProfileReloading, function(data: DataEvents.ProfileReloading)
		local gp = self._players[data.player]
		if gp then
			self:_flushPlayTime(gp)
		end
	end))
	self:_bind(EventBus:on(DataEvents.ProfileChanged, function(data: DataEvents.ProfileChanged)
		if data.reason == "data:mode" or data.reason == "admin:wipe" then
			local gp = self._players[data.player]
			if gp then
				gp.playTimeAt = gp:GetSessionTime()
			end
		end
	end))
	Network.setReadyCheck(function(player: Player): boolean
		local gp = self._players[player]
		return gp ~= nil and gp.ready
	end)
	self:_bind(Network.onServerEvent(PlayerChannels.PLAYER_READY, function(player: Player)
		self:_onClientReady(player)
	end, { validate = Validate.empty, beforeReady = true }))
	self:_bind(Players.PlayerAdded:Connect(function(player)
		self:_enter(player)
	end))
	-- вошедшие до старта сервисов (часто в Studio)
	for _, player in ipairs(Players:GetPlayers()) do
		self:_enter(player)
	end
	self:_bind(Players.PlayerRemoving:Connect(function(player)
		self:_leave(player, "leaving")
	end))
	game:BindToClose(function()
		self:PrepareShutdown()
		for player in pairs(self._prepared) do
			self:_releasePrepared(player)
		end
	end)
end

function PlayerService:_enter(player: Player)
	if self._players[player] then
		return
	end
	local gp = GamePlayer:new(player)
	self._players[player] = gp
	gp:Stage("вход")
	-- Загрузка профиля параллельно с загрузкой клиента. Поток НЕ в scope: отменённая посреди
	-- StartSessionAsync загрузка оставит висящую сессию. Ушёл — ProfileStore отменит сам (Cancel в DataService).
	task.spawn(function()
		if not self._data:Load(player) or player.Parent ~= Players or gp:isDestroyed() then
			return
		end
		gp:Stage("профиль")
		local now = math.floor(ServerClock.now())
		self._data:Update(player, function(data)
			local stats = data.Player
			stats.visits += 1
			stats.lastJoin = now
			if stats.firstJoin == 0 then
				stats.firstJoin = now
			end
			return true
		end, "player:join")
		local profile = self._data:Get(player)
		gp.visits = if profile then profile.Player.visits else 1
		gp.firstVisit = gp.visits <= 1
		gp.dataReady = true
		EventBus:emit(
			PlayerEvents.PlayerReady,
			{ player = player, firstVisit = gp.firstVisit, visits = gp.visits } :: PlayerEvents.PlayerReady
		)
		gp:GetGroupRank()
		self:_tryReady(gp)
	end)
	gp.scope:Delay(PlayerConfig.ReadyWarnAfter, function()
		if not gp.ready then
			self._log:Warn("%s: вход затянулся — %s", player.Name, gp:StagesLine())
		end
	end)
end

function PlayerService:_onClientReady(player: Player)
	local gp = self._players[player]
	if not gp or gp.clientReady then
		return
	end
	gp.clientReady = true
	gp:Stage("клиент")
	self:_tryReady(gp)
end

-- Данные есть и клиент слушает → ClientReady (системы шлют стартовое состояние) → ProfileReady.
function PlayerService:_tryReady(gp: any)
	if gp.ready or not gp.dataReady or not gp.clientReady then
		return
	end
	gp.ready = true
	EventBus:emit(PlayerEvents.ClientReady, { player = gp.player } :: PlayerEvents.ClientReady)
	gp.player:SetAttribute(PlayerConfig.Attr.ProfileReady, true)
	gp:Stage("готов")
	self._log:Info(
		"%s: вход · %s · визит %d",
		gp.player.Name,
		gp:StagesLine(),
		gp.visits
	)
end

function PlayerService:PrepareDeparture(player: Player, reason: string): boolean
	if self._prepared[player] then
		return true
	end
	local gp = self._players[player]
	if not gp then
		return false
	end
	self._players[player] = nil
	local sessionTime = gp:GetSessionTime()
	local departure = {
		gp = gp,
		reason = reason,
		sessionTime = sessionTime,
		began = os.clock(),
		ready = false,
		releasing = false,
	}
	self._prepared[player] = departure
	if gp.dataReady then
		-- Доски и аналитика в PlayerLeaving уже видят окончательное время текущего режима.
		self:_flushPlayTime(gp)
		-- обработчики быстрые, без yield; каждый в pcall (EventBus) — упавший не мешает сохранению
		EventBus:emit(
			PlayerEvents.PlayerLeaving,
			{ player = player, sessionTime = sessionTime, reason = reason } :: PlayerEvents.PlayerLeaving
		)
	end
	EventBus:emit(
		PlayerEvents.PlayerLeavingFinished,
		{
			player = player,
			sessionTime = sessionTime,
			reason = reason,
			profileLoaded = gp.dataReady == true,
		} :: PlayerEvents.PlayerLeavingFinished
	)
	departure.ready = true
	return true
end

function PlayerService:PrepareShutdown(): number
	local players = {}
	for player in pairs(self._players) do
		table.insert(players, player)
	end
	for _, player in ipairs(players) do
		self:PrepareDeparture(player, "shutdown")
	end
	return #players
end

function PlayerService:_releasePrepared(player: Player)
	local departure = self._prepared[player]
	if not departure or not departure.ready or departure.releasing then
		return
	end
	departure.releasing = true
	local gp = departure.gp
	local saved = self._data:Release(player, departure.reason)
	local items = gp.scope:Count()
	gp:destroy()
	self._prepared[player] = nil
	self._log:Info(
		"%s: выход (%s) · сессия %.0fс · PlayerLeavingFinished → сохранение %s → scope (%d) · %.0fмс",
		player.Name,
		departure.reason,
		departure.sessionTime,
		if saved then "да" else "нет",
		items,
		(os.clock() - departure.began) * 1000
	)
end

function PlayerService:_leave(player: Player, reason: string)
	self:PrepareDeparture(player, reason)
	self:_releasePrepared(player)
end

-- Только неучтённый отрезок текущего профиля. Полная сессия остаётся для логов/PlayerLeaving.
function PlayerService:_flushPlayTime(gp: any)
	if not gp.dataReady or not self._data:IsLoaded(gp.player) then
		return
	end
	local now = gp:GetSessionTime()
	local seconds = math.floor(math.max(0, now - (gp.playTimeAt or 0)))
	if seconds == 0 then
		return
	end
	local ok = self._data:UpdateFields(gp.player, { "Player" }, function(data)
		data.Player.playTime += seconds
		return true
	end, "player:time")
	if ok then
		gp.playTimeAt = now
	end
end

-- Накопленное время текущего профиля + ещё не записанный онлайн; nosave не переносится в save.
function PlayerService:PlayTime(player: Player): number
	local profile = self._data:Get(player)
	if not profile then
		return 0
	end
	local gp = self._players[player]
	local pending = if gp and gp.dataReady
		then math.max(0, gp:GetSessionTime() - (gp.playTimeAt or 0))
		else 0
	return (profile.Player and profile.Player.playTime or 0) + pending
end

function PlayerService:Get(player: Player): any
	return self._players[player]
end

function PlayerService:GetScope(player: Player): any
	local gp = self._players[player]
	return if gp then gp.scope else nil
end

function PlayerService:IsReady(player: Player): boolean
	local gp = self._players[player]
	return gp ~= nil and gp.ready
end

function PlayerService:Describe(player: Player): string
	local gp = self._players[player]
	if not gp then
		return player.Name .. ": not tracked"
	end
	return string.format(
		"%s: %s · session %.0fs · visit %d%s · rank %d · scope %d",
		player.Name,
		gp:StagesLine(),
		gp:GetSessionTime(),
		gp.visits,
		if gp.firstVisit then " (first)" else "",
		gp:GetGroupRank(),
		gp.scope:Count()
	)
end

function PlayerService:All(): { [Player]: any }
	return self._players
end

return PlayerService
