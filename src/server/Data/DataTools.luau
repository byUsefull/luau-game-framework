--!strict
--[[ ━━━ DataTools · система data · сервер, все плейсы
  Что: тест-режимы и удаление: режим без сохранения (nosave ↔ save), тестовый профиль админа с нуля
    (fresh), вайп своего профиля, удаление данных по UserId (запросы Roblox) с хуками систем.
  Почему так: nosave — честная подмена: живая сессия закрывается с сохранением, дальше игрок играет
    на Mock-сессии с копией данных; save — Mock закрывается, профиль грузится заново из DataStore.
    fresh включается только при входе (DataService:Load): сервисы с первого кадра видят данные нового
    игрока; настоящий профиль при этом не меняется, флаг в нём правит только setFreshFlag.
  Не здесь: обычная запись — DataService:Update; кто вызывает — админ-команды игры.
━━━ ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataConfig = require(ReplicatedStorage.Shared.Data.DataConfig)
local DataOps = require(ReplicatedStorage.Shared.Data.DataOps)
local DataTypes = require(ReplicatedStorage.Shared.Data.DataTypes)
local DataEvents = require(ReplicatedStorage.Shared.Data.DataEvents)
local EventBus = require(ReplicatedStorage.Shared.Core.EventBus)

local DataTools = {}

-- service — сам DataService (помощник без своего состояния).
function DataTools.setMode(service: any, player: Player, mode: DataTypes.Mode): (boolean, string)
	local profile = service._profiles[player]
	if not profile then
		return false, "profile not loaded"
	end
	if profile.mode == "fresh" then
		return false, "fresh test profile is on — turn it off in Settings and rejoin"
	end
	if profile.mode == mode then
		return true, "already " .. mode
	end
	-- Владельцы накопленного в памяти успевают записать старую сессию до копирования и Release.
	EventBus:emit(
		DataEvents.ProfileReloading,
		{
			player = player,
			fromMode = profile.mode,
			toMode = mode,
		} :: DataEvents.ProfileReloading
	)
	local copy = DataOps.deepCopy(profile:data())
	service:Release(player, "mode " .. mode)
	local session = service:_open(player, mode == "nosave")
	if not session then
		return false, "could not open session — rejoin"
	end
	if mode == "nosave" then
		DataOps.replaceContents(session.Data, copy)
		-- Это живая копия прежней сессии, а не данные из прошлого Mock-сохранения.
		session.PreviousSaveTime = nil
	end
	service:_attach(player, session, mode)
	service:_afterWrite(player, DataOps.changedKeys(copy, session.Data), "data:mode", true)
	service:_push(player)
	service._log:Info("%s: режим %s", player.Name, mode)
	return true,
		if mode == "nosave"
			then "nosave: progress from now on is not saved"
			else "save: profile reloaded from DataStore"
end

-- Флаг тестового профиля в настоящих данных (до или после миграций — Settings может не быть).
function DataTools.freshWanted(data: { [string]: any }): boolean
	local settings = data.Settings
	local values = type(settings) == "table" and settings.values
	return type(values) == "table" and values[DataConfig.FreshKey] == true
end

-- Вход с флагом: настоящая сессия закрывается как есть, игрок получает Mock с данными по умолчанию.
function DataTools.openFresh(service: any, player: Player, real: any): any
	real:EndSession()
	local session = service:_open(player, true)
	if not session then
		return nil
	end
	local fresh = DataOps.deepCopy(DataConfig.Default)
	fresh[DataConfig.VersionField] = DataConfig.Version
	fresh.Settings.values[DataConfig.FreshKey] = true
	DataOps.replaceContents(session.Data, fresh)
	service._log:Warn(
		"%s: ТЕСТОВЫЙ профиль — данные с нуля, в DataStore ничего не пишется",
		player.Name
	)
	return session
end

-- Флаг в настоящем профиле. save — обычной записью; nosave / fresh — настоящая сессия на миг, только флаг.
function DataTools.setFreshFlag(service: any, player: Player, on: boolean): boolean
	local profile = service._profiles[player]
	if not profile then
		return false
	end
	local value = if on then true else nil
	if profile.mode == "save" then
		local ok = service:Update(player, function(data)
			data.Settings.values[DataConfig.FreshKey] = value
			return true
		end, "data:fresh")
		return ok and service:SaveAndWait(player, "fresh flag")
	end
	local real = service:_open(player)
	if not real then
		return false
	end
	real:Reconcile()
	real.Data.Settings.values[DataConfig.FreshKey] = value
	real:EndSession()
	service._log:Info(
		"%s: флаг тестового профиля в настоящих данных: %s",
		player.Name,
		tostring(on)
	)
	return true
end

function DataTools.wipe(service: any, player: Player): boolean
	local changed = false
	local ok = service:Update(player, function(data)
		local fresh = DataOps.deepCopy(DataConfig.Default)
		-- Барьер ожидающих SaveAndWait технический: сброс прогресса не должен повторить его номер.
		fresh[DataConfig.SaveRevisionKey] = data[DataConfig.SaveRevisionKey] or 0
		-- Управляющий флаг следующего входа не часть прогресса. В fresh это также копия для UI;
		-- её сброс не меняет настоящую настройку и показывал бы админу неверное Off.
		local settings = data.Settings
		local values = type(settings) == "table" and settings.values
		if type(values) == "table" then
			fresh.Settings.values[DataConfig.FreshKey] = values[DataConfig.FreshKey]
		end
		-- Wipe сбрасывает прогресс, но не историю оплаты и ещё не доставленные внешние эффекты.
		-- Иначе recent чек станет новым, а pending исчезнет даже посреди ожидающего SaveAndWait.
		local purchases = data.Purchases
		if type(purchases) == "table" then
			fresh.Purchases.receipts = purchases.receipts or fresh.Purchases.receipts
			fresh.Purchases.pending = purchases.pending or fresh.Purchases.pending
		end
		fresh[DataConfig.VersionField] = DataConfig.Version
		changed = not DataOps.equal(data, fresh)
		table.clear(data)
		for k, v in pairs(fresh) do
			data[k] = v
		end
		data[DataConfig.VersionField] = DataConfig.Version
		return true
	end, "admin:wipe")
	if ok then
		if not changed then
			service:_afterWrite(player, {}, "admin:wipe", true)
		end
		service:_push(player)
	end
	return ok
end

function DataTools.erase(service: any, userId: number): (boolean, string)
	if Players:GetPlayerByUserId(userId) then
		return false, "player is on this server — kick first"
	end
	local ok, err = pcall(function()
		service._store:RemoveAsync(DataConfig.KeyPrefix .. tostring(userId))
	end)
	if not ok then
		return false, "RemoveAsync failed: " .. tostring(err)
	end
	local failed = {}
	for name, hook in pairs(service._eraseHooks) do
		local hookOk, hookErr = pcall(hook, userId)
		if not hookOk then
			table.insert(failed, name .. ": " .. tostring(hookErr))
		end
	end
	service._log:Info(
		"данные %d удалены, хуков %d, ошибок %d",
		userId,
		#failed,
		#failed
	)
	if #failed > 0 then
		return false, "profile erased, hooks failed: " .. table.concat(failed, "; ")
	end
	return true, "erased profile and system hooks for " .. userId
end

return DataTools
