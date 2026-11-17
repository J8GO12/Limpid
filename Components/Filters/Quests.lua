local _, ns = ...

local Module = ns:NewModule("Quests")

-- GLOBALS: hooksecurefunc, AcceptQuest, GetQuestReward, GetTitleText

-- Lua API
local string_format = string.format
local string_match = string.match
local GetTime = GetTime

-- WoW Globals (keep as nil if missing - empty string patterns match everything!)
local G = {
	SET_COMPLETE = ERR_COMPLETED_TRANSMOG_SET_S, -- "You've completed the set %s."
	PUSH_ONQUEST = ERR_QUEST_PUSH_ONQUEST_S, -- "%s is already on that quest."
	PUSH_ALREADY_DONE = ERR_QUEST_PUSH_ALREADY_DONE_S, -- "%s has completed that quest."
	PUSH_INVALID = ERR_QUEST_PUSH_INVALID_S, -- "%s is not eligible for that quest."
	QUEST_ACCEPTED = ERR_QUEST_ACCEPTED_S, -- "Quest accepted: %s"
	QUEST_ALREADY_DONE = ERR_QUEST_ALREADY_DONE, -- "You have completed that quest."
	QUEST_ALREADY_DONE_DAILY = ERR_QUEST_ALREADY_DONE_DAILY, -- "You have completed that daily quest today."
	QUEST_FAILED_TOO_MANY_DAILY = ERR_QUEST_FAILED_TOO_MANY_DAILY_QUESTS_I, -- "You have already completed %d daily quests today"
	NO_DAILY_QUESTS_REMAINING = NO_DAILY_QUESTS_REMAINING, -- "You cannot complete any more daily quests today."
	QUEST_COMPLETE = ERR_QUEST_COMPLETE_S, -- "%s completed."
	ACCEPTED = CALENDAR_STATUS_ACCEPTED or "Accepted", -- "Accepted"
	COMPLETE = COMPLETE or "Complete", -- "Complete"
}

-- Convert a WoW global string to a search pattern
local makePattern = ns.MakePattern

-- Search Pattern Cache (self-populating via ns.MakePattern on first lookup).
local P = ns.MakePatternCache()

-- Safe pattern match that tolerates a nil pattern (shared helper).
local safeMatch = ns.SafeMatch

-- A real quest completion is ALWAYS the entire system line ("<name> completed."),
-- so we anchor the pattern to the whole message with ^...$. Without anchoring,
-- the greedy "(.+) completed." swallows any line that merely contains the word
-- "completed" and reformats them into a bogus "+ Complete: ..." line.
local QUEST_COMPLETE_ANCHORED = G.QUEST_COMPLETE and ("^" .. makePattern(G.QUEST_COMPLETE) .. "$")

-- If a real (server-sent) or a synthetic quest line was shown within this many
-- seconds, treat another as a duplicate (see synthetic accept/complete below).
local QUEST_DEDUP_WINDOW = 1.0
-- Print the synthetic line on the next frame (effectively instant). We no longer
-- wait for a real system message first; instead, on cores that DO send one, the
-- OnChatEvent filter suppresses it if it lands within QUEST_DEDUP_WINDOW after
-- our synthetic line -- so there's still never a duplicate.
local SYNTHETIC_QUEST_DELAY = 0

-- Timestamps of the last accept/complete line shown (real or synthetic).
Module.lastAcceptAt = 0
Module.lastCompleteAt = 0

Module.OnChatEvent = function(self, chatFrame, event, message, author, ...)
	if type(message) ~= "string" or ns:IsProtectedMessage(message) then
		return
	end

	-- Other players' quest-sharing status ("<name> is already on that quest.");
	-- class-colour the name and tidy the text.
	if ns.db == nil or ns.db.prettifyQuestStatus then
		local who = safeMatch(message, P[G.PUSH_ONQUEST])
		if who then
			return false, string_format(ns.out.quest_status_already, ns.GetClassColoredName(who)), author, ...
		end
		who = safeMatch(message, P[G.PUSH_ALREADY_DONE])
		if who then
			return false, string_format(ns.out.quest_status_completed, ns.GetClassColoredName(who)), author, ...
		end
		who = safeMatch(message, P[G.PUSH_INVALID])
		if who then
			return false, string_format(ns.out.quest_status_ineligible, ns.GetClassColoredName(who)), author, ...
		end
	end

	local name

	-- Adding completed transmog sets here,
	-- to make sure they don't fire as completed quests.
	name = safeMatch(message, P[G.SET_COMPLETE])
	if name then
		name = ns.StripBrackets(name)
		return false, string_format(ns.out.set_complete, G.COMPLETE, name), author, ...
	end

	name = safeMatch(message, P[G.QUEST_ACCEPTED])
	if name then
		-- A synthetic "Accepted" line was just shown for this quest -> drop the dup.
		if (GetTime() - self.lastAcceptAt) < QUEST_DEDUP_WINDOW then
			return true
		end
		self.lastAcceptAt = GetTime()
		name = ns.StripBrackets(name)
		return false, string_format(ns.out.quest_accepted, G.ACCEPTED, name), author, ...
	end

	-- Avoid false positives on quest completion.
	if
		not safeMatch(message, P[G.QUEST_ALREADY_DONE])
		and not safeMatch(message, P[G.QUEST_ALREADY_DONE_DAILY])
		and not safeMatch(message, P[G.QUEST_FAILED_TOO_MANY_DAILY])
		and not safeMatch(message, P[G.NO_DAILY_QUESTS_REMAINING])
	then
		name = QUEST_COMPLETE_ANCHORED and string_match(message, QUEST_COMPLETE_ANCHORED)
		if name then
			-- A synthetic "Complete" line was just shown for this quest -> drop the dup.
			if (GetTime() - self.lastCompleteAt) < QUEST_DEDUP_WINDOW then
				return true
			end
			self.lastCompleteAt = GetTime()
			name = ns.StripBrackets(name)
			return false, string_format(ns.out.quest_complete, G.COMPLETE, name), author, ...
		end
	end
end

local onChatEventProxy = function(...)
	return Module:OnChatEvent(...)
end

-- Safety net: if the server doesn't broadcast the ERR_QUEST_ACCEPTED_S
-- ("Quest accepted: <name>") or ERR_QUEST_COMPLETE_S ("<name> completed.")
-- system messages, synthesize the line from the actual accept/turn-in. A real
-- system message within the dedup window always wins (see timestamps above).
local schedule = function(delay, fn)
	C_Timer.After(delay, fn)
end

local printSynthetic = function(stampKey, template, label, title)
	-- A real server-sent line already showed within the window -> skip duplicate.
	if (GetTime() - (Module[stampKey] or 0)) < QUEST_DEDUP_WINDOW then
		return
	end
	Module[stampKey] = GetTime()
	ns.PrintToFrame(DEFAULT_CHAT_FRAME or ChatFrame1, string_format(template, label, title))
end

local onQuestAction = function(stampKey, template, label)
	if not Module:IsEnabled() then
		return
	end
	-- The quest frame is still shown while AcceptQuest/GetQuestReward run, so the
	-- title is valid here; capture it before the frame closes on a later frame.
	local title = GetTitleText and GetTitleText()
	if ns.IsSecret(title) or type(title) ~= "string" then
		return
	end
	title = ns.StripBrackets(title)
	if title == "" then
		return
	end
	schedule(SYNTHETIC_QUEST_DELAY, function()
		printSynthetic(stampKey, template, label, title)
	end)
end

Module.OnEnable = function(self)
	-- System messages only: applying this to player chat (channels, whispers)
	-- would rewrite anything a player types that happens to end in "completed.".
	self:RegisterMessageEventFilter("CHAT_MSG_SYSTEM", onChatEventProxy)

	-- Synthesize accept/complete lines on cores that don't broadcast them.
	-- hooksecurefunc is a post-hook (no taint) and cannot be removed, so install
	-- once and gate the body on Module:IsEnabled().
	if not self.questHooksInstalled then
		self.questHooksInstalled = true
		if type(AcceptQuest) == "function" then
			hooksecurefunc("AcceptQuest", function()
				onQuestAction("lastAcceptAt", ns.out.quest_accepted, G.ACCEPTED)
			end)
		end
		if type(GetQuestReward) == "function" then
			hooksecurefunc("GetQuestReward", function()
				onQuestAction("lastCompleteAt", ns.out.quest_complete, G.COMPLETE)
			end)
		end
	end
end

Module.OnDisable = function(self)
	self:UnregisterMessageEventFilter("CHAT_MSG_SYSTEM", onChatEventProxy)
end
