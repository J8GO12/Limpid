local _, ns = ...

local Module = ns:NewModule("Tradeskills")

-- Lua API
local string_format = string.format
local tonumber = tonumber
local type = type

-- WoW Globals
local G = {
	SKILL_RANK_UP = SKILL_RANK_UP, -- "Your skill in %s has increased to %d."
	LEARN_RECIPE = ERR_LEARN_RECIPE_S, -- "You have learned how to create a new item: %s."
	LEARNED = TRADE_SKILLS_LEARNED_TAB or "Learned", -- "Learned"
	UNLEARNED = TRADE_SKILLS_UNLEARNED_TAB or "Unlearned", -- "Unlearned"
}

-- Search Pattern Cache (self-populating via ns.MakePattern on first lookup).
local P = ns.MakePatternCache()

-- Safe pattern match that tolerates a nil pattern (shared helper).
local safeMatch = ns.SafeMatch

-- Anchored patterns for "<name> creates: <item>." craft broadcasts, built
-- from the client's own strings so they work in every language. The whole
-- line is anchored to limit false positives on normal chat.
local CREATE_MULTIPLE_PATTERN = CREATED_ITEM_MULTIPLE and ("^" .. ns.MakePattern(CREATED_ITEM_MULTIPLE) .. "$") -- "%s creates: %sx%d."
local CREATE_SINGLE_PATTERN = CREATED_ITEM and ("^" .. ns.MakePattern(CREATED_ITEM) .. "$") -- "%s creates: %s."

-- Best-effort class colour for a crafter's name (shared helper).
local GetClassColoredName = ns.GetClassColoredName

Module.OnChatEvent = function(self, chatFrame, event, message, author, ...)
	if type(message) ~= "string" then
		return
	end

	local skill, gain = safeMatch(message, P[G.SKILL_RANK_UP])
	if skill and gain then
		gain = tonumber(gain)
		if gain then
			return false, string_format(ns.out.item_multiple, skill, gain), author, ...
		end
	end

	local craft = safeMatch(message, P[G.LEARN_RECIPE])
	if craft then
		return false, string_format(ns.out.objective_status, G.LEARNED, craft), author, ...
	end
end

Module.OnReplacementSet = function(self, msg, r, g, b, chatID, ...)
	-- Recipe learned. Handled here at the replacement layer because it can fire
	-- during the initial PLAYER_ENTERING_WORLD, before the chat frames are
	-- registered for user events.
	local craft = safeMatch(msg, P[G.LEARN_RECIPE])
	if craft then
		return string_format(ns.out.objective_status, G.LEARNED, craft)
	end

	-- "<player> creates: <item>." craft broadcasts.
	-- Reformat them as: "<player>" created: <item>, class-colouring the name.
	local who, item, count = safeMatch(msg, CREATE_MULTIPLE_PATTERN)
	if who and item and count then
		return string_format(ns.out.craft_multiple_other, GetClassColoredName(who), ns.StripBrackets(item), tonumber(count) or 1)
	end

	who, item = safeMatch(msg, CREATE_SINGLE_PATTERN)
	if who and item then
		return string_format(ns.out.craft_single_other, GetClassColoredName(who), ns.StripBrackets(item))
	end
end

-- Blacklist filter: when the option is enabled, hide other players'
-- "<player> creates <item>" craft broadcasts entirely instead of letting
-- OnReplacementSet reformat them. Blacklists run BEFORE replacements, so a
-- dropped line is never reformatted.
Module.OnAddMessage = function(self, chatFrame, msg, r, g, b, chatID, ...)
	if (not ns.db) or not ns.db.hideOtherCrafts then
		return
	end
	if not msg then
		return
	end

	if (safeMatch(msg, CREATE_MULTIPLE_PATTERN)) or (safeMatch(msg, CREATE_SINGLE_PATTERN)) then
		return true
	end
end

local onAddMessageProxy = function(...)
	return Module:OnAddMessage(...)
end

local onChatEventProxy = function(...)
	return Module:OnChatEvent(...)
end

local onReplacementSetProxy = function(...)
	return Module:OnReplacementSet(...)
end

Module.OnEnable = function(self)
	self:RegisterBlacklistFilter(onAddMessageProxy)
	self:RegisterMessageReplacement(onReplacementSetProxy)
	self:RegisterMessageEventFilter("CHAT_MSG_SKILL", onChatEventProxy)
end

Module.OnDisable = function(self)
	self:UnregisterBlacklistFilter(onAddMessageProxy)
	self:UnregisterMessageReplacement(onReplacementSetProxy)
	self:UnregisterMessageEventFilter("CHAT_MSG_SKILL", onChatEventProxy)
end
