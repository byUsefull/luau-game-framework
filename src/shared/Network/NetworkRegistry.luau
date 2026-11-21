--!strict
--[[ ━━━ NetworkRegistry · система network · общее, все плейсы
  Что: сверяет объявления каналов из всех <S>Channels: ключ = значение, UPPER_SNAKE с префиксом системы,
    kind / direction / note в Spec, без дублей между системами. Возвращает карту каналов и ошибки.
  Почему так: чистые функции без Roblox API и без require — их проверяет lune
    (tests/network_registry.spec.luau). Ошибка объявления видна при старте, а не по таймауту у игрока.
  Не здесь: сбор модулей из дерева и создание remotes — Network.start.
━━━ ]]

export type Kind = "Event" | "Unreliable" | "Function"
export type Direction = "ClientToServer" | "ServerToClient" | "Both"

export type Spec = {
	kind: Kind,
	direction: Direction,
	rate: number?,
	note: string,
}

export type Channel = {
	name: string,
	system: string,
	kind: Kind,
	direction: Direction,
	rate: number,
	note: string,
}

local KINDS = { Event = true, Unreliable = true, Function = true }
local DIRECTIONS = { ClientToServer = true, ServerToClient = true, Both = true }

local NetworkRegistry = {}

NetworkRegistry.DEFAULT_RATE = 0.05

-- «SocialRewards» → «SOCIAL_REWARDS_»
function NetworkRegistry.prefixOf(systemFolder: string): string
	local snake = string.gsub(systemFolder, "(%l)(%u)", "%1_%2")
	return string.upper(snake) .. "_"
end

-- modules: [имя модуля <S>Channels] = таблица модуля. Возвращает каналы по имени и список ошибок.
function NetworkRegistry.collect(modules: { [string]: any }): ({ [string]: Channel }, { string })
	local channels: { [string]: Channel } = {}
	local errors: { string } = {}
	local moduleNames = {}
	for moduleName in pairs(modules) do
		table.insert(moduleNames, moduleName)
	end
	table.sort(moduleNames)
	for _, moduleName in ipairs(moduleNames) do
		local module = modules[moduleName]
		local system = string.gsub(moduleName, "Channels$", "")
		local prefix = NetworkRegistry.prefixOf(system)
		if type(module) ~= "table" then
			table.insert(
				errors,
				string.format("%s: модуль вернул не таблицу", moduleName)
			)
			continue
		end
		local spec = module.Spec
		if type(spec) ~= "table" then
			table.insert(errors, string.format("%s: нет таблицы Spec", moduleName))
			continue
		end
		for key, value in pairs(module) do
			if key == "Spec" then
				continue
			end
			if type(key) ~= "string" or key ~= value then
				table.insert(
					errors,
					string.format("%s.%s: ключ ≠ значение", moduleName, tostring(key))
				)
				continue
			end
			if
				not string.match(key, "^[A-Z][A-Z0-9_]*$")
				or string.sub(key, 1, #prefix) ~= prefix
			then
				table.insert(
					errors,
					string.format(
						"%s.%s: имя UPPER_SNAKE с префиксом %s",
						moduleName,
						key,
						prefix
					)
				)
			end
			local entry = spec[key]
			if type(entry) ~= "table" then
				table.insert(
					errors,
					string.format("%s.%s: нет записи в Spec", moduleName, key)
				)
				continue
			end
			if not KINDS[entry.kind] then
				table.insert(
					errors,
					string.format("%s.%s: kind — Event | Unreliable | Function", moduleName, key)
				)
			end
			if not DIRECTIONS[entry.direction] then
				table.insert(
					errors,
					string.format(
						"%s.%s: direction — ClientToServer | ServerToClient | Both",
						moduleName,
						key
					)
				)
			end
			if type(entry.note) ~= "string" or entry.note == "" then
				table.insert(
					errors,
					string.format("%s.%s: нет note — зачем канал", moduleName, key)
				)
			end
			if
				entry.rate ~= nil
				and (type(entry.rate) ~= "number" or entry.rate ~= entry.rate or entry.rate < 0)
			then
				table.insert(
					errors,
					string.format("%s.%s: rate — число секунд ≥ 0", moduleName, key)
				)
			end
			if entry.kind == "Function" and entry.direction ~= "ClientToServer" then
				table.insert(
					errors,
					string.format(
						"%s.%s: Function только ClientToServer (InvokeClient запрещён)",
						moduleName,
						key
					)
				)
			end
			if channels[key] then
				table.insert(
					errors,
					string.format(
						"%s.%s: канал уже объявлен в %sChannels",
						moduleName,
						key,
						channels[key].system
					)
				)
				continue
			end
			channels[key] = {
				name = key,
				system = system,
				kind = entry.kind,
				direction = entry.direction,
				rate = if type(entry.rate) == "number"
					then entry.rate
					else NetworkRegistry.DEFAULT_RATE,
				note = tostring(entry.note),
			}
		end
		for key in pairs(spec) do
			if module[key] == nil then
				table.insert(
					errors,
					string.format(
						"%s.Spec[%s]: канала нет в таблице модуля",
						moduleName,
						tostring(key)
					)
				)
			end
		end
	end
	return channels, errors
end

-- Можно ли слать по каналу в эту сторону. want = "ClientToServer" | "ServerToClient".
function NetworkRegistry.allows(channel: Channel, want: Direction): boolean
	return channel.direction == want or channel.direction == "Both"
end

return NetworkRegistry
