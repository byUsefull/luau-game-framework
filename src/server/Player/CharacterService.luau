--!strict
--[[ ━━━ CharacterService · система player · сервер, все плейсы
  Что: единственный, кто грузит персонажа: при входе (PlayerReady) и по запросу; ставит на точку
    системы спавна; ждёт Humanoid, корень и Animator → CharacterReady; возрождает после смерти.
  Почему так: CharacterAutoLoads выключен — персонаж не появляется дважды и не там. Связи персонажа
    живут в его отдельном scope и убираются при смерти и новом персонаже — без дублей на 20 респавнов.
    Насколько тело персонажа больше обычного (Reach) — от поставщика (например, система роста тела): к этому
    запасу прибавляют свои дистанции «от корня до точки» промпты, звуки, эффекты, точки появления.
  Не здесь: где появляться — система спавна через SetSpawnProvider; когда возрождать — health
    через SetRespawnPolicy (без него — PlayerConfig.RespawnDelay); скорость и прыжок — stats.
━━━ ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage.Shared
local Core = Shared.Core

local Lifecycle = require(Core.Lifecycle)
local Registry = require(Core.ServiceRegistry)
local EventBus = require(Core.EventBus)
local PlayerConfig = require(Shared.Player.PlayerConfig)
local PlayerEvents = require(Shared.Player.PlayerEvents)
local PlayerTypes = require(Shared.Player.PlayerTypes)
local PlayerScope = require(ServerStorage.Server.Player.PlayerScope)

local CharacterService = Lifecycle:extend()
CharacterService.name = "CharacterService"
CharacterService.dependencies = { "PlayerService" }

function CharacterService:Init()
	self._players = Registry:get("PlayerService") :: PlayerTypes.PlayerService
	self._spawnProvider = nil :: ((Player) -> CFrame?)?
	self._respawnPolicy = nil :: ((Player) -> number?)?
	self._reach = nil :: ((Player) -> number)?
end

function CharacterService:Start()
	Players.CharacterAutoLoads = false
	self:_bind(EventBus:on(PlayerEvents.PlayerReady, function(data: PlayerEvents.PlayerReady)
		local scope = self._players:GetScope(data.player)
		if not scope then
			return
		end
		local gp = self._players:Get(data.player) :: any
		gp:SetState("character.respawns", 0)
		-- scope персонажа живёт отдельно (не копится в scope игрока); на выходе убирается текущий
		scope:Add(function()
			local current = gp:GetState("character.scope")
			if current then
				current:destroy()
			end
		end)
		scope:Add(data.player.CharacterAdded:Connect(function(character)
			self:_onCharacter(data.player, character)
		end))
		self:Spawn(data.player)
	end))
end

function CharacterService:SetSpawnProvider(fn: (Player) -> CFrame?)
	self._spawnProvider = fn
end

function CharacterService:SetRespawnPolicy(fn: (Player) -> number?)
	self._respawnPolicy = fn
end

-- Насколько тело больше обычного, studs: регистрирует игровая система (например, рост тела). nil — снять.
function CharacterService:SetReachProvider(fn: ((Player) -> number)?)
	self._reach = fn
end

-- Запас тела игрока к дистанциям от корня (большое тело: корень высоко над землёй). Обычное тело — 0.
function CharacterService:Reach(player: Player): number
	local fn = self._reach
	local value = if fn then fn(player) else 0
	return if type(value) == "number" and value == value and value > 0 then value else 0
end

function CharacterService:Spawn(player: Player)
	local scope = self._players:GetScope(player)
	if not scope then
		return
	end
	scope:Spawn(function()
		-- LoadCharacterAsync — текущий API; LoadCharacter Roblox пометил устаревшим
		local ok, err = pcall(function()
			(player :: any):LoadCharacterAsync()
		end)
		if not ok then
			self._log:Warn("%s: LoadCharacterAsync упал: %s", player.Name, tostring(err))
		end
	end)
end

function CharacterService:GetCharacterScope(player: Player): any
	local gp = self._players:Get(player) :: any
	return gp and gp:GetState("character.scope")
end

function CharacterService:Respawns(player: Player): number
	local gp = self._players:Get(player) :: any
	return gp and gp:GetState("character.respawns") or 0
end

-- Новый персонаж: свой scope (старый убирается), ждём части, ставим на точку, CharacterReady.
function CharacterService:_onCharacter(player: Player, character: Model)
	local gp = self._players:Get(player) :: any
	if not gp then
		return
	end
	local old = gp:GetState("character.scope")
	if old then
		old:destroy()
	end
	local charScope = PlayerScope:new({ name = player.Name .. ":character" })
	gp:SetState("character.scope", charScope)
	charScope:Spawn(function()
		local timeout = PlayerConfig.CharacterPartsTimeout
		local deadline = os.clock() + timeout
		local humanoid = character:WaitForChild("Humanoid", timeout) :: Humanoid?
		local root = character:WaitForChild("HumanoidRootPart", timeout) :: BasePart?
		local animator = humanoid and humanoid:WaitForChild("Animator", timeout)
		-- CharacterAdded бывает раньше, чем персонаж попал в Workspace (детали уже есть, родителя нет):
		-- ждём, пока он появится в мире, а не считаем его пропавшим
		while character.Parent == nil and player.Character == character and os.clock() < deadline do
			task.wait()
		end
		if not humanoid or not root or not animator or character.Parent == nil then
			self._log:Warn(
				"%s: персонаж без Humanoid / корня / Animator за %dс",
				player.Name,
				timeout
			)
			return
		end
		local spawnAt = self._spawnProvider and self._spawnProvider(player)
		if spawnAt then
			character:PivotTo(spawnAt)
		end
		gp:SetState("character.respawns", (gp:GetState("character.respawns") or 0) + 1)
		charScope:Add(humanoid.Died:Connect(function()
			self:_onDied(player, character)
		end))
		EventBus:emit(
			PlayerEvents.CharacterReady,
			{ player = player, character = character, humanoid = humanoid, root = root } :: PlayerEvents.CharacterReady
		)
	end)
end

function CharacterService:_onDied(player: Player, character: Model)
	local gp = self._players:Get(player) :: any
	if not gp then
		return
	end
	local delay: number? = PlayerConfig.RespawnDelay
	if self._respawnPolicy then
		delay = self._respawnPolicy(player)
	end
	if delay == nil then
		return
	end
	gp.scope:Delay(delay, function()
		if player.Character == character or player.Character == nil then
			self:Spawn(player)
		end
	end)
end

return CharacterService
