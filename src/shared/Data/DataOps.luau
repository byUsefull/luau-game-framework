--!strict
--[[ ━━━ DataOps · система data · общее, все плейсы
  Что: чистые операции над таблицей профиля: глубокая копия, атомарная правка с откатом и запретом
    yield, снимок без приватных полей, изменённые ключи, проверка JSON-совместимости, размер, доливка схемы.
  Почему так: правило «запись целиком или никак» проверяется lune без Studio (tests/data_ops.spec.luau).
    Правка идёт на копии: упала, вернула false или попыталась ждать — живые данные не тронуты.
  Не здесь: сессии ProfileStore и сохранение — DataService и Profile.
━━━ ]]

local DataOps = {}

function DataOps.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value :: any) do
		out[DataOps.deepCopy(k)] = DataOps.deepCopy(v)
	end
	return out :: any
end

-- Заменить содержимое target содержимым source, не меняя саму таблицу (ссылка ProfileStore живёт).
function DataOps.replaceContents(target: { [any]: any }, source: { [any]: any })
	table.clear(target)
	for k, v in pairs(source) do
		target[k] = v
	end
end

export type ApplyResult = { ok: boolean, data: any?, error: string? }

-- Правка на копии. fn(copy) может вернуть false — отказ без ошибки. Ошибка или yield — откат.
function DataOps.applyAtomic(data: any, fn: (any) -> boolean?): ApplyResult
	local copy = DataOps.deepCopy(data)
	local thread = coroutine.create(fn)
	local resumed, result = coroutine.resume(thread, copy)
	if coroutine.status(thread) ~= "dead" then
		coroutine.close(thread)
		return {
			ok = false,
			error = "yield внутри правки профиля — запись отменена",
		}
	end
	if not resumed then
		return { ok = false, error = tostring(result) }
	end
	if result == false then
		return { ok = false, error = "отказ" }
	end
	local safe, path = DataOps.jsonSafe(copy)
	if not safe then
		return { ok = false, error = "не JSON-совместимое значение: " .. path }
	end
	return { ok = true, data = copy }
end

-- То же для двух профилей сразу (обмен): fn(copyA, copyB).
function DataOps.applyPair(a: any, b: any, fn: (any, any) -> boolean?): (ApplyResult, ApplyResult?)
	local copyB: any = nil
	local first = DataOps.applyAtomic(a, function(copyA)
		copyB = DataOps.deepCopy(b)
		return fn(copyA, copyB)
	end)
	if not first.ok then
		return first, nil
	end
	local safe, path = DataOps.jsonSafe(copyB)
	if not safe then
		return {
			ok = false,
			error = "не JSON-совместимое значение во втором профиле: "
				.. path,
		},
			nil
	end
	return first, { ok = true, data = copyB }
end

-- Частая локальная правка: callback видит только копии явно выбранных разделов.
-- Остальной профиль не копируется и не доступен через переданную таблицу.
function DataOps.applyFieldsAtomic(
	data: any,
	fields: { string },
	fn: (any) -> boolean?
): ApplyResult
	if type(fields) ~= "table" or #fields == 0 then
		return { ok = false, error = "UpdateFields: нужны имена разделов" }
	end
	local allowed, selected = {}, {}
	local count = 0
	for index, key in pairs(fields) do
		count += 1
		if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #fields then
			return {
				ok = false,
				error = "UpdateFields: нужен плотный список разделов",
			}
		end
		if type(key) ~= "string" or key == "" or allowed[key] then
			return {
				ok = false,
				error = "UpdateFields: неверный или повторный раздел",
			}
		end
		allowed[key] = true
		selected[key] = data[key]
	end
	if count ~= #fields then
		return {
			ok = false,
			error = "UpdateFields: нужен плотный список разделов",
		}
	end
	return DataOps.applyAtomic(selected, function(copy)
		if fn(copy) == false then
			return false
		end
		for key in pairs(copy) do
			if not allowed[key] then
				error(
					"UpdateFields: запись вне выбранных разделов: "
						.. tostring(key)
				)
			end
		end
		return true
	end)
end

local function isArray(t: { [any]: any }): (boolean, number)
	local count = 0
	for k in pairs(t) do
		if type(k) ~= "number" then
			return false, 0
		end
		count += 1
	end
	return count > 0 and count == #t, count
end

-- true или (false, путь к плохому значению). Нельзя: Instance, Vector3, функции, NaN, inf,
-- смешанные ключи, массивы с дырами.
function DataOps.jsonSafe(value: any, path: string?): (boolean, string)
	local here = path or "root"
	local kind = type(value)
	if kind == "string" or kind == "boolean" or kind == "nil" then
		return true, ""
	end
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return false, here .. " (NaN или inf)"
		end
		return true, ""
	end
	if kind ~= "table" then
		return false, here .. " (" .. typeof(value) .. ")"
	end
	local hasNumber, hasString = false, false
	for k, v in pairs(value) do
		if type(k) == "number" then
			hasNumber = true
		elseif type(k) == "string" then
			hasString = true
		else
			return false, here .. " (ключ " .. typeof(k) .. ")"
		end
		local ok, bad = DataOps.jsonSafe(v, here .. "." .. tostring(k))
		if not ok then
			return false, bad
		end
	end
	if hasNumber and hasString then
		return false, here .. " (смешаны числовые и строковые ключи)"
	end
	if hasNumber and not isArray(value) then
		return false, here .. " (массив с дырами)"
	end
	return true, ""
end

-- Копия без приватных полей верхнего уровня — то, что уходит клиенту.
function DataOps.snapshot(
	data: { [string]: any },
	private: { [string]: boolean }
): { [string]: any }
	local out = {}
	for k, v in pairs(data) do
		if not private[k] then
			out[k] = DataOps.deepCopy(v)
		end
	end
	return out
end

function DataOps.equal(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not DataOps.equal(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- Ключи верхнего уровня, которые отличаются (для пакета изменений клиенту).
function DataOps.changedKeys(before: { [string]: any }, after: { [string]: any }): { string }
	local keys, seen = {}, {}
	for k, v in pairs(after) do
		seen[k] = true
		if not DataOps.equal(before[k], v) then
			table.insert(keys, k)
		end
	end
	for k in pairs(before) do
		if not seen[k] then
			table.insert(keys, k)
		end
	end
	table.sort(keys)
	return keys
end

-- Долить отсутствующие поля из схемы (новые поля у старых игроков). Существующее не трогает.
function DataOps.reconcile(data: { [string]: any }, template: { [string]: any })
	for k, v in pairs(template) do
		if data[k] == nil then
			data[k] = DataOps.deepCopy(v)
		elseif
			type(v) == "table"
			and type(data[k]) == "table"
			and next(v) ~= nil
			and not isArray(v)
		then
			DataOps.reconcile(data[k], v)
		end
	end
end

return DataOps
