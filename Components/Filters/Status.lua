local _, ns = ...

local Module = ns:NewModule("Status")

-- Lua API
local string_format = string.format
local type = type

-- WoW Globals
local CLEARED_AFK = CLEARED_AFK -- "You are no longer Away."
local CLEARED_DND = CLEARED_DND -- "You are no longer marked Busy."
local DEFAULT_AFK_MESSAGE = DEFAULT_AFK_MESSAGE -- "AFK"
local DEFAULT_DND_MESSAGE = DEFAULT_DND_MESSAGE -- "DND"
local MARKED_AFK = MARKED_AFK -- "You are now Away."
local MARKED_AFK_MESSAGE = MARKED_AFK_MESSAGE -- "You are now Away: %s"
local MARKED_DND = MARKED_DND -- "You are now Busy: %s"
local EXHAUSTION_NORMAL = ERR_EXHAUSTION_NORMAL -- "You are no longer rested."
local EXHAUSTION_WELLRESTED = ERR_EXHAUSTION_WELLRESTED -- "You feel well rested."
local FRIEND_ONLINE = ERR_FRIEND_ONLINE_SS -- "|Hplayer:%s|h[%s]|h has come online."
local FRIEND_OFFLINE = ERR_FRIEND_OFFLINE_S -- "%s has gone offline."

-- Search Pattern Cache (self-populating via ns.MakePattern on first lookup).
local P = ns.MakePatternCache()

-- Safe pattern match that tolerates a nil pattern (shared helper).
local safeMatch = ns.SafeMatch

-- The online/offline lines must be the WHOLE system message.
local ONLINE_ANCHORED = FRIEND_ONLINE and ("^" .. ns.MakePattern(FRIEND_ONLINE) .. "$")
local OFFLINE_ANCHORED = FRIEND_OFFLINE and ("^" .. ns.MakePattern(FRIEND_OFFLINE) .. "$")

Module.OnChatEvent = function(self, chatFrame, event, message, author, ...)
	if type(message) ~= "string" then
		return
	end

	-- AFK
	if MARKED_AFK and message == MARKED_AFK then
		return false, ns.out.afk_added, author, ...
	end
	if CLEARED_AFK and message == CLEARED_AFK then
		return false, ns.out.afk_cleared, author, ...
	end
	local afk_message = safeMatch(message, P[MARKED_AFK_MESSAGE])
	if afk_message then
		if afk_message == DEFAULT_AFK_MESSAGE then
			return false, ns.out.afk_added, author, ...
		end
		return false, string_format(ns.out.afk_added_message, afk_message), author, ...
	end

	-- DND
	if CLEARED_DND and message == CLEARED_DND then
		return false, ns.out.dnd_cleared, author, ...
	end
	local dnd_message = safeMatch(message, P[MARKED_DND])
	if dnd_message then
		if dnd_message == DEFAULT_DND_MESSAGE then
			return false, ns.out.dnd_added, author, ...
		end
		return false, string_format(ns.out.dnd_added_message, dnd_message), author, ...
	end

	-- Rested
	if EXHAUSTION_WELLRESTED and message == EXHAUSTION_WELLRESTED then
		return false, ns.out.rested_added, author, ...
	end
	if EXHAUSTION_NORMAL and message == EXHAUSTION_NORMAL then
		return false, ns.out.rested_cleared, author, ...
	end

	-- Friend / guild member online: "|Hplayer:Name|h[Name]|h has come online."
	-- Friend / guild member offline: "Name has gone offline."
	if ns.db == nil or ns.db.prettifyGuildStatus then
		if ONLINE_ANCHORED then
			local linkTarget, displayName = safeMatch(message, ONLINE_ANCHORED)
			if linkTarget and displayName then
				-- Keep the name clickable (whisper / invite menu).
				local name = "|Hplayer:" .. linkTarget .. "|h" .. ns.GetClassColoredName(displayName) .. "|h"
				return false, string_format(ns.out.guild_online, name), author, ...
			end
		end

		if OFFLINE_ANCHORED then
			local offlineName = safeMatch(message, OFFLINE_ANCHORED)
			if offlineName then
				return false, string_format(ns.out.guild_offline, offlineName), author, ...
			end
		end
	end
end

local onChatEventProxy = function(...)
	return Module:OnChatEvent(...)
end

Module.OnEnable = function(self)
	self:RegisterMessageEventFilter("CHAT_MSG_SYSTEM", onChatEventProxy)
end

Module.OnDisable = function(self)
	self:UnregisterMessageEventFilter("CHAT_MSG_SYSTEM", onChatEventProxy)
end
