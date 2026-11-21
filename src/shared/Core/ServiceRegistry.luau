--!strict
--[[ ━━━ ServiceRegistry · система core · общее, все плейсы
  Что: реестр синглтонов стороны: register, get (обязательный), find (необязательный), list.
  Почему так: синглтоны ссылаются друг на друга без циклических require. get возвращает any —
    потребитель приводит к типу из <S>Types: Registry:get("DataService") :: DataTypes.DataService.
  Не здесь: кто и когда регистрирует — Bootstrap; get только внутри Init/Start/методов (правило L09).
━━━ ]]

local Registry = {}

local services: { [string]: any } = {}

function Registry.register(_self: any, name: string, service: any)
	if services[name] ~= nil then
		error(
			string.format(
				"[Registry] '%s' уже зарегистрирован — переименуй файл",
				name
			),
			2
		)
	end
	services[name] = service
end

function Registry.get(_self: any, name: string): any
	local service = services[name]
	if service == nil then
		error(
			string.format(
				"[Registry] нет синглтона '%s' — он в dependencies? есть в этом плейсе?",
				name
			),
			2
		)
	end
	return service
end

function Registry.find(_self: any, name: string): any?
	return services[name]
end

function Registry.list(_self: any): { string }
	local names = {}
	for name in pairs(services) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function Registry.clear(_self: any)
	services = {}
end

return Registry
