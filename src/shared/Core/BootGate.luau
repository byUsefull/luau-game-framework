--!strict
--[[ ━━━ BootGate · система core · общее, все плейсы
  Что: ждёт, пока атрибут станет true: подписка на изменение плюс честный тайм-аут.
  Почему так: без цикла ожидания (не теряем кадры) и без вечного чёрного экрана, если сервер не поднялся.
  Не здесь: кто ставит ServerReady — ServerMain; ProfileReady — PlayerService.
━━━ ]]

local BootGate = {}

-- true — дождались; false — истёк тайм-аут (клиент всё равно поднимается и покажет, что сломано).
function BootGate.waitForAttribute(container: Instance, attribute: string, timeout: number): boolean
	if container:GetAttribute(attribute) == true then
		return true
	end
	local thread = coroutine.running()
	local settled = false
	local connection: RBXScriptConnection?
	local function finish(result: boolean)
		if settled then
			return
		end
		settled = true
		if connection then
			connection:Disconnect()
		end
		task.spawn(thread, result)
	end
	connection = container:GetAttributeChangedSignal(attribute):Connect(function()
		if container:GetAttribute(attribute) == true then
			finish(true)
		end
	end)
	if container:GetAttribute(attribute) == true then
		finish(true)
	end
	task.delay(timeout, function()
		finish(false)
	end)
	return coroutine.yield()
end

return BootGate
