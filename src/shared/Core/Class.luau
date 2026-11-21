--!strict
--[[ ━━━ Class · система core · общее, все плейсы
  Что: ООП-основа: extend, new (вызывает init), isA по цепочке наследования.
  Почему так: одна основа для синглтонов (Lifecycle), объектов (Entity) и простых классов.
    extend() возвращает any — форму нового класса статически не вывести, поэтому каждый класс
    объявляет свой export type рядом с реализацией.
  Не здесь: уборка подписок — Lifecycle и Entity.
━━━ ]]

local Class = {}
Class.__index = Class

-- Дочерний класс. Вызов двоеточием: Class:extend().
function Class.extend(self: any): any
	local cls = {}
	cls.__index = cls
	cls.super = self
	setmetatable(cls, { __index = self })
	return cls
end

-- Экземпляр; вызывает init(...), если он объявлен.
function Class.new(self: any, ...: any): any
	local instance = setmetatable({}, self)
	local init = instance.init
	if type(init) == "function" then
		init(instance, ...)
	end
	return instance
end

-- Принадлежность к классу по всей цепочке наследования.
function Class.isA(self: any, klass: any): boolean
	local cls = getmetatable(self)
	while cls do
		if cls == klass then
			return true
		end
		cls = rawget(cls, "super")
	end
	return false
end

return Class
