local _, ns = ...

-- Demo mode
-- "/lpd" shows everything at once, for screenshots or a quick look: a set of
-- sample chat lines in every style, the tabs, and a filled loot list. All of
-- it stays on screen until "/lpd" is typed again, which restores the settings
-- it changed. Nothing here touches the game: the lines are only printed.

local ipairs = ipairs
local pcall = pcall
local string_format = string.format
local type = type

local active = false
local saved -- chat window settings to restore

local FALLBACK_ITEMS = { 6948, 2589, 2318, 4306, 2592, 2447 }

-- Up to `count` distinct item links: what's in the bags first, then a few
-- common items if the client already knows them.
ns.SampleItemLinks = function(count)
	local links, seen = {}, {}
	local function add(link)
		if type(link) == "string" and not ns.IsSecret(link) and not seen[link] and #links < count then
			seen[link] = true
			links[#links + 1] = link
		end
	end
	local container = _G.C_Container
	if container and container.GetContainerNumSlots and container.GetContainerItemLink then
		for bag = 0, 4 do
			local ok, slots = pcall(container.GetContainerNumSlots, bag)
			for slot = 1, (ok and type(slots) == "number") and slots or 0 do
				add(container.GetContainerItemLink(bag, slot))
			end
		end
	end
	local getInfo = _G.C_Item and _G.C_Item.GetItemInfo
	if getInfo then
		for _, itemID in ipairs(FALLBACK_ITEMS) do
			if #links >= count then
				break
			end
			local ok, _, link = pcall(getInfo, itemID)
			if ok then
				add(link)
			end
		end
	end
	return links
end

local function QuestTitle()
	local questLog = _G.C_QuestLog
	if questLog and questLog.GetNumQuestLogEntries and questLog.GetInfo then
		local ok, entries = pcall(questLog.GetNumQuestLogEntries)
		if ok and type(entries) == "number" then
			for index = 1, entries do
				local okInfo, info = pcall(questLog.GetInfo, index)
				if okInfo and type(info) == "table" and not info.isHeader and type(info.title) == "string" and not ns.IsSecret(info.title) then
					return info.title
				end
			end
		end
	end
	return "The Lost Tools"
end

local function PrintSamples()
	local frame = _G.DEFAULT_CHAT_FRAME or _G.ChatFrame1
	local out = ns.out
	if not frame or not out then
		return
	end
	local function line(template, chatType, ...)
		if type(template) == "string" then
			local ok, text = pcall(string_format, template, ...)
			if ok then
				ns.PrintToFrame(frame, text, chatType)
			end
		end
	end

	local links = ns.SampleItemLinks(3)
	local function item(index)
		local link = links[index] or links[1]
		return link and ns.StripBrackets(ns.NormalizeLinks(link)) or "Linen Cloth"
	end
	local quest = QuestTitle()
	local name = _G.UnitName and _G.UnitName("player")
	if type(name) ~= "string" or ns.IsSecret(name) then
		name = "Limpid"
	end
	local _, faction = pcall(function()
		local _, localized = _G.UnitFactionGroup("player")
		return localized
	end)
	if type(faction) ~= "string" then
		faction = "Azeroth"
	end

	line(out.quest_accepted, "SYSTEM", _G.CALENDAR_STATUS_ACCEPTED or "Accepted", quest)
	line(out.item_single, "LOOT", item(1))
	line(out.item_multiple, "LOOT", item(2), 3)
	if ns.FormatMoney then
		line(out.money, "MONEY", ns.FormatMoney(1, 89, 98))
	end
	line(out.xp_unnamed, "COMBAT_XP_GAIN", 2375, _G.XP or "XP")
	line(out.standing, "COMBAT_FACTION_CHANGE", 41, _G.REPUTATION or "Reputation", faction)
	line(out.quest_complete, "SYSTEM", _G.COMPLETE or "Complete", quest)
	line(out.item_deficit, "LOOT", item(3))
	line(out.guild_online, "SYSTEM", name)
end

-- Keep the chat lines and tabs on screen while the demo runs.
local PINNED_KEYS = { "messagesAlwaysVisible", "tabsAlwaysVisible" }

local function SetChatPinned(on)
	local chatUI, constants = ns[1], ns[2]
	local profile = chatUI and chatUI.db and chatUI.db.profile
	local update = constants and constants.ACTIONS and constants.ACTIONS.UpdateConfig
	if not profile or not update or not chatUI.Dispatch then
		return
	end
	if on then
		saved = {}
		for _, key in ipairs(PINNED_KEYS) do
			saved[key] = profile[key]
			profile[key] = true
		end
	elseif saved then
		for _, key in ipairs(PINNED_KEYS) do
			profile[key] = saved[key]
		end
		saved = nil
	else
		return
	end
	for _, key in ipairs(PINNED_KEYS) do
		pcall(chatUI.Dispatch, chatUI, update(key, "Main"))
	end
end

ns.ToggleDemo = function()
	active = not active
	SetChatPinned(active)
	if active then
		PrintSamples()
	end
	if ns.LootPopup then
		ns.LootPopup:Demo(active)
	end
	print("|cffDFBA69Limpid|r: demo " .. (active and "|cff00ff00ON|r - /lpd" or "|cffff0000OFF|r"))
end

ns.IsDemoActive = function()
	return active
end

ns:RegisterChatCommand("lpd", function()
	ns.ToggleDemo()
end)
