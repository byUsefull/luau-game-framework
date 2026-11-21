--!strict
--[[ ━━━ Validate · система network · общее, все плейсы
  Что: проверки данных от клиента: shape, str, num, int, bool, oneOf, optional, array, instance, vector3, none.
  Почему так: типы Luau живут только при разработке, а клиент читера шлёт что угодно. NaN и inf отсекаются,
    у строк и массивов обязательный предел длины, лишние ключи в shape — отказ.
    Без Roblox API, кроме instance и vector3, и без require — проверяет lune (tests/network_validate.spec.luau).
  Не здесь: «можно ли сейчас» (жив, в зоне, хватает денег) — в обработчике сервиса.
━━━ ]]

export type Check = (value: any) -> boolean
export type Validator = (payload: any, player: Player?) -> boolean

local Validate = {}

-- «Проверка не нужна, и я это осознаю». Единственный законный способ её отключить.
function Validate.none(_payload: any, _player: Player?): boolean
	return true
end

-- Ничего не должно прийти.
function Validate.empty(payload: any, _player: Player?): boolean
	return payload == nil
end

local function finite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

function Validate.str(maxLength: number): Check
	return function(value: any): boolean
		return type(value) == "string" and #value <= maxLength
	end
end

-- Непустая строка из латиницы, цифр, точек, «_» и «-» (ключи конфигов).
function Validate.key(maxLength: number): Check
	return function(value: any): boolean
		return type(value) == "string"
			and #value > 0
			and #value <= maxLength
			and string.match(value, "^[%w%._%-]+$") ~= nil
	end
end

function Validate.num(min: number, max: number): Check
	return function(value: any): boolean
		return type(value) == "number" and finite(value) and value >= min and value <= max
	end
end

function Validate.int(min: number, max: number): Check
	local inRange = Validate.num(min, max)
	return function(value: any): boolean
		return inRange(value) and value % 1 == 0
	end
end

function Validate.bool(value: any): boolean
	return type(value) == "boolean"
end

function Validate.oneOf(allowed: { any }): Check
	local set = {}
	for _, item in ipairs(allowed) do
		set[item] = true
	end
	return function(value: any): boolean
		return value ~= nil and set[value] == true
	end
end

function Validate.optional(check: Check): Check
	return function(value: any): boolean
		return value == nil or check(value)
	end
end

-- Живой Instance нужного класса в дереве игры (удалённый «призрак» не проходит).
function Validate.instance(className: string): Check
	return function(value: any): boolean
		return typeof(value) == "Instance" and value:IsA(className) and value:IsDescendantOf(game)
	end
end

function Validate.vector3(value: any): boolean
	return typeof(value) == "Vector3" and finite(value.X) and finite(value.Y) and finite(value.Z)
end

-- Массив до maxCount элементов, каждый проходит check. Словарь и дыры — отказ.
function Validate.array(check: Check, maxCount: number): Check
	return function(value: any): boolean
		if type(value) ~= "table" or getmetatable(value) ~= nil then
			return false
		end
		local count = 0
		for key, item in pairs(value) do
			if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
				return false
			end
			count += 1
			if count > maxCount or not check(item) then
				return false
			end
		end
		return count == #value
	end
end

-- Таблица ровно с этими полями: лишний ключ — отказ (пакет на сто тысяч ключей не разбираем).
function Validate.shape(fields: { [string]: Check }): Validator
	return function(payload: any, _player: Player?): boolean
		if type(payload) ~= "table" or getmetatable(payload) ~= nil then
			return false
		end
		for key in pairs(payload) do
			if type(key) ~= "string" or fields[key] == nil then
				return false
			end
		end
		for key, check in pairs(fields) do
			if not check(payload[key]) then
				return false
			end
		end
		return true
	end
end

-- Одно значение вместо таблицы: validate = Validate.value(Validate.str(32)).
function Validate.value(check: Check): Validator
	return function(payload: any, _player: Player?): boolean
		return check(payload)
	end
end

return Validate
