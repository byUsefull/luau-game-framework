--!strict
-- PlayerScope · система player · завершённые задачи не удерживаются до выхода игрока.
local Luau = require("@lune/luau")
local FS = require("@lune/fs")
local T = require("./TestKit")

local Entity = {
	extend = function()
		return {}
	end,
	destroy = function(self)
		self._destroyed = true
	end,
}
local disconnect = function(item)
	if type(item) == "thread" and coroutine.status(item) ~= "dead" then
		coroutine.close(item)
	end
end
local core = {
	Entity = Entity,
	ConnectionUtil = {
		disconnect = disconnect,
		disconnectAll = function(items)
			for _, item in ipairs(items) do
				disconnect(item)
			end
		end,
	},
}
local Scope = Luau.load(FS.readFile("src/server/Player/PlayerScope.luau"), {
	environment = {
		game = {
			GetService = function()
				return { Shared = { Core = core } }
			end,
		},
		require = function(module)
			return module
		end,
		task = {
			spawn = function(fn, ...)
				local thread = coroutine.create(fn)
				assert(coroutine.resume(thread, ...))
				return thread
			end,
		},
	},
})()
local scope = setmetatable({ _items = {}, _destroyed = false }, { __index = Scope })
local sum = 0
for _ = 1, 100 do
	scope:Spawn(function(value)
		sum += value
	end, 2)
end
T.eq("аргументы потока передаются", sum, 200)
T.eq("завершённые сразу потоки не копятся", #scope._items, 0)
local waiting = scope:Spawn(function()
	coroutine.yield()
end)
T.eq("ожидающий поток под уборкой", #scope._items, 1)
assert(coroutine.resume(waiting))
T.eq(
	"завершившийся после ожидания поток удалён",
	#scope._items,
	0
)
local cancelled = scope:Spawn(function()
	coroutine.yield()
end)
scope:destroy()
T.eq(
	"выход отменяет ожидающий поток",
	coroutine.status(cancelled),
	"dead"
)
T.eq("после выхода список пуст", #scope._items, 0)
T.finish()
