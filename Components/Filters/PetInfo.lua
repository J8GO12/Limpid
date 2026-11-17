local _, ns = ...

local Module = ns:NewModule("PetInfo")

-- Hides pet spam (happiness changes, pet abilities learned/unlearned, ...).
--
-- Forever port: these lines arrive through their own CHAT_MSG_PET_INFO event,
-- so the whole event is dropped while this filter is on. That works in every
-- client language, unlike the English text match the 3.3.5 version used.
Module.OnChatEvent = function()
	return true
end

local onChatEventProxy = function(...)
	return Module:OnChatEvent(...)
end

Module.OnEnable = function(self)
	self:RegisterMessageEventFilter("CHAT_MSG_PET_INFO", onChatEventProxy)
end

Module.OnDisable = function(self)
	self:UnregisterMessageEventFilter("CHAT_MSG_PET_INFO", onChatEventProxy)
end
