--!strict
--[[ ━━━ ModuleLoader · система core · общее, все плейсы
  Что: запускает синглтоны фазами (все Init → все Start, Destroy в обратном порядке) и печатает отчёт.
  Почему так: упавший модуль → FAILED, зависящие → SKIPPED, остальная игра поднимается; в логе одна
    первопричина. Время меряется всегда: застрявший в WaitForChild модуль виден в «дольше всего».
    Служебные поля (_connections, _destroyed) ставятся ВСЕГДА перед Init: синглтон — таблица модуля,
    require её кэширует, и повторный запуск поднимает тот же объект.
  Не здесь: поиск модулей по папкам — Bootstrap; порядок — DependencyGraph.
━━━ ]]

local Logger = require(script.Parent.Logger)
local DependencyGraph = require(script.Parent.DependencyGraph)
local ConnectionUtil = require(script.Parent.ConnectionUtil)
local CoreConfig = require(script.Parent.CoreConfig)

export type Status = "OK" | "FAILED" | "SKIPPED"

export type Record = {
	name: string,
	module: any?,
	deps: { string },
	status: Status?,
	error: string?,
	note: string?,
	requireMs: number,
	initMs: number,
	startMs: number,
}

export type ModuleLoader = {
	side: string,
	add: (self: ModuleLoader, name: string, module: any, requireMs: number?) -> (),
	addFailed: (self: ModuleLoader, name: string, err: any, requireMs: number?) -> (),
	loadAll: (self: ModuleLoader) -> (),
	unloadAll: (self: ModuleLoader) -> (),
	records: (self: ModuleLoader) -> { Record },
	count: (self: ModuleLoader, status: Status) -> number,
	totalMs: (self: ModuleLoader) -> number,
}

local ModuleLoader = {}
ModuleLoader.__index = ModuleLoader

function ModuleLoader.new(side: string): ModuleLoader
	local self = {
		side = side,
		_log = Logger.new("ModuleLoader", true),
		_records = {} :: { Record },
		_byName = {} :: { [string]: Record },
		_order = {} :: { Record },
		_loaded = false,
	}
	return (setmetatable(self, ModuleLoader) :: any) :: ModuleLoader
end

local function newRecord(name: string, module: any?, deps: { string }, requireMs: number?): Record
	return {
		name = name,
		module = module,
		deps = deps,
		status = nil,
		error = nil,
		note = nil,
		requireMs = requireMs or 0,
		initMs = 0,
		startMs = 0,
	}
end

function ModuleLoader.add(self: any, name: string, module: any, requireMs: number?)
	assert(not self._loaded, "ModuleLoader: add после loadAll")
	local deps: { string } = {}
	if type(module.dependencies) == "table" then
		for _, dep in ipairs(module.dependencies) do
			if type(dep) == "string" then
				table.insert(deps, dep)
			end
		end
	end
	local record = newRecord(name, module, deps, requireMs)
	table.insert(self._records, record)
	self._byName[name] = record
end

-- Модуль, упавший ещё на require: FAILED, чтобы зависящие стали SKIPPED.
function ModuleLoader.addFailed(self: any, name: string, err: any, requireMs: number?)
	local record = newRecord(name, nil, {}, requireMs)
	record.status = "FAILED"
	record.error = tostring(err)
	record.note = "require"
	table.insert(self._records, record)
	self._byName[name] = record
end

local function prepare(record: Record)
	local module = record.module
	if not module then
		return
	end
	if rawget(module, "name") == nil then
		rawset(module, "name", record.name)
	end
	if rawget(module, "_log") == nil then
		rawset(module, "_log", Logger.new(record.name))
	end
	ConnectionUtil.disconnectAll(rawget(module, "_connections"))
	rawset(module, "_connections", {})
	rawset(module, "_destroyed", false)
end

local function blockedBy(self: any, record: Record): Record?
	for _, depName in ipairs(record.deps) do
		local dep = self._byName[depName]
		if dep and (dep.status == "FAILED" or dep.status == "SKIPPED") then
			return dep
		end
	end
	return nil
end

-- Одна фаза у всех модулей по порядку. phase = "Init" | "Start".
local function runPhase(self: any, phase: string)
	for _, record in ipairs(self._order) do
		if record.status ~= nil then
			continue
		end
		local blocker = blockedBy(self, record)
		if blocker then
			record.status = "SKIPPED"
			record.note =
				string.format("зависит от %s (%s)", blocker.name, tostring(blocker.status))
			continue
		end
		if phase == "Init" then
			prepare(record)
		end
		local module = record.module
		local fn = module and module[phase]
		if type(fn) == "function" then
			local began = os.clock()
			local ok, err = pcall(fn, module)
			local ms = (os.clock() - began) * 1000
			if phase == "Init" then
				record.initMs = ms
			else
				record.startMs = ms
			end
			if not ok then
				record.status = "FAILED"
				record.error = tostring(err)
				record.note = phase
				self._log:Critical("%s упал · %s · %s", phase, record.name, tostring(err))
			end
		end
		if phase == "Start" and record.status == nil then
			record.status = "OK"
		end
	end
end

function ModuleLoader.loadAll(self: any)
	assert(not self._loaded, "ModuleLoader: повторный loadAll")
	self._loaded = true
	local entries: { DependencyGraph.Entry } = {}
	for _, record in ipairs(self._records) do
		table.insert(entries, { name = record.name, deps = record.deps })
	end
	local sorted, issues = DependencyGraph.sort(entries)
	for _, entry in ipairs(sorted) do
		table.insert(self._order, self._byName[entry.name])
	end
	-- Цикл или пропавшая зависимость — ошибка конфигурации: модуль не вызываем вовсе.
	for name, issue in pairs(issues) do
		local record = self._byName[name]
		if record and record.status == nil then
			record.status = "FAILED"
			record.error = issue.message
			record.note = issue.kind
			self._log:Critical("%s · %s", name, issue.message)
		end
	end
	runPhase(self, "Init")
	runPhase(self, "Start")
	ModuleLoader.report(self)
end

-- Destroy в обратном порядке: потребитель отпускает зависимость раньше, чем та развалится.
function ModuleLoader.unloadAll(self: any)
	for i = #self._order, 1, -1 do
		local record = self._order[i]
		local module = record.module
		if module and record.status == "OK" then
			if type(module.Destroy) == "function" then
				local ok, err = pcall(module.Destroy, module)
				if not ok then
					self._log:Critical("Destroy упал · %s · %s", record.name, tostring(err))
				end
			else
				ConnectionUtil.disconnectAll(rawget(module, "_connections"))
				rawset(module, "_destroyed", true)
			end
		end
	end
end

local function moduleMs(record: Record): number
	return record.requireMs + record.initMs + record.startMs
end

function ModuleLoader.totalMs(self: any): number
	local total = 0
	for _, record in ipairs(self._records) do
		total += moduleMs(record)
	end
	return total
end

function ModuleLoader.records(self: any): { Record }
	return table.clone(self._records)
end

function ModuleLoader.count(self: any, status: Status): number
	local n = 0
	for _, record in ipairs(self._records) do
		if record.status == status then
			n += 1
		end
	end
	return n
end

local function slowestLine(self: any): string?
	local sorted = table.clone(self._records)
	table.sort(sorted, function(a, b)
		return moduleMs(a) > moduleMs(b)
	end)
	local parts = {}
	for _, record in ipairs(sorted) do
		if #parts >= CoreConfig.Boot.SlowTop or moduleMs(record) < CoreConfig.Boot.SlowFloorMs then
			break
		end
		table.insert(parts, string.format("%s %.0fмс", record.name, moduleMs(record)))
	end
	return if #parts > 0 then table.concat(parts, " · ") else nil
end

function ModuleLoader.report(self: any)
	local ok = ModuleLoader.count(self, "OK")
	local failed = ModuleLoader.count(self, "FAILED")
	local skipped = ModuleLoader.count(self, "SKIPPED")
	local slowest = slowestLine(self)
	if failed == 0 and skipped == 0 then
		self._log:Info(
			"%s · поднято модулей: %d за %.0fмс",
			self.side,
			ok,
			ModuleLoader.totalMs(self)
		)
		if slowest then
			self._log:Info("дольше всего: %s", slowest)
		end
		return
	end
	self._log:Critical("──── отчёт загрузки · %s ────", self.side)
	for _, record in ipairs(self._records) do
		local detail = ""
		if record.error then
			detail = string.format("  ← %s: %s", record.note or "?", record.error)
		elseif record.note then
			detail = "  ← " .. record.note
		end
		self._log:Critical(
			"  %-8s %-28s %.0fмс%s",
			record.status or "?",
			record.name,
			moduleMs(record),
			detail
		)
	end
	self._log:Critical(
		"──── %d OK · %d FAILED · %d SKIPPED · %.0fмс ────",
		ok,
		failed,
		skipped,
		ModuleLoader.totalMs(self)
	)
	if slowest then
		self._log:Critical("дольше всего: %s", slowest)
	end
end

return ModuleLoader
