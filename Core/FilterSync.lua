--[[
	FilterSync.lua

	Sync between Limpid filters and Blizzard's chat message categories
	(Chat Settings UI).

	Forever port notes:
	  * The ChatFrame_AddMessageGroup globals are gone; message groups are
	    methods of the chat frame (ChatFrame1:AddMessageGroup).
	  * Limpid -> Blizzard: only when the USER turns a filter on in /limpid
	    (never at login), and only ever ADDING a category, never removing one.
	  * Blizzard -> Limpid: read through secure post-hooks on the primary
	    chat frame, so Blizzard's own code is never replaced or tainted.
]]

local _, ns = ...

local FilterSync = {}
ns.FilterSync = FilterSync

-- Mapping: Limpid filter key -> Blizzard message group(s).
-- CONTRACT: this sync only ever ADDS (enables) a message group, never removes
-- one. Limpid reformats messages; it must never hide a whole Blizzard chat
-- category.
local CC_TO_BLIZZARD = {
	experience = { "COMBAT_XP_GAIN" },
	honor = { "COMBAT_HONOR_GAIN" },
	reputation = { "COMBAT_FACTION_CHANGE" },
	loot = { "LOOT", "MONEY", "CURRENCY" },
	tradeskills = { "SKILL", "TRADESKILLS" },
	opening = { "OPENING" },
	petinfo = { "PET_INFO" },
	miscinfo = { "COMBAT_MISC_INFO" },
	systemmessages = { "SYSTEM" },
	achievements = { "ACHIEVEMENT", "GUILD_ACHIEVEMENT" },
	bossmessages = { "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER" },
}

-- Reverse mapping: Blizzard message group -> Limpid filter key
local BLIZZARD_TO_CC = {}
for ccFilter, blizzGroups in pairs(CC_TO_BLIZZARD) do
	for _, group in ipairs(blizzGroups) do
		BLIZZARD_TO_CC[group] = ccFilter
	end
end

-- Track if we're currently syncing to prevent infinite loops
local isSyncing = false

-- Get the primary chat frame (ChatFrame1)
local function GetPrimaryChatFrame()
	return ChatFrame1
end

-- Enable a message group for the primary chat frame
local function EnableMessageGroup(group)
	local chatFrame = GetPrimaryChatFrame()
	if not chatFrame or not chatFrame.AddMessageGroup then
		return
	end
	-- Unknown groups are ignored by Blizzard, but a duplicate add would insert
	-- the group twice into the frame's list, so check first.
	if ChatTypeGroup and not ChatTypeGroup[group] then
		return
	end
	if chatFrame.ContainsMessageGroup and chatFrame:ContainsMessageGroup(group) then
		return
	end
	chatFrame:AddMessageGroup(group)
end

-- Sync a Limpid filter state TO Blizzard's settings.
-- ENABLE-ONLY: we never remove a group here.
function FilterSync:SyncToBlizzard(filterKey, enabled)
	if not enabled then
		return
	end

	if isSyncing then
		return
	end

	local blizzGroups = CC_TO_BLIZZARD[filterKey]
	if not blizzGroups then
		return
	end

	isSyncing = true
	for _, group in ipairs(blizzGroups) do
		pcall(EnableMessageGroup, group)
	end
	isSyncing = false
end

-- Sync a Blizzard message group change TO Limpid
function FilterSync:SyncFromBlizzard(group, enabled)
	if isSyncing then
		return
	end
	if type(group) ~= "string" then
		return
	end

	local ccFilter = BLIZZARD_TO_CC[group]
	if not ccFilter then
		return
	end

	-- Only update if different from current state
	if ns.db and ns.db.filters and ns.db.filters[ccFilter] ~= nil then
		if ns.db.filters[ccFilter] ~= enabled then
			isSyncing = true

			ns.db.filters[ccFilter] = enabled

			-- Update module state
			local moduleName = ns:GetModuleNameFromFilter(ccFilter)
			local module = ns:GetModule(moduleName, true)
			if module then
				if enabled and not module:IsEnabled() then
					module:Enable()
				elseif not enabled and module:IsEnabled() then
					module:Disable()
				end
			end

			isSyncing = false
		end
	end
end

-- Watch Blizzard's message group changes with secure post-hooks on the
-- primary chat frame itself (the methods come from ChatFrameMixin).
function FilterSync:HookBlizzardFunctions()
	if self.hooked then
		return
	end
	local chatFrame = GetPrimaryChatFrame()
	if not chatFrame then
		return
	end
	self.hooked = true

	if chatFrame.AddMessageGroup then
		hooksecurefunc(chatFrame, "AddMessageGroup", function(_, group)
			FilterSync:SyncFromBlizzard(group, true)
		end)
	end

	if chatFrame.RemoveMessageGroup then
		hooksecurefunc(chatFrame, "RemoveMessageGroup", function(_, group)
			FilterSync:SyncFromBlizzard(group, false)
		end)
	end
end

-- Initialize sync system
function FilterSync:Initialize()
	self:HookBlizzardFunctions()
end

-- Expose sync function for Options.lua to call when filters change
ns.SyncFilterToBlizzard = function(filterKey, enabled)
	FilterSync:SyncToBlizzard(filterKey, enabled)
end
