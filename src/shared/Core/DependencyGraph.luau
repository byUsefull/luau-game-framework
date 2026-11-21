--!strict
--[[ ━━━ DependencyGraph · система core · общее, все плейсы
  Что: топологическая сортировка по dependencies: порядок «зависимость → потребитель», циклы, пропавшие.
  Почему так: чистые функции без Roblox API и без require — их проверяет lune (tests/core_dependency_graph.spec.luau).
  Не здесь: запуск фаз и отчёт — ModuleLoader.
━━━ ]]

export type Entry = { name: string, deps: { string } }
export type Issue = { kind: "missing" | "cycle", message: string }

local VISITING = 1
local DONE = 2

local DependencyGraph = {}

-- entries — вершины в любом порядке. Возвращает порядок загрузки и проблемы [имя] = Issue.
-- Вершина с проблемой всё равно в списке: решение, грузить ли её, — за ModuleLoader.
function DependencyGraph.sort(entries: { Entry }): ({ Entry }, { [string]: Issue })
	local byName: { [string]: Entry } = {}
	for _, entry in ipairs(entries) do
		byName[entry.name] = entry
	end
	local sorted: { Entry } = {}
	local state: { [string]: number } = {}
	local stack: { Entry } = {}
	local stackIndex: { [string]: number } = {}
	local issues: { [string]: Issue } = {}

	local function setIssue(entry: Entry, kind: "missing" | "cycle", message: string)
		if not issues[entry.name] then
			issues[entry.name] = { kind = kind, message = message }
		end
	end

	local visit: (Entry) -> ()
	visit = function(entry: Entry)
		local current = state[entry.name]
		if current == DONE then
			return
		end
		if current == VISITING then
			-- помечаем всю петлю: одно имя не объясняет, где разрывать
			local first = stackIndex[entry.name] or 1
			local names = {}
			for i = first, #stack do
				table.insert(names, stack[i].name)
			end
			table.insert(names, entry.name)
			local message = "цикл зависимостей: " .. table.concat(names, " → ")
			for i = first, #stack do
				setIssue(stack[i], "cycle", message)
			end
			return
		end
		state[entry.name] = VISITING
		table.insert(stack, entry)
		stackIndex[entry.name] = #stack
		for _, depName in ipairs(entry.deps) do
			local dep = byName[depName]
			if dep then
				visit(dep)
			else
				setIssue(
					entry,
					"missing",
					string.format(
						"зависимость '%s' не найдена в этом плейсе",
						depName
					)
				)
			end
		end
		stackIndex[entry.name] = nil
		table.remove(stack)
		state[entry.name] = DONE
		table.insert(sorted, entry)
	end

	for _, entry in ipairs(entries) do
		visit(entry)
	end
	return sorted, issues
end

return DependencyGraph
