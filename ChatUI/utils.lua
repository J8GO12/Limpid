local Core, _, Utils = unpack(select(2, ...))

-- Utility functions

---
-- Print to VDT
Utils.print = function(str, t)
	if _G.ViragDevTool_AddData then
		_G.ViragDevTool_AddData(t, str)
	else
		-- Buffer print messages until ViragDevTool loads
		table.insert(Core.printBuffer, { str, t })
	end
end

---
-- Prints LimpidUI' notification messages
Utils.notify = function(message)
	print("|cffDFBA69Limpid|r: ", message)
end

---
-- Set a solid-colour texture. Centralizes the helper that was copy-pasted
-- into several LimpidUI components.
Utils.SetSolidColor = function(texture, r, g, b, a)
	texture:SetColorTexture(r or 1, g or 1, b or 1, a or 1)
end

---
-- Secret values (see Core/Common/Compatibility.lua). Chat text can reach the
-- display as an opaque "secret" during chat-messaging lockdown: it may be
-- passed to FontString:SetText, but never inspected.
local issecretvalue = _G.issecretvalue
Utils.IsSecret = function(value)
	if issecretvalue then
		return issecretvalue(value)
	end
	return false
end

---
-- Simple object pool. Kept private to the addon instead of relying on
-- Blizzard's CreateObjectPool, whose signature has changed between clients.
--   creationFunc(pool)      -> new object
--   resetterFunc(pool, obj) -> called when an object is released
Utils.CreateObjectPool = function(creationFunc, resetterFunc)
	local pool = {
		objects = {},
		activeObjects = {},
	}

	function pool:Acquire()
		local obj = table.remove(self.objects)
		if not obj then
			obj = creationFunc(self)
		end
		self.activeObjects[obj] = true
		return obj
	end

	function pool:Release(obj)
		if obj and self.activeObjects[obj] then
			self.activeObjects[obj] = nil
			if resetterFunc then
				resetterFunc(self, obj)
			end
			table.insert(self.objects, obj)
		end
	end

	function pool:ReleaseAll()
		-- Collect first: releasing mutates activeObjects.
		local active = {}
		for obj in pairs(self.activeObjects) do
			active[#active + 1] = obj
		end
		for _, obj in ipairs(active) do
			self:Release(obj)
		end
	end

	function pool:GetNumActive()
		local count = 0
		for _ in pairs(self.activeObjects) do
			count = count + 1
		end
		return count
	end

	return pool
end

---
-- Plain mixin (copies fields onto our OWN frames only).
Utils.Mixin = function(target, ...)
	for i = 1, select("#", ...) do
		local mixin = select(i, ...)
		if mixin then
			for key, value in pairs(mixin) do
				target[key] = value
			end
		end
	end
	return target
end

-- Functional helpers (replaces lodash.wow dependency)

-- Reduce an array to a single value using an accumulator function.
Utils.reduce = function(tbl, fn, initial)
	local acc = initial
	for _, v in ipairs(tbl) do
		acc = fn(acc, v)
	end
	return acc
end

-- Return first N elements of an array.
Utils.take = function(tbl, n)
	local result = {}
	for i = 1, math.min(n, #tbl) do
		result[i] = tbl[i]
	end
	return result
end

-- Return array without first N elements.
Utils.drop = function(tbl, n)
	local result = {}
	for i = n + 1, #tbl do
		result[#result + 1] = tbl[i]
	end
	return result
end
