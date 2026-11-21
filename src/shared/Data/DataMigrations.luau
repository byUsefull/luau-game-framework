--!strict
--[[ ━━━ DataMigrations · система data · общее, все плейсы
  Что: миграции профиля по версиям схемы — по функции на версию, по порядку; run доводит старый профиль
    до текущей DataConfig.Version.
  Почему так: смысл поля поменялся — старые игроки не теряют прогресс. Чистые функции без Roblox API
    и без require — проверяются lune на копии старого профиля (tests/data_migrations.spec.luau).
  Не здесь: новые поля без смены смысла — просто в DataConfig.Default (доливаются сами).
━━━ ]]

export type Migration = (data: { [string]: any }) -> ()

local DataMigrations = {}

-- Steps[N] переводит профиль из версии N-1 в N. Новая версия = новая функция в конце, старые не правятся.
-- Пример: Steps[2] = function(data) data.Currency.coins = data.Currency.gold; data.Currency.gold = nil end
DataMigrations.Steps = {} :: { [number]: Migration }

-- Доводит data до target. Возвращает итоговую версию и список применённых шагов.
-- steps — для тестов; по умолчанию DataMigrations.Steps.
function DataMigrations.run(
	data: { [string]: any },
	versionField: string,
	target: number,
	steps: { [number]: Migration }?
): (number, { number })
	local list = steps or DataMigrations.Steps
	local version = tonumber(data[versionField]) or 1
	local applied = {}
	while version < target do
		local nextVersion = version + 1
		local step = list[nextVersion]
		if step then
			step(data)
			table.insert(applied, nextVersion)
		end
		version = nextVersion
		data[versionField] = version
	end
	return version, applied
end

return DataMigrations
