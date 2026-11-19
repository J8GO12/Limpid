local Addon, ns = ...

ns = LibStub("AceAddon-3.0"):NewAddon(ns, Addon, "LibMoreEvents-1.0", "AceConsole-3.0", "AceHook-3.0")

local L = LibStub("AceLocale-3.0"):GetLocale(Addon)

-- GLOBALS: GetChatTypeIndex
-- WoW Forever (1.60 / interface 16001) port.

-- Lua API
local _G = _G
local ipairs = ipairs
local next = next
local setmetatable = setmetatable
local string_find = string.find
local string_format = string.format
local string_match = string.match
local string_gsub = string.gsub
local string_lower = string.lower
local string_upper = string.upper
local table_concat = table.concat
local table_insert = table.insert
local table_remove = table.remove
local type = type

-- These channels will be ignored by the general parsing.
-- This does not affect the chat event filters,
-- and is only meant to avoid normal chat messages
-- giving off false positives as system messages.
local ignoredIDs = {}
for _, index in ipairs({

	--"SYSTEM",
	"SAY",
	"PARTY",
	"RAID",
	"GUILD",
	"OFFICER",
	"YELL",
	"WHISPER",
	"SMART_WHISPER",
	"WHISPER_INFORM",
	"REPLY",
	"EMOTE",
	"TEXT_EMOTE",
	"MONSTER_SAY",
	"MONSTER_PARTY",
	"MONSTER_YELL",
	"MONSTER_WHISPER",
	"MONSTER_EMOTE",
	"CHANNEL",
	"CHANNEL_JOIN",
	"CHANNEL_LEAVE",
	"CHANNEL_LIST",
	"CHANNEL_NOTICE",
	"CHANNEL_NOTICE_USER",
	"TARGETICONS",
	"AFK",
	"DND",
	"IGNORED",
	--"SKILL",
	--"LOOT",
	--"CURRENCY",
	--"MONEY",
	--"OPENING",
	--"TRADESKILLS",
	"PET_INFO",
	"COMBAT_MISC_INFO",
	--"COMBAT_XP_GAIN",
	--"COMBAT_HONOR_GAIN",
	--"COMBAT_FACTION_CHANGE",
	"BG_SYSTEM_NEUTRAL",
	"BG_SYSTEM_ALLIANCE",
	"BG_SYSTEM_HORDE",
	"RAID_LEADER",
	"RAID_WARNING",
	"RAID_BOSS_WHISPER",
	"RAID_BOSS_EMOTE",
	"QUEST_BOSS_EMOTE",
	"FILTERED",
	"INSTANCE_CHAT",
	"INSTANCE_CHAT_LEADER",
	"RESTRICTED",
	"CHANNEL1",
	"CHANNEL2",
	"CHANNEL3",
	"CHANNEL4",
	"CHANNEL5",
	"CHANNEL6",
	"CHANNEL7",
	"CHANNEL8",
	"CHANNEL9",
	"CHANNEL10",
	"CHANNEL11",
	"CHANNEL12",
	"CHANNEL13",
	"CHANNEL14",
	"CHANNEL15",
	"CHANNEL16",
	"CHANNEL17",
	"CHANNEL18",
	"CHANNEL19",
	"CHANNEL20",
	"ACHIEVEMENT",
	"PARTY_LEADER",
	"BN_WHISPER",
	"BN_WHISPER_INFORM",
	"BN_ALERT",
	"BN_BROADCAST",
	"BN_BROADCAST_INFORM",
	"BN_INLINE_TOAST_ALERT",
	"BN_INLINE_TOAST_BROADCAST",
	"BN_INLINE_TOAST_BROADCAST_INFORM",
	"BN_WHISPER_PLAYER_OFFLINE",
	"COMMUNITIES_CHANNEL",
	"VOICE_TEXT",
}) do
	local id = GetChatTypeIndex(index)
	if id then
		ignoredIDs[id] = true
	end
end

-- Factory for a callable blacklist container. Invoking it runs `...` through
-- every registered predicate; the first truthy result means "drop this message".
-- Both the normal and the unconditional (ignoredIDs-bypassing) groups are built
-- from this so their iteration logic can never drift apart.
local function makeBlacklistSet()
	return setmetatable({}, {
		__call = function(self, ...)
			for _, func in next, self do
				if func(...) then
					return true
				end
			end
		end,
	})
end

local blacklist = makeBlacklistSet()
-- Unconditional blacklist: like `blacklist`, but consulted for EVERY message,
-- even those whose chatID is in `ignoredIDs`. Channel join/leave/change notices
-- are delivered with the channel's own (ignored) chatID, so the normal blacklist
-- never sees them; the ChannelJoin filter registers here so it can still drop them.
local specialblacklist = makeBlacklistSet()

-- Factory for a callable replacement-set container. Invoking the returned table
-- runs `msg` through every registered set, where a set is either a table of
-- { pattern, replacement } pairs or a function. Both the regular and the
-- special (blacklist-ignoring) groups are built from this, so their iteration
-- logic can never drift apart.
local function makeReplacementSet()
	return setmetatable({}, {
		__call = function(self, msg, ...)
			if not msg then
				return msg
			end

			for i, set in next, self do
				if type(set) == "table" then
					for k, data in ipairs(set) do
						if data[1] and data[2] and (string_match(msg, data[1])) then
							-- string_gsub handles function replacements by passing captures
							msg = string_gsub(msg, data[1], data[2])
						end
					end
				elseif type(set) == "function" then
					msg = set(msg, ...) or msg
				end
			end

			return msg, ...
		end,
	})
end

local replacements = makeReplacementSet()
local specialreplacements = makeReplacementSet()

local modulePrototype = {

	-- @input event <string>
	-- @input method <string,func>
	RegisterMessageEventFilter = function(self, event, method)
		local func = (type(method) == "string") and self[method]
		ns.AddMessageEventFilter(event, func or method)
	end,

	-- @input event <string>
	-- @input method <string,func>
	UnregisterMessageEventFilter = function(self, event, method)
		local func = (type(method) == "string") and self[method]
		ns.RemoveMessageEventFilter(event, func or method)
	end,

	-- @input set <table,func>
	RegisterBlacklistFilter = function(self, method)
		local func = (type(method) == "string") and self[method]
		ns:AddBlacklistMethod(func or method)
	end,

	-- @input set <table,func>
	UnregisterBlacklistFilter = function(self, method)
		local func = (type(method) == "string") and self[method]
		ns:RemoveBlacklistMethod(func or method)
	end,

	-- Like RegisterBlacklistFilter, but the predicate is consulted for EVERY
	-- message regardless of chatID (see ns.FilterMessage). Use for system notices
	-- whose chatID falls in the ignored set (e.g. channel join/leave/change
	-- notices, which carry the channel's own ignored chatID).
	-- @input set <table,func>
	RegisterUnconditionalBlacklistFilter = function(self, method)
		local func = (type(method) == "string") and self[method]
		ns:AddSpecialBlacklistMethod(func or method)
	end,

	-- @input set <table,func>
	UnregisterUnconditionalBlacklistFilter = function(self, method)
		local func = (type(method) == "string") and self[method]
		ns:RemoveSpecialBlacklistMethod(func or method)
	end,

	-- @input set <table,func>
	RegisterMessageReplacement = function(self, set, ignoreBlacklist)
		ns:AddReplacementSet(set, ignoreBlacklist)
	end,

	-- @input set <table,func>
	UnregisterMessageReplacement = function(self, set)
		ns:RemoveReplacementSet(set)
	end,
}

-- Setup the module defaults.
ns:SetDefaultModuleState(false)
ns:SetDefaultModulePrototype(modulePrototype)

-- Addon default settings.
local defaults = {
	channelNameMode = "initial", -- "initial" shows the first letter (e.g. "[G]"), "full" shows the whole name, "none" for number only
	groupChannelNameMode = "initial", -- "initial" shows the first letter (e.g. "[G]"), "full" shows the whole name
	channelNumber = true, -- prefix the channel display with its number, e.g. "1. "
	channelCapitalize = true, -- capitalize the channel name/initial
	capitalizeNames = true, -- capitalize the first letter of player names
	forceClassColors = true, -- force enable class colors for all chat types
	moneyPrettify = true, -- use spaces in large gold amounts (e.g. "1 234" instead of "1234")
	hideOtherCrafts = true, -- hide other players' "<name> creates <item>" craft broadcasts
	showStartupMessage = true, -- print "Use /limpid for settings" on addon load
	rawDebug = false, -- /limpiddebug chat raw/event capture (persists across /reload)
	oneLineQuestRewards = true, -- combine quest rewards (items, currency, xp) into one line
	showItemDestruction = true, -- show "- item" when destroying items
	showVendorSales = true, -- show "- item" when selling to vendors
	showTradeItems = false, -- show +/- lines for items exchanged in a player trade
	prettifyGuildStatus = true, -- prettify guild online/offline messages
	prettifyQuestStatus = true, -- prettify other players' quest status broadcasts
	highlightSound = false, -- play an alert sound when your own name is highlighted (requires the highlight filter)
	lootPopupDuration = 6, -- loot popup: seconds a line stays visible
	lootPopupMax = 8, -- loot popup: lines shown at once
	lootPopupScale = 1, -- loot popup: scale
	lootPopupFontSize = 0, -- loot popup: text size (0 = same as the chat)
	lootPopupMoney = true, -- loot popup: show looted coins
	lootPopupTotals = true, -- loot popup: show how many you now carry
	lootPopupGrowUp = true, -- loot popup: new lines push older ones upwards
	filters = {
		achievements = true,
		auctions = true,
		bossmessages = true,
		channels = true,
		channeljoin = false,
		experience = true,
		honor = true,
		loot = true,
		miscinfo = false,
		names = true,
		opening = false,
		petinfo = false,
		quests = true,
		reputation = true,
		spells = true,
		status = true,
		systemmessages = false,
		tradeskills = true,
		copyChat = true,
		highlight = false,
		lootPopup = true,
		clickInvite = true,
	},
}

-- Expose defaults for external reset functionality
ns.defaults = defaults

Limpid_DB = ns.CopyTable(defaults)

-- Reset Limpid settings to defaults and update module states
ns.ResetLimpidSettings = function(self)
	for key, value in next, defaults do
		if type(value) == "table" then
			Limpid_DB[key] = ns.CopyTable(value)
		else
			Limpid_DB[key] = value
		end
	end
	self.db = Limpid_DB

	-- Update module enable/disable states based on new filter values
	for setting, value in next, self.db.filters do
		local moduleName = self:GetModuleNameFromFilter(setting)
		local module = self:GetModule(moduleName, true)
		if module then
			if value and not module:IsEnabled() then
				module:Enable()
			elseif not value and module:IsEnabled() then
				module:Disable()
			end
		end
	end
end

ns.IsProtectedMessage = function(self, msg)
	if ns.IsSecret(msg) or not msg or msg == "" then
		return
	end
	if string_find(msg, "|Hquestie") then
		return true
	end
end

-- Run a message through Limpid's special replacements, blacklists and
-- replacements. Returns the cleaned message, or nil if the message was
-- blacklisted and should be dropped entirely.
-- This is pure (it doesn't render anything), so other display layers such as
-- the LimpidUI chat UI can reuse it to show identically formatted messages.
ns.FilterMessage = function(self, chatFrame, msg, r, g, b, chatID, ...)
	-- Forever: during chat-messaging lockdown (boss encounters etc.) the text is
	-- a "secret" value. It can be displayed but not inspected, so it passes
	-- through untouched.
	if ns.IsSecret(msg) then
		return msg
	end
	if type(msg) ~= "string" or msg == "" then
		return msg
	end
	-- The chat type id may be secret too; treat it as unknown.
	if ns.IsSecret(chatID) then
		chatID = nil
	end

	-- Item links use named quality colours ("|cnIQ4:") on this client; turn
	-- them into hex colour codes (Limpid's palette) before filtering.
	msg = ns.NormalizeLinks(msg)

	-- TODO:
	-- *Encode Questie links, parse encoded string, decode Questie link.
	--  This keeps their links uncorrupted while still parsing the line in full.
	if not ns:IsProtectedMessage(msg) then
		-- Unconditional blacklist: consulted for EVERY message, even those whose
		-- chatID is in ignoredIDs. Channel join/leave/change notices carry the
		-- channel's own (ignored) chatID, so the gated blacklist below never sees
		-- them. Run it BEFORE the replacements so a notice is dropped before the
		-- Channel Names filter reshapes (and, for "Changed Channel", strips) it.
		if next(specialblacklist) then
			if specialblacklist(chatFrame, msg, r, g, b, chatID, ...) then
				return nil
			end
		end

		-- Parse replacements that ignore the blacklists.
		if next(specialreplacements) then
			msg = specialreplacements(msg, r, g, b, chatID, ...)
		end

		-- Parse regular blacklists and replacements.
		if not (chatID and ignoredIDs[chatID]) then
			-- Completely filter out matches.
			if next(blacklist) then
				if blacklist(chatFrame, msg, r, g, b, chatID, ...) then
					return nil
				end
			end

			-- Return a modified string.
			if next(replacements) then
				msg = replacements(msg, r, g, b, chatID, ...)
			end
		end
	end

	return msg
end

-- NOTE (Forever port): the original replaced every chat frame's AddMessage
-- method with a filtered copy. On the modern client that taints Blizzard's
-- whole chat pipeline (and breaks when the text is secret), so it is gone.
-- The filtering above is applied by the LimpidUI display layer instead, from a
-- secure post-hook on AddMessage (see Components/UI/SlidingMessageFrame.lua);
-- the native chat frames are hidden and left completely untouched.

ns.AddBlacklistMethod = function(self, func)
	-- Make sure the function isn't in our database already.
	for _, infunc in next, blacklist do
		if infunc == func then
			return
		end
	end
	table_insert(blacklist, func)
end

ns.RemoveBlacklistMethod = function(self, func)
	for k = #blacklist, 1, -1 do
		if blacklist[k] == func then
			table_remove(blacklist, k)
			break
		end
	end
end

-- Unconditional (ignoredIDs-bypassing) blacklist registration. See the
-- specialblacklist note above and ns.FilterMessage.
ns.AddSpecialBlacklistMethod = function(self, func)
	for _, infunc in next, specialblacklist do
		if infunc == func then
			return
		end
	end
	table_insert(specialblacklist, func)
end

ns.RemoveSpecialBlacklistMethod = function(self, func)
	for k = #specialblacklist, 1, -1 do
		if specialblacklist[k] == func then
			table_remove(specialblacklist, k)
			break
		end
	end
end

ns.AddReplacementSet = function(self, set, ignoreBlacklist)
	local group = ignoreBlacklist and specialreplacements or replacements

	-- Make sure the replacement set hasn't already been added.
	for _, inset in next, group do
		if inset == set then
			return
		end
	end

	table_insert(group, set)
end

ns.RemoveReplacementSet = function(self, set)
	for k = #replacements, 1, -1 do
		if replacements[k] == set then
			table_remove(replacements, k)
			break
		end
	end
	for k = #specialreplacements, 1, -1 do
		if specialreplacements[k] == set then
			table_remove(specialreplacements, k)
			break
		end
	end
end

-- Convert a stored filter key (e.g. "achievements") to its
-- corresponding module name (e.g. "Achievements").
--
-- Module names are case-sensitive, and four of them are CamelCase while their
-- filter keys are all lower-case. Simply capitalizing the first letter turned
-- "bossmessages" into "Bossmessages", which matches no module -- so those four
-- filters could never be switched on. They are mapped explicitly here.
local moduleNameByFilter = {
	bossmessages = "BossMessages",
	miscinfo = "MiscInfo",
	petinfo = "PetInfo",
	systemmessages = "SystemMessages",
}
ns.GetModuleNameFromFilter = function(self, key)
	return moduleNameByFilter[key] or (string_gsub(key, "^%l", string_upper))
end

ns.UpgradeSettings = function(self)
	-- Has the db been upgraded?
	if not Limpid_DB.configversion or Limpid_DB.configversion < 2 then
		-- Work on a clone.
		local old = ns.CopyTable(Limpid_DB)

		-- Replace missing entries with the defaults
		for setting, value in next, defaults do
			if Limpid_DB[setting] == nil then
				Limpid_DB[setting] = value
			end
		end

		-- Parse the cloned db for outdated entries.
		for setting, value in next, old do
			-- Only parse old filter settings.
			local moduleName = string_match(setting, "DisableFilter:(.*)")
			if moduleName then
				-- Old settings are true when the filter is disabled,
				-- new settings are true when filter is enabled.
				-- The old setting naming scheme has also been replaced.
				Limpid_DB[setting] = nil
				Limpid_DB.filters[string_lower(moduleName)] = not value
			end
		end

		-- Replace missing filter settings with their defaults.
		for setting, value in next, defaults.filters do
			if Limpid_DB.filters[setting] == nil then
				Limpid_DB.filters[setting] = value
			end
		end

		-- Store the new settings version
		-- so we never have to do this again.
		Limpid_DB.configversion = 2
	end

	-- Always backfill any newly added default settings,
	-- so existing users get sane values for new options.
	for setting, value in next, defaults do
		if type(value) ~= "table" and Limpid_DB[setting] == nil then
			Limpid_DB[setting] = value
		end
	end
	if Limpid_DB.filters then
		for setting, value in next, defaults.filters do
			if Limpid_DB.filters[setting] == nil then
				Limpid_DB.filters[setting] = value
			end
		end
	end

	-- Return a more sane db.
	return Limpid_DB
end

-- Quest Reward Buffering System
-- When oneLineQuestRewards is enabled, collect items, currency, and XP
-- that fire in the same frame (e.g. quest turn-in) and output as one line.
-- Batching (per chat frame + next-frame flush) is handled by ns.CreateFrameBuffer.
local questRewardBuffer = ns.CreateFrameBuffer(function()
	return { items = {}, xp = nil, money = nil }
end, function(chatFrame, buf)
	-- Build the combined output
	local parts = {}

	-- Add items (already formatted with color and count)
	for _, itemText in ipairs(buf.items) do
		parts[#parts + 1] = itemText
	end

	-- Add money (already formatted)
	if buf.money then
		parts[#parts + 1] = buf.money
	end

	-- Add XP
	if buf.xp then
		parts[#parts + 1] = buf.xp
	end

	if #parts > 0 then
		local text = ns.out.quest_rewards_combined
		if text then
			text = string_format(text, table_concat(parts, ", "))
		else
			-- Fallback if output format not yet loaded
			text = "|cff00ff00+|r " .. table_concat(parts, ", ")
		end

		-- Match the colour these messages normally display with.
		ns.PrintToFrame(chatFrame, text, "LOOT")
	end
end)

-- Public API for modules to add rewards to the buffer
ns.AddQuestReward = function(self, chatFrame, rewardType, rewardText)
	if not self.db or not self.db.oneLineQuestRewards then
		return false -- Not buffering, let module handle normally
	end

	if not chatFrame or not chatFrame.AddMessage then
		return false
	end

	local buf = questRewardBuffer.Get(chatFrame)

	if rewardType == "item" then
		buf.items[#buf.items + 1] = rewardText
	elseif rewardType == "xp" then
		buf.xp = rewardText
	elseif rewardType == "money" then
		buf.money = rewardText
	else
		return false
	end

	-- Defer the combined flush to the next frame (idempotent per frame).
	questRewardBuffer.Schedule(chatFrame)

	return true -- Reward was buffered
end

-- Apply class colors to player names in every chat type.
-- Forever exposes this as a single CVar ("0" = always colour by class), so
-- there is no per-channel loop anymore.
--
-- The value found before Limpid forced it is remembered so the option can be
-- switched back OFF again: it used to be a one-way door, writing `false` to the
-- database while leaving the CVar forced forever.
local previousClassColorOverride

ns.ApplyClassColors = function(self)
	if GetCVar and SetCVar and GetCVar("chatClassColorOverride") ~= "0" then
		previousClassColorOverride = GetCVar("chatClassColorOverride")
		SetCVar("chatClassColorOverride", "0")
	end
end

-- Undo ApplyClassColors: restore what was there before, or the client's own
-- default when Limpid forced the CVar in an earlier session and has nothing
-- remembered. Does nothing if the CVar is no longer the forced value.
ns.RestoreClassColors = function(self)
	if not (GetCVar and SetCVar) then
		return
	end
	if GetCVar("chatClassColorOverride") ~= "0" then
		return
	end

	local restore = previousClassColorOverride
	if not restore and GetCVarDefault then
		restore = GetCVarDefault("chatClassColorOverride")
	end
	previousClassColorOverride = nil

	if restore and restore ~= "0" then
		SetCVar("chatClassColorOverride", restore)
	end
end

ns.OnInitialize = function(self)
	self.db = self:UpgradeSettings()

	-- Always enable the options menu module.
	self:GetModule("Options"):Enable()
end

ns.OnEnable = function(self)
	-- Enable modules.
	for setting, value in next, self.db.filters do
		local moduleName = self:GetModuleNameFromFilter(setting)
		local module = ns:GetModule(moduleName, true)
		if module then
			if value and not module:IsEnabled() then
				module:Enable()
			elseif not value and module:IsEnabled() then
				module:Disable()
			end
		end
	end

	-- Always enabled modules.
	self:GetModule("Money"):Enable()
	self:GetModule("ClassColors"):Enable()
	self:GetModule("QualityColors"):Enable()
	self:GetModule("Blacklist"):Enable()
	self:GetModule("Empty"):Enable()
	self:GetModule("VersionCheck"):Enable()

	-- Apply class colors to all chat types if enabled
	if self.db.forceClassColors then
		self:ApplyClassColors()
	end

	-- Initialize filter sync with Blizzard chat settings
	if ns.FilterSync and ns.FilterSync.Initialize then
		ns.FilterSync:Initialize()
	end

	-- Print startup message (delayed so it's visible after login spam)
	if self.db.showStartupMessage then
		C_Timer.After(2, function()
			print("|cffDFBA69Limpid|r: " .. string_format(L["Use %s for settings."], "|cffffd200/limpid|r"))
		end)
	end
end
