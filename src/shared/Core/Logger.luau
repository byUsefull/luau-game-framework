--!strict
--[[ ━━━ Logger · система core · общее, все плейсы
  Что: логи с уровнями и областями: [S][Scope] текст. Уровень области меняется на ходу.
  Почему так: вместо print по всему коду; format ленивый — отфильтрованный Debug ничего не стоит.
    permanent = true печатается мимо порогов: только для строки Boot и развала загрузки.
  Не здесь: пороги — CoreConfig.Log; команда смены уровня — /core log (CoreCommands).
━━━ ]]

local RunService = game:GetService("RunService")

local CoreConfig = require(script.Parent.CoreConfig)

local Level = {
	Debug = 1,
	Info = 2,
	Warn = 3,
	Critical = 4,
}

local SIDE = if RunService:IsServer() then "S" else "C"
local BASE_LEVEL: number = if RunService:IsStudio()
	then CoreConfig.Log.StudioLevel
	else CoreConfig.Log.LiveLevel

local overrides: { [string]: number } = {}

local function levelFor(scope: string): number
	return overrides[scope] or CoreConfig.Log.Scopes[scope] or BASE_LEVEL
end

export type Logger = {
	scope: string,
	permanent: boolean,
	Debug: (self: Logger, message: string, ...any) -> (),
	Info: (self: Logger, message: string, ...any) -> (),
	Warn: (self: Logger, message: string, ...any) -> (),
	Critical: (self: Logger, message: string, ...any) -> (),
	IsEnabled: (self: Logger, level: number) -> boolean,
}

local Logger = {}
Logger.__index = Logger
Logger.Level = Level

function Logger.new(scope: string, permanent: boolean?): Logger
	local self = { scope = scope, permanent = permanent == true }
	return (setmetatable(self, Logger) :: any) :: Logger
end

-- Порог области на ходу (команда /core log).
function Logger.setLevel(scope: string, level: number)
	overrides[scope] = level
end

function Logger.resetLevel(scope: string)
	overrides[scope] = nil
end

function Logger.levelOf(scope: string): number
	return levelFor(scope)
end

function Logger.IsEnabled(self: Logger, level: number): boolean
	return self.permanent or level >= levelFor(self.scope)
end

local function emit(self: Logger, level: number, message: string, ...: any)
	if not self.permanent and level < levelFor(self.scope) then
		return
	end
	local body = message
	if select("#", ...) > 0 then
		local ok, formatted = pcall(string.format, message, ...)
		body = if ok then formatted else message .. "  <!format failed>"
	end
	local line = string.format("[%s][%s] %s", SIDE, self.scope, body)
	if level >= Level.Warn then
		warn(line)
	else
		print(line)
	end
end

function Logger.Debug(self: Logger, message: string, ...: any)
	emit(self, Level.Debug, message, ...)
end

function Logger.Info(self: Logger, message: string, ...: any)
	emit(self, Level.Info, message, ...)
end

function Logger.Warn(self: Logger, message: string, ...: any)
	emit(self, Level.Warn, message, ...)
end

function Logger.Critical(self: Logger, message: string, ...: any)
	emit(self, Level.Critical, message, ...)
end

return Logger
