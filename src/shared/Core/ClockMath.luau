--!strict
--[[ ━━━ ClockMath · система core · общее, все плейсы
  Что: номер дня, отсчёт до сброса, разбор «1d 3h», дата UTC строкой — по переданному времени.
  Почему так: чистые функции без Roblox API и без require — их проверяет lune (tests/core_clock_math.spec.luau);
    os.date не нужен, дата считается по алгоритму «дни → гражданская дата».
  Не здесь: само время сервера и сдвиг — ServerClock.
━━━ ]]

local DAY = 86400

local ClockMath = {}

ClockMath.DAY = DAY

-- Номер игрового дня: сутки начинаются в resetHourUtc.
function ClockMath.dayNumber(t: number, resetHourUtc: number): number
	return math.floor((t - resetHourUtc * 3600) / DAY)
end

-- Сколько секунд до начала следующего игрового дня (1…86400).
function ClockMath.secondsToReset(t: number, resetHourUtc: number): number
	local into = (t - resetHourUtc * 3600) % DAY
	return DAY - into
end

local UNITS: { [string]: number } = { d = DAY, h = 3600, m = 60, s = 1 }

-- «1d», «3h», «90m», «1d12h», «45» (секунды). nil — не разобрал. Отрицательное: «-1d».
function ClockMath.parseDuration(text: string): number?
	local sign = 1
	local rest = string.lower((string.gsub(text, "%s", "")))
	if string.sub(rest, 1, 1) == "-" then
		sign = -1
		rest = string.sub(rest, 2)
	end
	if rest == "" then
		return nil
	end
	if string.match(rest, "^%d+$") then
		return sign * (tonumber(rest) :: number)
	end
	local total = 0
	local consumed = 0
	for number, unit in string.gmatch(rest, "(%d+)([dhms])") do
		total += (tonumber(number) :: number) * UNITS[unit]
		consumed += #number + 1
	end
	if consumed ~= #rest then
		return nil
	end
	return sign * total
end

-- Дни с 1970-01-01 → год, месяц, день (алгоритм Howard Hinnant).
local function civilFromDays(days: number): (number, number, number)
	local z = days + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor(
		(doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365
	)
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	return (if m <= 2 then y + 1 else y), m, d
end

-- «2026-10-02 21:15:03 UTC»
function ClockMath.formatUtc(t: number): string
	local whole = math.floor(t)
	local days = math.floor(whole / DAY)
	local secs = whole - days * DAY
	local y, m, d = civilFromDays(days)
	return string.format(
		"%04d-%02d-%02d %02d:%02d:%02d UTC",
		y,
		m,
		d,
		math.floor(secs / 3600),
		math.floor(secs % 3600 / 60),
		secs % 60
	)
end

-- «5h 03m 09s» / «2d 4h» — для отсчётов и ответов команд.
function ClockMath.formatDuration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local d = math.floor(s / DAY)
	local h = math.floor(s % DAY / 3600)
	local m = math.floor(s % 3600 / 60)
	if d > 0 then
		return string.format("%dd %dh", d, h)
	end
	if h > 0 then
		return string.format("%dh %02dm %02ds", h, m, s % 60)
	end
	return string.format("%dm %02ds", m, s % 60)
end

return ClockMath
