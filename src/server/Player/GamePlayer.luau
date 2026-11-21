--!strict
--[[ ━━━ GamePlayer · система player · сервер, все плейсы
  Что: объект игрока на сессию: его PlayerScope, этапы входа, первый вход и число входов, время сессии,
    ранг в группе игры (кеш на вход), сессионное состояние систем.
  Почему так: ранг спрашивают админка, теги чата, награды за группу — один запрос к Roblox на вход, а не по
    запросу в каждой системе; ошибка запроса → ранг 0, игра идёт.
  Не здесь: порядок входа и выхода — PlayerService; сохраняемые данные — DataService.
━━━ ]]

local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Entity = require(ReplicatedStorage.Shared.Core.Entity)
local PlayerConfig = require(ReplicatedStorage.Shared.Player.PlayerConfig)
local PlayerScope = require(ServerStorage.Server.Player.PlayerScope)

local GamePlayer = Entity:extend()
GamePlayer.className = "GamePlayer"

function GamePlayer.init(self: any, player: Player)
	Entity.init(self, { id = "GamePlayer:" .. player.Name })
	self.player = player
	self.scope = PlayerScope:new({ name = player.Name })
	self.joinedAt = os.clock()
	-- Позиция в GetSessionTime до которой playTime уже записан либо начался новый профиль/режим.
	self.playTimeAt = 0
	self.stages = {} :: { { name: string, at: number } }
	self.firstVisit = false
	self.visits = 0
	self.dataReady = false
	self.clientReady = false
	self.ready = false
	self._rank = nil :: number?
	self._state = {} :: { [string]: any }
end

-- Отметка этапа входа: время от входа, мс.
function GamePlayer.Stage(self: any, name: string)
	table.insert(self.stages, { name = name, at = (os.clock() - self.joinedAt) * 1000 })
end

function GamePlayer.StagesLine(self: any): string
	local parts = {}
	for _, stage in ipairs(self.stages) do
		table.insert(parts, string.format("%s %.0fмс", stage.name, stage.at))
	end
	return table.concat(parts, " · ")
end

function GamePlayer.GetSessionTime(self: any): number
	return os.clock() - self.joinedAt
end

function GamePlayer.GetGroupRank(self: any): number
	if self._rank ~= nil then
		return self._rank
	end
	local groupId = PlayerConfig.GroupId
	local rank = 0
	if groupId > 0 then
		local ok, result = pcall(self.player.GetRankInGroup, self.player, groupId)
		rank = if ok and type(result) == "number" then result else 0
		if not ok then
			self._log:Warn(
				"ранг в группе не получен: %s — считаю 0",
				tostring(result)
			)
		end
	end
	self._rank = rank
	self.player:SetAttribute(PlayerConfig.Attr.GroupRank, rank)
	return rank
end

-- Свежий ранг (GetRankInGroup на сервере кэшируется Roblox до конца сессии).
function GamePlayer.RefreshGroupRank(self: any): number
	local groupId = PlayerConfig.GroupId
	if groupId <= 0 then
		return GamePlayer.GetGroupRank(self)
	end
	local ok, groups = pcall(GroupService.GetGroupsAsync, GroupService, self.player.UserId)
	if not ok or type(groups) ~= "table" then
		self._log:Warn("список групп не получен: %s", tostring(groups))
		return GamePlayer.GetGroupRank(self)
	end
	local rank = 0
	for _, group in ipairs(groups) do
		if group.Id == groupId then
			rank = group.Rank
		end
	end
	if self.player.Parent then
		self._rank = rank
		self.player:SetAttribute(PlayerConfig.Attr.GroupRank, rank)
	end
	return rank
end

function GamePlayer.GetState(self: any, key: string): any
	return self._state[key]
end

function GamePlayer.SetState(self: any, key: string, value: any)
	self._state[key] = value
end

function GamePlayer.destroy(self: any)
	self.scope:destroy()
	self._state = {}
	Entity.destroy(self)
end

return GamePlayer
