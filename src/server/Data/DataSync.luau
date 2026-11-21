--!strict
--[[ ━━━ DataSync · система data · сервер, все плейсы
  Что: копия профиля клиенту: снимок после ClientReady, потом только изменённые ключи верхнего уровня.
  Почему так: до ClientReady клиент не слушает — снимок ушёл бы в пустоту; вся таблица на каждую
    правку — лишний трафик. Приватные поля (DataConfig.Private) не уходят никогда.
  Не здесь: приём на клиенте — DataController.
━━━ ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage.Shared.Network.Network)
local DataChannels = require(ReplicatedStorage.Shared.Data.DataChannels)
local DataConfig = require(ReplicatedStorage.Shared.Data.DataConfig)
local DataOps = require(ReplicatedStorage.Shared.Data.DataOps)

local DataSync = {}

-- Клиенту: снимок после ClientReady, дальше только изменения.
function DataSync.push(service: any, player: Player)
	local profile = service._profiles[player]
	if profile and service._clientReady[player] then
		Network.fireClient(
			DataChannels.DATA_SNAPSHOT,
			player,
			{ data = profile:snapshot() } :: DataChannels.Snapshot
		)
	end
end

function DataSync.pushKeys(service: any, player: Player, keys: { string }, reason: string)
	local profile = service._profiles[player]
	if not profile or not service._clientReady[player] then
		return
	end
	local values, removed = {}, {}
	local data = profile:data()
	for _, key in ipairs(keys) do
		if not DataConfig.Private[key] then
			if data[key] == nil then
				table.insert(removed, key)
			else
				values[key] = DataOps.deepCopy(data[key])
			end
		end
	end
	if next(values) or #removed > 0 then
		Network.fireClient(
			DataChannels.DATA_CHANGED,
			player,
			{ values = values, removed = removed, reason = reason } :: DataChannels.Changed
		)
	end
end

return DataSync
