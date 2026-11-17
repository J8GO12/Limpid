local Addon, ns = ...

-- WoW Forever (1.60.x, interface 16001) compatibility helpers.
--
-- Forever runs on the modern (Mainline 12.x) client API, so none of the 3.3.5
-- polyfills of the original addon are needed anymore -- and patching Blizzard
-- globals or widget metatables is exactly what must NOT be done on this client
-- (it taints the UI). Everything here is PRIVATE to the addon namespace.

local _G = _G
local pairs = pairs
local select = select
local type = type

-- Timers: the native C_Timer is always available on Forever.
ns.Timer = _G.C_Timer

-- Secret values (Midnight "addon disarmament", active on Forever).
-- During chat-messaging lockdown (boss encounters etc.) chat text reaches
-- addons as opaque "secret" values: they can be handed to widgets (SetText,
-- AddMessage) but any comparison, concatenation or string.* call on them throws.
-- Every code path that touches chat text checks this first.
local issecretvalue = _G.issecretvalue
ns.IsSecret = function(value)
	if issecretvalue then
		return issecretvalue(value)
	end
	return false
end

-- True if ANY of the given values is secret.
ns.AnySecret = function(...)
	if not issecretvalue then
		return false
	end
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then
			return true
		end
	end
	return false
end

-- Plain table copy (kept local instead of relying on a Blizzard global).
local function copyTable(source)
	local copy = {}
	for k, v in pairs(source) do
		if type(v) == "table" then
			copy[k] = copyTable(v)
		else
			copy[k] = v
		end
	end
	return copy
end
ns.CopyTable = copyTable

-- Addon metadata (GetAddOnMetadata moved to C_AddOns).
ns.GetAddOnMetadata = function(field)
	if _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata then
		return _G.C_AddOns.GetAddOnMetadata(Addon, field)
	end
end

ns.IsAddOnLoaded = function(name)
	if _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded then
		return _G.C_AddOns.IsAddOnLoaded(name)
	end
	return false
end

-- Item info (GetItemInfo moved to C_Item). Returns the same values.
ns.GetItemInfo = function(item)
	if _G.C_Item and _G.C_Item.GetItemInfo then
		return _G.C_Item.GetItemInfo(item)
	end
end

ns.GetItemIcon = function(item)
	if _G.C_Item and _G.C_Item.GetItemIconByID then
		return _G.C_Item.GetItemIconByID(item)
	end
end

-- Bag access (moved to C_Container; info is now a table).
ns.GetContainerItemLink = function(bag, slot)
	if _G.C_Container and _G.C_Container.GetContainerItemLink then
		return _G.C_Container.GetContainerItemLink(bag, slot)
	end
end

ns.GetContainerItemCount = function(bag, slot)
	if _G.C_Container and _G.C_Container.GetContainerItemInfo then
		local info = _G.C_Container.GetContainerItemInfo(bag, slot)
		return info and info.stackCount or nil
	end
end

-- Chat message event filters: the ChatFrame_* globals are deprecation shims
-- that only exist when a CVar enables them; ChatFrameUtil is the real API.
ns.AddMessageEventFilter = function(event, func)
	_G.ChatFrameUtil.AddMessageEventFilter(event, func)
end

ns.RemoveMessageEventFilter = function(event, func)
	_G.ChatFrameUtil.RemoveMessageEventFilter(event, func)
end

-- Reloading the UI from addon code is a protected action on this client
-- (it triggers the "addon action blocked" popup), so we ask the user instead.
ns.RequestReload = function(reason)
	print("|cffDFBA69Limpid|r: " .. (reason or "Type |cffffd200/reload|r to apply the changes."))
end
