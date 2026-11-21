--!strict
--[[ ━━━ DataService · система data · сервер, все плейсы
  Что: обёртка ProfileStore: Load, Get, Update/UpdateFields, UpdatePair, SaveAndWait, Release, сообщения в профиль,
    снимок и изменения клиенту, режимы теста (nosave, fresh, wipe), удаление данных по UserId.
  Почему так: ProfileStore даёт блокировку сессии, автосейв и досохранение при закрытии сервера.
    Запись только через Update — атомарно на копии; клиент получает снимок после ClientReady, дальше
    только изменённые ключи. Порядок выхода ведёт player: он зовёт Release после PlayerLeaving;
    data отпускает сам только как страховка (DataConfig.ReleaseFallback).
  Не здесь: когда грузить и отпускать — PlayerService; сессия одного игрока — Profile;
    открытие сессий и сообщения — DataSessions; клиенту — DataSync; режимы и удаление — DataTools.
━━━ ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local Core = Shared.Core

local Lifecycle = require(Core.Lifecycle)
local EventBus = require(Core.EventBus)
local DataConfig = require(Shared.Data.DataConfig)
local DataEvents = require(Shared.Data.DataEvents)
local DataMigrations = require(Shared.Data.DataMigrations)
local DataOps = require(Shared.Data.DataOps)
local DataTypes = require(Shared.Data.DataTypes)
local PlayerEvents = require(Shared.Player.PlayerEvents)
local DataFolder = ServerStorage.Server.Data
local Profile = require(DataFolder.Profile)
local DataTools = require(DataFolder.DataTools)
local DataSessions = require(DataFolder.DataSessions)
local DataSync = require(DataFolder.DataSync)
local ProfileStore = require(DataFolder.Packages.ProfileStore)

local DataService = Lifecycle:extend()
DataService.name = "DataService"
DataService.dependencies = {}

function DataService:Init()
	self._profiles = {} :: { [Player]: Profile.Profile }
	self._loading = {} :: { [Player]: boolean }
	self._clientReady = {} :: { [Player]: boolean }
	self._handlers = {} :: { [string]: (Player, { [string]: any }) -> boolean }
	self._eraseHooks = {} :: { [string]: (number) -> () }
	self._saveTransforms = {} :: { [string]: DataTypes.SaveTransform }
	self._loadTransforms = {} :: { [string]: DataTypes.LoadTransform }
	local name = DataConfig.StoreName
		.. (if RunService:IsStudio() then DataConfig.StudioStoreSuffix else "")
	self._store = ProfileStore.New(name, DataConfig.Default)
end

function DataService:Start()
	self:_spawn(function()
		while ProfileStore.DataStoreState == "NotReady" do
			task.wait(0.1)
		end
		if ProfileStore.DataStoreState == "Access" then
			self._log:Info(
				"хранилище доступно: профили сохраняются"
			)
		else
			self._log:Critical(
				"СОХРАНЕНИЙ НЕТ (%s): профили в памяти. Studio: Game Settings → Security → API Services",
				tostring(ProfileStore.DataStoreState)
			)
		end
	end)
	self:_bind(EventBus:on(PlayerEvents.ClientReady, function(data: PlayerEvents.ClientReady)
		self._clientReady[data.player] = true
		self:_push(data.player)
	end))
	self:_bind(Players.PlayerRemoving:Connect(function(player)
		self._clientReady[player] = nil
		-- страховка: player отпускает профиль сам после PlayerLeaving; не отпустил — отпускаем мы
		task.delay(DataConfig.ReleaseFallback, function()
			if self._profiles[player] then
				self._log:Critical(
					"%s: профиль не отпущен через %dс после выхода — отпускаю",
					player.Name,
					DataConfig.ReleaseFallback
				)
				self:Release(player, "fallback")
			end
		end)
	end))
end

function DataService:_key(userId: number): string
	return DataConfig.KeyPrefix .. tostring(userId)
end

function DataService:Load(player: Player): boolean
	if self._profiles[player] then
		return true
	end
	if self._loading[player] then
		return false
	end
	self._loading[player] = true
	local began = os.clock()
	local session = self:_open(player)
	local mode: DataTypes.Mode = "save"
	if session and DataTools.freshWanted(session.Data) then
		-- тестовый профиль админа: настоящий не трогаем, играем с нуля без записи
		session = DataTools.openFresh(self, player, session)
		mode = "fresh"
	end
	self._loading[player] = nil
	if not session then
		if player.Parent == Players then
			self._log:Critical("%s: профиль не загружен", player.Name)
			if DataConfig.KickOnLoadFail then
				player:Kick(DataConfig.Text.LoadFailed)
			end
		end
		return false
	end
	self:_attach(player, session, mode)
	local data = session.Data
	local version, migrated = DataMigrations.run(data, DataConfig.VersionField, DataConfig.Version)
	session:Reconcile()
	self._log:Info(
		"%s: профиль за %dмс, схема v%d",
		player.Name,
		math.floor((os.clock() - began) * 1000),
		version
	)
	EventBus:emit(
		DataEvents.ProfileLoaded,
		{ player = player, version = version, migrated = migrated } :: DataEvents.ProfileLoaded
	)
	return true
end

function DataService:IsLoaded(player: Player): boolean
	local profile = self._profiles[player]
	return profile ~= nil and not profile.released
end

function DataService:Get(player: Player): { [string]: any }?
	local profile = self._profiles[player]
	return if profile and not profile.released then profile:data() else nil
end

function DataService:_afterWrite(
	player: Player,
	keys: { string },
	reason: string,
	forceEvent: boolean?
)
	if #keys == 0 and not forceEvent then
		return
	end
	EventBus:emit(
		DataEvents.ProfileChanged,
		{ player = player, keys = keys, reason = reason } :: DataEvents.ProfileChanged
	)
	if #keys > 0 then
		self:_pushKeys(player, keys, reason)
	end
end

function DataService:Update(
	player: Player,
	fn: DataTypes.Mutator,
	reason: string
): (boolean, string?)
	local profile = self._profiles[player]
	if not profile then
		self._log:Warn(
			"Update без профиля (%s, %s) — правка отклонена",
			player.Name,
			reason
		)
		return false, "NotLoaded"
	end
	local ok, err, keys = profile:update(fn)
	if not ok then
		if err ~= "отказ" then
			self._log:Warn(
				"%s: Update «%s» отменён: %s",
				player.Name,
				reason,
				tostring(err)
			)
		end
		return false, err
	end
	self:_afterWrite(player, keys :: { string }, reason)
	return true, nil
end

function DataService:UpdatePair(
	a: Player,
	b: Player,
	fn: (any, any) -> boolean?,
	reason: string
): (boolean, string?)
	local pa, pb = self._profiles[a], self._profiles[b]
	if not pa or not pb or pa.released or pb.released or a == b then
		return false, "NotLoaded"
	end
	local first, second = DataOps.applyPair(pa:data(), pb:data(), fn)
	if not first.ok or not second then
		self._log:Warn("UpdatePair «%s» отменён: %s", reason, tostring(first.error))
		return false, first.error
	end
	local keysA = pa:commit(first.data)
	local keysB = pb:commit(second.data)
	self:_afterWrite(a, keysA, reason)
	self:_afterWrite(b, keysB, reason)
	return true, nil
end

-- У частых правок стоимость зависит от выбранных разделов, а не размера инвентаря/журнала покупок.
function DataService:UpdateFields(
	player: Player,
	fields: { string },
	fn: DataTypes.Mutator,
	reason: string
): (boolean, string?)
	local profile = self._profiles[player]
	if not profile then
		return false, "NotLoaded"
	end
	local ok, err, keys = profile:updateFields(fields, fn)
	if not ok then
		if err ~= "отказ" then
			self._log:Warn(
				"%s: UpdateFields «%s» отменён: %s",
				player.Name,
				reason,
				tostring(err)
			)
		end
		return false, err
	end
	self:_afterWrite(player, keys :: { string }, reason)
	return true, nil
end

function DataService:SaveAndWait(player: Player, reason: string): boolean
	local profile = self._profiles[player]
	if not profile or profile.released then
		return false
	end
	local ok = profile:saveAndWait(DataConfig.SaveConfirmTimeout)
	if ok then
		self._log:Info("%s: запись подтверждена (%s)", player.Name, reason)
	else
		self._log:Critical(
			"%s: запись НЕ подтверждена (%s)",
			player.Name,
			reason
		)
	end
	return ok
end

function DataService:Release(player: Player, reason: string): boolean
	local profile = self._profiles[player]
	if not profile then
		return false
	end
	self._profiles[player] = nil
	local size = profile:size()
	local saved = profile:release() and profile.mode == "save"
	if size > DataConfig.SizeWarnBytes then
		self._log:Warn(
			"%s: профиль %d байт — близко к лимиту 4 МБ",
			player.Name,
			size
		)
	end
	self._log:Info(
		"%s: профиль отпущен (%s), сохранён: %s",
		player.Name,
		reason,
		tostring(saved)
	)
	EventBus:emit(
		DataEvents.ProfileReleased,
		{ player = player, saved = saved, reason = reason } :: DataEvents.ProfileReleased
	)
	profile:destroy()
	return saved
end

function DataService:SendMessage(userId: number, message: { [string]: any }): boolean
	local ok, err = pcall(function()
		self._store:MessageAsync(self:_key(userId), message)
	end)
	if not ok then
		self._log:Critical(
			"сообщение в профиль %d не ушло: %s",
			userId,
			tostring(err)
		)
	end
	return ok
end

function DataService:OnMessage(kind: string, fn: (Player, { [string]: any }) -> boolean)
	assert(
		self._handlers[kind] == nil,
		"DataService:OnMessage — вид уже занят: " .. kind
	)
	self._handlers[kind] = fn
end

-- Регистрация в Init: сохраняемый снимок и открываемая сессия имеют разные представления данных.
function DataService:RegisterSaveTransform(name: string, fn: DataTypes.SaveTransform)
	assert(self._saveTransforms[name] == nil, "SaveTransform уже занят: " .. name)
	self._saveTransforms[name] = fn
end

function DataService:RegisterLoadTransform(name: string, fn: DataTypes.LoadTransform)
	assert(self._loadTransforms[name] == nil, "LoadTransform уже занят: " .. name)
	self._loadTransforms[name] = fn
end

-- Сессии и сообщения — DataSessions; клиенту — DataSync (тот же сервис как self).
function DataService:_open(player: Player, mock: boolean?): any
	return DataSessions.open(self, player, mock)
end

function DataService:_attach(player: Player, session: any, mode: DataTypes.Mode): any
	return DataSessions.attach(self, player, session, mode)
end

function DataService:_push(player: Player)
	DataSync.push(self, player)
end

function DataService:_pushKeys(player: Player, keys: { string }, reason: string)
	DataSync.pushKeys(self, player, keys, reason)
end

-- Режимы теста, вайп, удаление, размер — в DataTools (тот же сервис как self).
function DataService:RegisterEraseHook(name: string, fn: (number) -> ())
	self._eraseHooks[name] = fn
end

function DataService:Erase(userId: number): (boolean, string)
	return DataTools.erase(self, userId)
end

function DataService:GetMode(player: Player): DataTypes.Mode
	local profile = self._profiles[player]
	return if profile then profile.mode else "save"
end

function DataService:SetMode(player: Player, mode: DataTypes.Mode): (boolean, string)
	return DataTools.setMode(self, player, mode)
end

function DataService:SetFreshFlag(player: Player, on: boolean): boolean
	return DataTools.setFreshFlag(self, player, on)
end

function DataService:Wipe(player: Player): boolean
	return DataTools.wipe(self, player)
end

function DataService:SizeOf(player: Player): number
	local profile = self._profiles[player]
	return if profile then profile:size() else -1
end

function DataService:SetSaveFailure(player: Player, on: boolean)
	local profile = self._profiles[player]
	if profile then
		profile.failSaves = on
	end
end

return DataService
