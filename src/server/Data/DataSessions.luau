--!strict
--[[ ━━━ DataSessions · система data · сервер, все плейсы
  Что: открытие сессии ProfileStore (обычной или Mock) с отменой при уходе игрока; профиль на сессию:
    потеря замка → кик, сообщения в профиль → обработчики видов (DataService:OnMessage).
  Почему так: «профиль увели на другой сервер» узнаётся только здесь — играть дальше без сохранения нельзя.
    Сообщение помечается обработанным, только если обработчик вернул true (выдача и отметка — одна запись).
  Не здесь: правки и сохранение — DataService и Profile.
━━━ ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DataConfig = require(ReplicatedStorage.Shared.Data.DataConfig)
local DataOps = require(ReplicatedStorage.Shared.Data.DataOps)
local DataTypes = require(ReplicatedStorage.Shared.Data.DataTypes)
local ServerClock = require(ReplicatedStorage.Shared.Core.ServerClock)
local Profile = require(ServerStorage.Server.Data.Profile)

local DataSessions = {}

local function transform(hooks: { [string]: any }, snapshot: any, at: number, previous: number?)
	local names = {}
	for name in pairs(hooks) do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in ipairs(names) do
		hooks[name](snapshot, at, previous)
	end
end

-- Открыть сессию (store — обычный или Mock). nil — не вышло или игрок ушёл.
function DataSessions.open(service: any, player: Player, mock: boolean?): any
	local store = if mock then service._store.Mock else service._store
	local session = store:StartSessionAsync(DataConfig.KeyPrefix .. tostring(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if not session then
		return nil
	end
	if player.Parent ~= Players then
		session:EndSession()
		return nil
	end
	session:AddUserId(player.UserId)
	return session
end

-- Профиль на сессию: потеря замка → кик; сообщения → обработчики видов.
function DataSessions.attach(service: any, player: Player, session: any, mode: DataTypes.Mode)
	-- Сначала превратить сохранённое представление в живое. Это нужно и после /data mode save.
	local result = DataOps.applyAtomic(session.Data, function(copy)
		transform(service._loadTransforms, copy, ServerClock.now(), session.PreviousSaveTime)
	end)
	if not result.ok then
		session:EndSession()
		error("LoadTransform: " .. tostring(result.error))
	end
	DataOps.replaceContents(session.Data, result.data)
	-- Локальный opt-in адаптер ProfileStore: вызывается внутри UpdateAsync на отдельной копии.
	-- Исключение/yield отменяет запись в библиотеке и попадает в ProfileStore.OnError.
	session.SaveTransform = function(snapshot)
		transform(service._saveTransforms, snapshot, ServerClock.now(), nil)
		local safe, path = DataOps.jsonSafe(snapshot)
		assert(safe, "SaveTransform: не JSON-совместимое значение: " .. path)
	end
	local profile = Profile:new({ player = player, session = session, mode = mode })
	service._profiles[player] = profile
	session.OnSessionEnd:Connect(function()
		if profile.released then
			return
		end
		profile.released = true
		if service._profiles[player] == profile then
			service._profiles[player] = nil
		end
		service._log:Critical(
			"%s: замок сессии потерян — профиль открыт на другом сервере",
			player.Name
		)
		if DataConfig.KickOnLockLost and player.Parent == Players then
			player:Kick(DataConfig.Text.LockLost)
		end
	end)
	session:MessageHandler(function(message, processed)
		local handler = type(message) == "table" and service._handlers[message.kind]
		if not handler then
			service._log:Warn(
				"%s: сообщение без обработчика (%s)",
				player.Name,
				tostring(type(message) == "table" and message.kind)
			)
			return
		end
		local ok, done = pcall(handler, player, message)
		if ok and done then
			processed()
		elseif not ok then
			service._log:Critical(
				"%s: обработчик сообщения %s упал: %s",
				player.Name,
				tostring(message.kind),
				tostring(done)
			)
		end
	end)
	return profile
end

return DataSessions
