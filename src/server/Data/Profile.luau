--!strict
--[[ ━━━ Profile · система data · сервер, все плейсы
  Что: данные одного игрока на сессию: сессия ProfileStore, атомарная правка, снимок для клиента,
    запись с ожиданием подтверждения, закрытие, режим без сохранения.
  Почему так: изменения коммитятся только после успешной правки копии (всего профиля либо выбранных
    разделов) — при отказе не меняется ничего. После закрытия правки отклоняются громко.
  Не здесь: вход и выход игрока — PlayerService; хранилище, сообщения, команды — DataService.
━━━ ]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Entity = require(ReplicatedStorage.Shared.Core.Entity)
local DataOps = require(ReplicatedStorage.Shared.Data.DataOps)
local DataConfig = require(ReplicatedStorage.Shared.Data.DataConfig)
local DataTypes = require(ReplicatedStorage.Shared.Data.DataTypes)

export type Profile = {
	player: Player,
	session: any,
	mode: DataTypes.Mode,
	released: boolean,
	failSaves: boolean,
	data: (self: any) -> { [string]: any },
	update: (self: any, fn: DataTypes.Mutator) -> (boolean, string?, { string }?),
	updateFields: (
		self: any,
		fields: { string },
		fn: DataTypes.Mutator
	) -> (boolean, string?, { string }?),
	commit: (self: any, newData: { [string]: any }) -> { string },
	snapshot: (self: any) -> { [string]: any },
	saveAndWait: (self: any, timeout: number) -> boolean,
	release: (self: any) -> boolean,
	size: (self: any) -> number,
	destroy: (self: any) -> (),
}

local Profile = Entity:extend()
Profile.className = "Profile"

function Profile.init(self: any, opts: { player: Player, session: any, mode: DataTypes.Mode? })
	Entity.init(self, { id = "Profile#" .. opts.player.UserId })
	self.player = opts.player
	self.session = opts.session
	self.mode = opts.mode or "save"
	self.released = false
	self.failSaves = false
end

function Profile.data(self: any): { [string]: any }
	return self.session.Data
end

-- Новые данные целиком вместо старых; возвращает изменённые ключи верхнего уровня.
function Profile.commit(self: any, newData: { [string]: any }): { string }
	local live = self.session.Data
	local keys = DataOps.changedKeys(live, newData)
	DataOps.replaceContents(live, newData)
	return keys
end

-- Атомарная правка: (ok, ошибка, изменённые ключи).
function Profile.update(self: any, fn: DataTypes.Mutator): (boolean, string?, { string }?)
	if self.released or not self.session:IsActive() then
		return false, "профиль уже отпущен", nil
	end
	local result = DataOps.applyAtomic(self.session.Data, fn)
	if not result.ok then
		return false, result.error, nil
	end
	return true, nil, Profile.commit(self, result.data)
end

function Profile.snapshot(self: any): { [string]: any }
	return DataOps.snapshot(self.session.Data, DataConfig.Private)
end

-- Все выбранные разделы одной правкой; остальные сохраняют ссылки и не обходятся.
function Profile.updateFields(
	self: any,
	fields: { string },
	fn: DataTypes.Mutator
): (boolean, string?, { string }?)
	if self.released or not self.session:IsActive() then
		return false, "профиль уже отпущен", nil
	end
	local live = self.session.Data
	-- callback может замыкать исходный список; commit использует неизменяемый для него scope.
	local scope = if type(fields) == "table" then table.clone(fields) else fields
	local result = DataOps.applyFieldsAtomic(live, scope, fn)
	if not result.ok then
		return false, result.error, nil
	end
	local keys = {}
	for _, key in ipairs(scope) do
		if not DataOps.equal(live[key], result.data[key]) then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	for _, key in ipairs(keys) do
		live[key] = result.data[key]
	end
	return true, nil, keys
end

-- true — запись дошла до DataStore. В режимах nosave и fresh записывать нечего — true.
function Profile.saveAndWait(self: any, timeout: number): boolean
	if self.failSaves then
		return false
	end
	if self.mode ~= "save" then
		return true
	end
	local session = self.session
	if self.released or not session:IsActive() then
		return false
	end
	-- Барьер входит в тот же снимок, что все предшествующие изменения. Старый autosave,
	-- завершившийся после вызова Save, не содержит этот номер и не подтверждает покупку.
	local key = DataConfig.SaveRevisionKey
	local saved = session.LastSavedData or {}
	local revision = math.max(session.Data[key] or 0, saved[key] or 0) + 1
	session.Data[key] = revision
	local function confirmed(snapshot: any): boolean
		return type(snapshot) == "table"
			and type(snapshot[key]) == "number"
			and snapshot[key] >= revision
	end
	local written = false
	local connection = session.OnAfterSave:Connect(function(snapshot)
		if not self.released and session:IsActive() then
			written = written or confirmed(snapshot)
		end
	end)
	local ok = pcall(session.Save, session)
	if not ok then
		connection:Disconnect()
		return false
	end
	written = written or confirmed(session.LastSavedData)
	local deadline = os.clock() + timeout
	while not written and os.clock() < deadline and session:IsActive() do
		task.wait(0.1)
	end
	connection:Disconnect()
	-- Потерявший lock Save может вернуть снимок нового сервера с таким же номером барьера.
	return not self.released
		and session:IsActive()
		and (written or confirmed(session.LastSavedData))
end

-- Закрыть сессию (ProfileStore сохранит). true — сессия была живой.
function Profile.release(self: any): boolean
	if self.released then
		return false
	end
	self.released = true
	local active = self.session:IsActive()
	self.session:EndSession()
	return active
end

function Profile.size(self: any): number
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, self.session.Data)
	return if ok then #encoded else -1
end

function Profile.destroy(self: any)
	Entity.destroy(self)
end

return Profile
