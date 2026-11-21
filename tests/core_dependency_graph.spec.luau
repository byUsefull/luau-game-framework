--!strict
-- DependencyGraph · система core · lune-тест. Запуск из папки игры: lune run tests/core_dependency_graph.spec

local DependencyGraph = require("../src/shared/Core/DependencyGraph")
local T = require("./TestKit")

local function names(list: { DependencyGraph.Entry }): string
	local out = {}
	for _, entry in ipairs(list) do
		table.insert(out, entry.name)
	end
	return table.concat(out, ",")
end

local function index(list: { DependencyGraph.Entry }, name: string): number
	for i, entry in ipairs(list) do
		if entry.name == name then
			return i
		end
	end
	return -1
end

do
	local sorted, issues = DependencyGraph.sort({
		{ name = "PlayerService", deps = { "DataService" } },
		{ name = "DataService", deps = {} },
		{ name = "CurrencyService", deps = { "DataService", "PlayerService" } },
	})
	T.check(
		"зависимость раньше потребителя",
		index(sorted, "DataService") < index(sorted, "PlayerService"),
		names(sorted)
	)
	T.check(
		"цепочка из трёх",
		index(sorted, "PlayerService") < index(sorted, "CurrencyService"),
		names(sorted)
	)
	T.check("без проблем", next(issues) == nil)
end

do
	local sorted, issues = DependencyGraph.sort({
		{ name = "A", deps = { "B" } },
		{ name = "B", deps = { "C" } },
		{ name = "C", deps = { "A" } },
		{ name = "D", deps = {} },
	})
	T.check(
		"цикл найден у всех участников",
		issues.A ~= nil and issues.B ~= nil and issues.C ~= nil
	)
	T.check("вид проблемы — cycle", issues.A and issues.A.kind == "cycle")
	T.check(
		"в сообщении имена цикла",
		issues.A ~= nil
			and string.find(issues.A.message, "A") ~= nil
			and string.find(issues.A.message, "C") ~= nil
	)
	T.check("модуль вне цикла без проблем", issues.D == nil)
	T.check("все вершины в порядке", #sorted == 4)
end

do
	local _, issues = DependencyGraph.sort({ { name = "X", deps = { "Ghost" } } })
	T.check(
		"пропавшая зависимость",
		issues.X ~= nil and issues.X.kind == "missing"
	)
	T.check(
		"в сообщении имя пропавшей",
		issues.X ~= nil and string.find(issues.X.message, "Ghost") ~= nil
	)
end

do
	local _, issues = DependencyGraph.sort({ { name = "Self", deps = { "Self" } } })
	T.check(
		"зависимость от себя — цикл",
		issues.Self ~= nil and issues.Self.kind == "cycle"
	)
end

T.finish()
