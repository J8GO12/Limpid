local _, ns = ...

local Module = ns:NewModule("Experience")

-- Lua API
local next = next
local string_format = string.format
local string_gsub = string.gsub
local string_match = string.match
local tonumber = tonumber
local type = type

-- WoW Globals
local G = {
	ERR_ZONE_EXPLORED_XP = ERR_ZONE_EXPLORED_XP, -- "Discovered %s: %d experience gained"
	ERR_QUEST_REWARD_EXP_I = ERR_QUEST_REWARD_EXP_I, -- "Experience gained: %d."
	XP = XP,

	-- All of these contain the first pattern,
	-- and the first pattern contains all we wish to show.
	NAMED = COMBATLOG_XPGAIN_FIRSTPERSON, -- "%s dies, you gain %d experience."
	-- COMBATLOG_XPGAIN_FIRSTPERSON_GROUP					-- "%s dies, you gain %d experience. (+%d group bonus)"
	-- COMBATLOG_XPGAIN_FIRSTPERSON_RAID 					-- "%s dies, you gain %d experience. (-%d raid penalty)"
	-- COMBATLOG_XPGAIN_EXHAUSTION1 						-- "%s dies, you gain %d experience. (%s exp %s bonus)"
	-- COMBATLOG_XPGAIN_EXHAUSTION1_GROUP 					-- "%s dies, you gain %d experience. (%s exp %s bonus, +%d group bonus)"
	-- COMBATLOG_XPGAIN_EXHAUSTION1_RAID 					-- "%s dies, you gain %d experience. (%s exp %s bonus, -%d raid penalty)"
	-- COMBATLOG_XPGAIN_EXHAUSTION2 						-- "%s dies, you gain %d experience. (%s exp %s bonus)"
	-- COMBATLOG_XPGAIN_EXHAUSTION2_GROUP 					-- "%s dies, you gain %d experience. (%s exp %s bonus, +%d group bonus)"
	-- COMBATLOG_XPGAIN_EXHAUSTION2_RAID 					-- "%s dies, you gain %d experience. (%s exp %s bonus, -%d raid penalty)"
	-- COMBATLOG_XPGAIN_EXHAUSTION4 						-- "%s dies, you gain %d experience. (%s exp %s penalty)"
	-- COMBATLOG_XPGAIN_EXHAUSTION4_GROUP 					-- "%s dies, you gain %d experience. (%s exp %s penalty, +%d group bonus)"
	-- COMBATLOG_XPGAIN_EXHAUSTION4_RAID 					-- "%s dies, you gain %d experience. (%s exp %s penalty, -%d raid penalty)"
	-- COMBATLOG_XPGAIN_EXHAUSTION5 						-- "%s dies, you gain %d experience. (%s exp %s penalty)"
	-- COMBATLOG_XPGAIN_EXHAUSTION5_GROUP 					-- "%s dies, you gain %d experience. (%s exp %s penalty, +%d group bonus)"
	-- COMBATLOG_XPGAIN_EXHAUSTION5_RAID 					-- "%s dies, you gain %d experience. (%s exp %s penalty, -%d raid penalty)"

	-- Same applies here as above. A single pattern is enough.
	UNNAMED = COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED, -- "You gain %d experience."
	-- COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_GROUP 			-- "You gain %d experience. (+%d group bonus)"
	-- COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED_RAID 			-- "You gain %d experience. (-%d raid penalty)"
	-- COMBATLOG_XPGAIN_QUEST 								-- "You gain %d experience. (%s exp %s bonus)"

	-- "Congratulations, you have reached |cffFF4E00|Hlevelup:%d:LEVEL_UP_TYPE_CHARACTER|h[Level %d]|h|r!"
	LEVEL_UP = LEVEL_UP,

	-- Level-up detail lines.
	LEVEL_UP_HEALTH = LEVEL_UP_HEALTH, -- "You have gained %d hit points."
	LEVEL_UP_HEALTH_MANA = LEVEL_UP_HEALTH_MANA, -- "You have gained %d hit points and %d mana."
	LEVEL_UP_STAT = LEVEL_UP_STAT, -- "Your %s increases by %d."
	LEVEL_UP_CHAR_POINTS = LEVEL_UP_CHAR_POINTS, -- "You have gained %d talent point."
	TALENT_POINTS = TALENT_POINTS or TALENTS or "Talents",
}

-- Search Pattern Cache (self-populating via ns.MakePattern on first lookup).
local P = ns.MakePatternCache()

-- Safe pattern match that tolerates a nil pattern (shared helper).
local safeMatch = ns.SafeMatch

-- Special handling for LEVEL_UP. We capture the entire colored, clickable level link.
if G.LEVEL_UP then
	P[G.LEVEL_UP] = string_gsub(G.LEVEL_UP, "(|.+|r)", "(.+)")
end

local fix = function(...)
	local string, number, n
	for i, v in next, { ... } do
		n = tonumber(v)
		if n and (n > 0) then
			number = n
		elseif not n then
			string = v
		end
	end
	return number, string
end

-- Reformat the level-up detail lines:
--   "You have gained 15 hit points."          -> "+ 15 HP"
--   "Your Strength increases by 1."           -> "+ 1 Strength"
--   "You have gained 1 talent point."         -> "+ 1 Talents"
-- Returns nil when the line is not one of them.
local levelupDetail = function(message)
	local hp = safeMatch(message, P[G.LEVEL_UP_HEALTH_MANA]) or safeMatch(message, P[G.LEVEL_UP_HEALTH])
	if hp then
		return string_format(ns.out.levelup_hp, tonumber(hp) or 0)
	end

	local a, b = safeMatch(message, P[G.LEVEL_UP_STAT])
	if a and b then
		-- Localized strings may put the amount first.
		local amount, stat = tonumber(b), a
		if not amount then
			amount, stat = tonumber(a), b
		end
		if amount then
			return string_format(ns.out.levelup_stat, amount, stat)
		end
	end

	local points = safeMatch(message, P[G.LEVEL_UP_CHAR_POINTS])
	if points and tonumber(points) then
		return string_format(ns.out.levelup_talent, tonumber(points), G.TALENT_POINTS)
	end
end

Module.OnChatEvent = function(self, chatFrame, event, message, author, ...)
	if type(message) ~= "string" then
		return
	end

	local value, source

	if event == "CHAT_MSG_COMBAT_XP_GAIN" then
		value, source = fix(safeMatch(message, P[G.NAMED]))
		if value then
			return false, string_format(ns.out.xp_named, value, G.XP, source), author, ...
		end

		value = safeMatch(message, P[G.UNNAMED])
		if value then
			-- Check if we should buffer for one-line quest rewards
			-- Only buffer unnamed XP (quest rewards), not named XP (mob kills)
			if ns.db and ns.db.oneLineQuestRewards and chatFrame then
				-- Use the highlight white (fafafa), NOT pure "|cffffffff": pure
				-- white is the Blizzard Priest class colour, so the ClassColors
				-- replacement (run on every AddMessage line) would remap it to the
				-- custom Priest tint and the XP would show gray-blue. Mob XP uses
				-- the same highlight colour, so this keeps them consistent.
				local rewardText = string_format("|cfffafafa%s|r |cfffafafa%s|r", value, G.XP)
				if ns:AddQuestReward(chatFrame, "xp", rewardText) then
					return true -- Suppress, will be output with combined rewards
				end
			end
			return false, string_format(ns.out.xp_unnamed, value, G.XP), author, ...
		end
	elseif event == "CHAT_MSG_SYSTEM" then
		-- Area discovery
		value, source = fix(safeMatch(message, P[G.ERR_ZONE_EXPLORED_XP]))
		if value then
			return false, string_format(ns.out.xp_named, value, G.XP, source), author, ...
		end

		-- Level up (retail format with clickable link)
		if G.LEVEL_UP then
			value = safeMatch(message, P[G.LEVEL_UP])
			if value then
				value = ns.StripBrackets(value)
				return false, string_format(ns.out.xp_levelup, value), author, ...
			end
		end

		-- Level-up detail lines (localized through the client's own strings).
		local detail = levelupDetail(message)
		if detail then
			return false, detail, author, ...
		end

		-- Quest Completed (also reported in the XP channel)
		if safeMatch(message, P[G.ERR_QUEST_REWARD_EXP_I]) then
			return true
		end
	end
end

local onChatEventProxy = function(...)
	return Module:OnChatEvent(...)
end

Module.OnEnable = function(self)
	self:RegisterMessageEventFilter("CHAT_MSG_COMBAT_XP_GAIN", onChatEventProxy)
	self:RegisterMessageEventFilter("CHAT_MSG_SYSTEM", onChatEventProxy)
end

Module.OnDisable = function(self)
	self:UnregisterMessageEventFilter("CHAT_MSG_COMBAT_XP_GAIN", onChatEventProxy)
	self:UnregisterMessageEventFilter("CHAT_MSG_SYSTEM", onChatEventProxy)
end
