--!strict
--[[ ━━━ Tags · система core · общее, все плейсы
  Что: единственный вход в CollectionService: all, inWorkspace, one, has, add, remove, watch.
  Почему так: watch сначала проходит по уже помеченным, потом подписывается — наивная подписка
    пропускает размеченное до старта сервиса. inWorkspace отсекает шаблоны в хранилищах.
  Не здесь: имена тегов — в Tag конфига своей системы (ZoneConfig.Tag.Zone …).
━━━ ]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Logger = require(script.Parent.Logger)

local log = Logger.new("Tags")

export type Watcher = { Disconnect: (any) -> () }

local Tags = {}

function Tags.all(tag: string): { Instance }
	return CollectionService:GetTagged(tag)
end

-- Только то, что стоит в мире.
function Tags.inWorkspace(tag: string): { Instance }
	local result = {}
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsDescendantOf(Workspace) then
			table.insert(result, instance)
		end
	end
	return result
end

-- Ровно один объект с тегом, иначе ошибка.
function Tags.one(tag: string): Instance
	local tagged = CollectionService:GetTagged(tag)
	if #tagged ~= 1 then
		error(
			string.format(
				"[Tags] ожидался ровно один объект с тегом '%s', найдено %d",
				tag,
				#tagged
			),
			2
		)
	end
	return tagged[1]
end

function Tags.has(instance: Instance, tag: string): boolean
	return CollectionService:HasTag(instance, tag)
end

function Tags.add(instance: Instance, tag: string)
	CollectionService:AddTag(instance, tag)
end

function Tags.remove(instance: Instance, tag: string)
	CollectionService:RemoveTag(instance, tag)
end

-- Подписка с догоном уже помеченных. onAdded по существующим — в pcall.
function Tags.watch(tag: string, onAdded: (Instance) -> (), onRemoved: ((Instance) -> ())?): Watcher
	local connections: { RBXScriptConnection } = {}
	table.insert(connections, CollectionService:GetInstanceAddedSignal(tag):Connect(onAdded))
	if onRemoved then
		table.insert(
			connections,
			CollectionService:GetInstanceRemovedSignal(tag):Connect(onRemoved)
		)
	end
	for _, instance in CollectionService:GetTagged(tag) do
		local ok, err = pcall(onAdded, instance)
		if not ok then
			log:Critical(
				"onAdded упал · %s · %s · %s",
				tag,
				instance:GetFullName(),
				tostring(err)
			)
		end
	end
	return {
		Disconnect = function()
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
			table.clear(connections)
		end,
	}
end

return Tags
