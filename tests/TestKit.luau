--!strict
-- Мини-набор для lune-тестов кита: check, eq, near, finish. Не спека — lune run его не запускает отдельно.

local TestKit = {}

local passed = 0
local failed = 0

function TestKit.check(name: string, condition: any, detail: string?)
	if condition then
		passed += 1
		print("  ok   · " .. name)
	else
		failed += 1
		print("  FAIL · " .. name .. (if detail then "  — " .. detail else ""))
	end
end

function TestKit.eq(name: string, actual: any, expected: any)
	TestKit.check(
		name,
		actual == expected,
		string.format("ждал %s, получил %s", tostring(expected), tostring(actual))
	)
end

function TestKit.near(name: string, actual: number, expected: number, eps: number?)
	TestKit.check(
		name,
		math.abs(actual - expected) <= (eps or 1e-9),
		string.format("ждал %s, получил %s", tostring(expected), tostring(actual))
	)
end

-- Ловит ошибку: true, если fn упала.
function TestKit.throws(name: string, fn: () -> ())
	local ok = pcall(fn)
	TestKit.check(name, not ok, "ошибки не было")
end

function TestKit.finish()
	print(string.format("════ %d ok · %d fail ════", passed, failed))
	if failed > 0 then
		error(string.format("тесты провалились: %d", failed), 0)
	end
end

return TestKit
