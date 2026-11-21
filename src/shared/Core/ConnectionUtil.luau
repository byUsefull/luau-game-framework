--!strict
--[[ ━━━ ConnectionUtil · система core · общее, все плейсы
  Что: отключает что угодно одним вызовом: связь, поток, Instance, таблицу с Disconnect/Destroy, функцию.
  Почему так: Lifecycle, Entity и PlayerScope складывают разные «подписки» в один список;
    каждая в pcall — одна битая не ломает уборку остальных.
  Не здесь: когда убирать — решают владельцы списков (Lifecycle, Entity, PlayerScope).
━━━ ]]

local ConnectionUtil = {}

-- true, если вид распознан.
function ConnectionUtil.disconnect(connection: any): boolean
	if connection == nil then
		return true
	end
	local kind = typeof(connection)
	if kind == "RBXScriptConnection" then
		pcall(function()
			connection:Disconnect()
		end)
		return true
	end
	if kind == "thread" then
		-- мёртвый и текущий поток отменять нельзя — task.cancel бросит
		if coroutine.status(connection) ~= "dead" and connection ~= coroutine.running() then
			pcall(task.cancel, connection)
		end
		return true
	end
	if kind == "Instance" then
		pcall(function()
			connection:Destroy()
		end)
		return true
	end
	if kind == "function" then
		pcall(connection)
		return true
	end
	if kind == "table" then
		for _, method in ipairs({ "Disconnect", "disconnect", "Destroy", "destroy" }) do
			if type(connection[method]) == "function" then
				pcall(function()
					connection[method](connection)
				end)
				return true
			end
		end
	end
	return false
end

-- Весь список, с конца: поздние подписки часто зависят от ранних.
function ConnectionUtil.disconnectAll(connections: { any }?)
	if not connections then
		return
	end
	for i = #connections, 1, -1 do
		local connection = connections[i]
		connections[i] = nil
		ConnectionUtil.disconnect(connection)
	end
end

return ConnectionUtil
