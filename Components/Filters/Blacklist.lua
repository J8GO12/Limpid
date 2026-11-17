local _, ns = ...

local Module = ns:NewModule("Blacklist")

-- Lua API
local string_find = string.find
local string_format = string.format
local tonumber = tonumber
local type = type

-- Build blacklist table safely
local B = {}
if ERR_NOT_IN_INSTANCE_GROUP then
	B[ERR_NOT_IN_INSTANCE_GROUP] = true
end
if ERR_NOT_IN_RAID then
	B[ERR_NOT_IN_RAID] = true
end
if ERR_QUEST_ALREADY_ON then
	B[ERR_QUEST_ALREADY_ON] = true
end

-- "Your equipped items suffer a %d%% durability loss."
local DURABILITY_PATTERN = ns.MakePattern(DURABILITYDAMAGE_DEATH)

Module.OnChatEvent = function(self, chatFrame, event, message, author, ...)
	if type(message) ~= "string" then
		return
	end

	-- Death message: |cff71d5ff|Hdeath:...|h[You died.]|h|r
	if string_find(message, "|Hdeath:", 1, true) then
		return false, ns.out.died, author, ...
	end

	-- Durability loss: "Your equipped items suffer a 10% durability loss."
	-- Comes through CHAT_MSG_COMBAT_MISC_INFO
	if event == "CHAT_MSG_COMBAT_MISC_INFO" then
		local durability = ns.SafeMatch(message, DURABILITY_PATTERN)
		if durability and tonumber(durability) then
			return false, string_format(ns.out.durability_loss, tonumber(durability)), author, ...
		end
	end

	if B[message] then
		-- These problems mostly occur in battlegrounds and other PvP.
		-- (Single boolean only: extra return values would replace the message.)
		if IsInInstance() then
			return true
		end
	end
end

local onChatEventProxy = function(...)
	return Module:OnChatEvent(...)
end

Module.OnEnable = function(self)
	self:RegisterMessageEventFilter("CHAT_MSG_SYSTEM", onChatEventProxy)
	self:RegisterMessageEventFilter("CHAT_MSG_COMBAT_MISC_INFO", onChatEventProxy)
end

Module.OnDisable = function(self)
	self:UnregisterMessageEventFilter("CHAT_MSG_SYSTEM", onChatEventProxy)
	self:UnregisterMessageEventFilter("CHAT_MSG_COMBAT_MISC_INFO", onChatEventProxy)
end
