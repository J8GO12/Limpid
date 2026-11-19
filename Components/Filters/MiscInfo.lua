local _, ns = ...

local Module = ns:NewModule("MiscInfo")

-- Lua API
local string_find = string.find
local tonumber = tonumber

-- WoW Globals - Miscellaneous combat/info messages
local G = {
	-- Combo point messages (pattern fallback)
	COMBO_POINTS = "combo point",
	-- Energy/rage/mana messages
	POWER_GAIN = "You gain %d %s.",
}

-- Search Pattern Cache (self-populating via ns.MakePattern on first lookup).
local P = ns.MakePatternCache()

-- Safe pattern match that tolerates a nil pattern (shared helper).
local safeMatch = ns.SafeMatch

-- LANGUAGE NOTE: the two strings above are English literals. The client
-- exposes no global for either line, so unlike the rest of Limpid's filters
-- this one only matches on an English client. Left as-is rather than guessed
-- at; it is off by default.

-- True for the misc-combat lines this filter exists to hide.
local function isMiscSpam(text)
	-- Combo point messages
	if string_find(text, G.COMBO_POINTS) then
		return true
	end

	-- "You gain X energy/rage/mana": redundant with the resource bars.
	local amount, power = safeMatch(text, P[G.POWER_GAIN])
	if amount and power then
		-- Only filter small/spam gains, not significant ones
		local n = tonumber(amount)
		if n and n <= 30 then
			return true
		end
	end

	return false
end

-- Filter out misc combat info spam.
--
-- This runs as a message EVENT filter, not as a display blacklist. The display
-- blacklist is skipped for any line whose chat-type id is in Limpid's ignored
-- set, and COMBAT_MISC_INFO is in that set -- so the previous registration
-- could never see the very messages this module targets, and the filter did
-- nothing at all whatever the user set.
--
-- Lines that do not match fall through untouched, so the durability-loss
-- rewrite that Blacklist.lua performs on the same event still runs.
Module.OnChatEvent = function(_, _, _, message)
	if type(message) ~= "string" then
		return
	end

	if isMiscSpam(message) then
		return true
	end
end

local onChatEventProxy = function(...)
	return Module:OnChatEvent(...)
end

Module.OnEnable = function(self)
	self:RegisterMessageEventFilter("CHAT_MSG_COMBAT_MISC_INFO", onChatEventProxy)
end

Module.OnDisable = function(self)
	self:UnregisterMessageEventFilter("CHAT_MSG_COMBAT_MISC_INFO", onChatEventProxy)
end
