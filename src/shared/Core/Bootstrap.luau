--!strict
--[[ ━━━ Bootstrap · система core · общее, все плейсы
  Что: собирает синглтоны по суффиксу имени (…Service / …Controller) из папок, регистрирует, запускает.
  Почему так: новый сервис подключается созданием файла — Main не правится никогда. Папки систем
    смешанные (сервис, команды, помощники рядом), поэтому синглтон узнаётся по суффиксу; папки
    Packages (сторонние библиотеки) пропускаются. require каждого в pcall — битый модуль не роняет бут.
  Не здесь: фазы и отчёт — ModuleLoader; сеть готовит Network.start до Bootstrap.run (ServerMain).
━━━ ]]

local Logger = require(script.Parent.Logger)
local Registry = require(script.Parent.ServiceRegistry)
local ModuleLoader = require(script.Parent.ModuleLoader)

local log = Logger.new("Bootstrap", true)

local VENDOR_FOLDER = "Packages"

local Bootstrap = {}

local current: ModuleLoader.ModuleLoader? = nil

local function collect(folder: Instance, suffix: string, out: { ModuleScript })
	local children = folder:GetChildren()
	table.sort(children, function(a, b)
		return a.Name < b.Name
	end)
	for _, child in ipairs(children) do
		if child:IsA("ModuleScript") then
			if string.sub(child.Name, -#suffix) == suffix then
				table.insert(out, child)
			end
		elseif child:IsA("Folder") and child.Name ~= VENDOR_FOLDER then
			collect(child, suffix, out)
		end
	end
end

-- side: "SERVER" | "CLIENT"; suffix: "Service" | "Controller"; folders — по порядку (общие, затем плейса).
function Bootstrap.run(
	side: string,
	suffix: string,
	folders: { Instance }
): ModuleLoader.ModuleLoader
	local scripts: { ModuleScript } = {}
	for _, folder in ipairs(folders) do
		collect(folder, suffix, scripts)
	end
	local loader = ModuleLoader.new(side)
	local seen: { [string]: string } = {}
	for _, moduleScript in ipairs(scripts) do
		local name = moduleScript.Name
		if seen[name] then
			local message = string.format(
				"дубликат имени '%s': %s и %s",
				name,
				seen[name],
				moduleScript:GetFullName()
			)
			log:Critical("%s", message)
			loader:addFailed(name .. " (дубликат)", message)
			continue
		end
		seen[name] = moduleScript:GetFullName()
		local began = os.clock()
		local ok, result = pcall(require, moduleScript)
		local requireMs = (os.clock() - began) * 1000
		if not ok then
			log:Critical(
				"require упал · %s · %s",
				moduleScript:GetFullName(),
				tostring(result)
			)
			loader:addFailed(name, result, requireMs)
		elseif type(result) ~= "table" then
			log:Warn(
				"пропущен (не синглтон, вернул %s): %s",
				typeof(result),
				moduleScript:GetFullName()
			)
		elseif result.autoload == false then
			log:Info("пропущен (autoload = false): %s", name)
		else
			Registry:register(name, result)
			loader:add(name, result, requireMs)
		end
	end
	loader:loadAll()
	current = loader
	return loader
end

-- Загрузчик этой стороны (для /core modules).
function Bootstrap.current(): ModuleLoader.ModuleLoader?
	return current
end

function Bootstrap.shutdown(loader: ModuleLoader.ModuleLoader)
	loader:unloadAll()
	Registry:clear()
	log:Info("выгрузка завершена, реестр очищен")
end

return Bootstrap
