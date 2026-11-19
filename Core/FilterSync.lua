--[[
	FilterSync.lua

	Keeps Limpid's filter checkboxes and the game's own chat categories
	(Chat Settings UI) in step.

	What a checkbox means
	  A Limpid filter that REFORMATS a category now also controls whether that
	  category is shown at all: unticking it removes the category from the chat
	  windows that were showing it, and ticking it again puts the category back
	  in exactly those windows. Unticking used to leave the raw Blizzard line in
	  chat, which read like the filter had simply failed.

	  Filters that already mean "hide this" when TICKED (Opening, Pet Info, Misc
	  Info, System Messages, Channel Notices) are deliberately absent from the
	  map below. Their modules drop the event while enabled, so touching their
	  category here would make the checkbox do the opposite of what it says.

	Forever port notes:
	  * The ChatFrame_AddMessageGroup globals are gone; message groups are
	    methods of the chat frame (ChatFrame1:AddMessageGroup).
	  * Blizzard -> Limpid: read through secure post-hooks on the primary
	    chat frame, so Blizzard's own code is never replaced or tainted.
	  * Nothing is synced at login. The game stores each window's categories
	    itself, so a category hidden in one session stays hidden without Limpid
	    having to re-apply anything.
]]

local _, ns = ...

local FilterSync = {}
ns.FilterSync = FilterSync

-- Mapping: Limpid filter key -> the Blizzard message group(s) it formats.
--
-- Only REFORMATTING filters belong here. MONEY is deliberately not part of
-- "loot": money lines are handled by an always-on module with no checkbox of
-- its own, so unticking Loot must not take them away.
local CC_TO_BLIZZARD = {
	experience = { "COMBAT_XP_GAIN" },
	honor = { "COMBAT_HONOR_GAIN" },
	reputation = { "COMBAT_FACTION_CHANGE" },
	loot = { "LOOT", "CURRENCY" },
	tradeskills = { "SKILL", "TRADESKILLS" },
	achievements = { "ACHIEVEMENT", "GUILD_ACHIEVEMENT" },
	bossmessages = { "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER" },
}

-- Reverse mapping: Blizzard message group -> Limpid filter key.
-- NOTE: several groups map to the SAME filter (LOOT and CURRENCY both back
-- "loot"), so this lookup alone must never decide the filter's new state
-- -- see AnyGroupEnabled below.
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

-- Run `fn(frame, index)` for every chat window the client has.
local function ForEachChatFrame(fn)
	local count = _G.NUM_CHAT_WINDOWS or 10
	for i = 1, count do
		local frame = _G["ChatFrame" .. i]
		if frame then
			fn(frame, i)
		end
	end
end

-- Is `group` a category this client actually has?
local function IsRealGroup(group)
	return (not ChatTypeGroup) or ChatTypeGroup[group] ~= nil
end

local function FrameShowsGroup(frame, group)
	return frame.ContainsMessageGroup and frame:ContainsMessageGroup(group)
end

-- Where the windows that were showing a category are remembered while it is
-- hidden, so ticking the filter again restores the user's layout instead of
-- dumping the category into the first window.
local function RememberStore()
	if not ns.db then
		return nil
	end
	ns.db.hiddenChatGroups = ns.db.hiddenChatGroups or {}
	return ns.db.hiddenChatGroups
end

-- Add a message group to the primary chat frame.
local function EnableMessageGroup(group)
	local chatFrame = GetPrimaryChatFrame()
	if not chatFrame or not chatFrame.AddMessageGroup then
		return
	end
	-- Unknown groups are ignored by Blizzard, but a duplicate add would insert
	-- the group twice into the frame's list, so check first.
	if not IsRealGroup(group) then
		return
	end
	if FrameShowsGroup(chatFrame, group) then
		return
	end
	chatFrame:AddMessageGroup(group)
end

-- Is ANY of the Blizzard categories backing `ccFilter` still shown in ANY chat
-- window?
--
-- Two things used to go wrong here. A Limpid filter can be backed by several
-- categories ("loot" covers LOOT and CURRENCY), and unticking just one of them
-- switched the whole filter off -- so unticking "Currency" in the game's chat
-- settings also killed loot formatting. And only the first window was
-- consulted, so moving a category to its own tab looked like switching it off.
--
-- Returns nil when the state can't be read, so the caller keeps its old
-- single-category behaviour instead of guessing.
local function AnyGroupEnabled(ccFilter)
	local primary = GetPrimaryChatFrame()
	local groups = CC_TO_BLIZZARD[ccFilter]
	if not primary or not primary.ContainsMessageGroup or not groups then
		return nil
	end

	local found = false
	for _, group in ipairs(groups) do
		-- Skip categories this client doesn't have: they can never be ticked,
		-- so they must not drag the filter down with them.
		if IsRealGroup(group) then
			ForEachChatFrame(function(frame)
				if FrameShowsGroup(frame, group) then
					found = true
				end
			end)
		end
	end
	return found
end

-- Take a category off every window that shows it, remembering which ones did.
local function HideGroups(filterKey)
	local groups = CC_TO_BLIZZARD[filterKey]
	if not groups then
		return
	end
	local store = RememberStore()

	for _, group in ipairs(groups) do
		if IsRealGroup(group) then
			local shownIn = {}
			ForEachChatFrame(function(frame, index)
				if FrameShowsGroup(frame, group) then
					shownIn[#shownIn + 1] = index
					if frame.RemoveMessageGroup then
						frame:RemoveMessageGroup(group)
					end
				end
			end)
			-- Only overwrite the memory when something was actually showing the
			-- category. Recording an empty list would throw away the layout
			-- remembered earlier and send the category back to the first window
			-- when the filter is switched on again.
			if store and #shownIn > 0 then
				store[group] = shownIn
			end
		end
	end
end

-- Put a category back where it was before Limpid hid it.
local function ShowGroups(filterKey)
	local groups = CC_TO_BLIZZARD[filterKey]
	if not groups then
		return
	end
	local store = RememberStore()

	for _, group in ipairs(groups) do
		if IsRealGroup(group) then
			local remembered = store and store[group]
			if remembered and #remembered > 0 then
				for _, index in ipairs(remembered) do
					local frame = _G["ChatFrame" .. index]
					if frame and frame.AddMessageGroup and not FrameShowsGroup(frame, group) then
						frame:AddMessageGroup(group)
					end
				end
			else
				-- Limpid never hid this one. Only step in when NO window shows
				-- the category at all, so a filter the user just switched on has
				-- something to format -- without overruling a deliberate layout.
				local shownSomewhere = false
				ForEachChatFrame(function(frame)
					if FrameShowsGroup(frame, group) then
						shownSomewhere = true
					end
				end)
				if not shownSomewhere then
					EnableMessageGroup(group)
				end
			end
			if store then
				store[group] = nil
			end
		end
	end
end

-- Apply a Limpid filter's state to the game's chat categories.
function FilterSync:SyncToBlizzard(filterKey, enabled)
	if isSyncing then
		return
	end
	if not CC_TO_BLIZZARD[filterKey] then
		return
	end

	isSyncing = true
	if enabled then
		pcall(ShowGroups, filterKey)
	else
		pcall(HideGroups, filterKey)
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

	-- This runs from a POST-hook, so the frame already reflects the change:
	-- ask it whether any backing category survives instead of trusting the
	-- single one that just moved.
	local anyEnabled = AnyGroupEnabled(ccFilter)
	if anyEnabled ~= nil then
		enabled = anyEnabled
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

-- Make the saved filter states true on this character.
--
-- Limpid's settings are account-wide, but the game stores each window's chat
-- categories PER CHARACTER. Without this pass, a filter unticked on one
-- character left its category showing on every other one: the box said hidden
-- and the raw lines kept arriving.
--
-- Only hiding is applied. Switching a category back on is the user's doing, and
-- doing it here would override a per-character layout nobody asked us to touch.
-- Deferred, because the client restores each window's categories during login.
function FilterSync:ApplyFilterStates()
	if not (ns.db and ns.db.filters) then
		return
	end
	isSyncing = true
	for filterKey in pairs(CC_TO_BLIZZARD) do
		if ns.db.filters[filterKey] == false then
			pcall(HideGroups, filterKey)
		end
	end
	isSyncing = false
end

-- Initialize sync system
function FilterSync:Initialize()
	self:HookBlizzardFunctions()

	local timer = ns.Timer or _G.C_Timer
	if timer and timer.After then
		timer.After(3, function()
			FilterSync:ApplyFilterStates()
		end)
	else
		self:ApplyFilterStates()
	end
end

-- True when unticking this filter also hides its category from chat. Used by
-- the options screen to say so in the tooltip.
ns.FilterHidesCategory = function(filterKey)
	return CC_TO_BLIZZARD[filterKey] ~= nil
end

-- Expose sync function for Options.lua to call when filters change
ns.SyncFilterToBlizzard = function(filterKey, enabled)
	FilterSync:SyncToBlizzard(filterKey, enabled)
end
