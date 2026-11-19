local _, ns = ...

local Module = ns:NewModule("Loot")

-- GLOBALS: MerchantFrame, ChatTypeInfo
-- GLOBALS: hooksecurefunc, C_Container, TakeInboxItem, GetInboxItem, GetInboxItemLink
-- GLOBALS: GetCursorInfo, CreateFrame, MAX_TRADABLE_ITEMS
-- GLOBALS: GetTradePlayerItemLink, GetTradePlayerItemInfo
-- GLOBALS: GetTradeTargetItemLink, GetTradeTargetItemInfo

-- Lua API
local ipairs = ipairs
local string_find = string.find
local string_format = string.format
local string_gsub = string.gsub
local string_match = string.match
local string_sub = string.sub
local table_insert = table.insert
local table_remove = table.remove
local tonumber = tonumber
local type = type

-- Forever prefixes group-loot lines with a clickable "[Loot]: " history link
-- ("|HlootHistory:%d|h[Loot]|h: You won: %s"). Strip it from the global string
-- so the remaining text can be matched anywhere in the line and the captures
-- stay (name,) item like the handlers expect.
local function roll(global)
	local str = _G[global]
	if type(str) ~= "string" then
		return nil
	end
	-- (Some locales put a -- possibly non-breaking -- space before the colon:
	-- "[Butin] : ...", hence "anything up to the first colon".)
	return (string_gsub(str, "^|HlootHistory:%%d|h.-|h[^:]*:%s*", ""))
end

-- WoW Globals (keep nil if missing - empty string patterns match everything!)
local G = {
	COMBATLOG_HONORAWARD = COMBATLOG_HONORAWARD, -- "You have been awarded %d Honor."
	COMBATLOG_HONORGAIN = COMBATLOG_HONORGAIN, -- "%s dies (Honorable Kill: %s). You gain %d Honor."
	COMBATLOG_HONORGAIN_NO_RANK = COMBATLOG_HONORGAIN_NO_RANK, -- "%s dies (Honorable Kill). You gain %d Honor."
	COMBATLOG_ARENAPOINTSAWARD = COMBATLOG_ARENAPOINTSAWARD, -- "You have been awarded %d arena points."

	-- Loot roll messages
	LOOT_ROLL_YOU_WON = roll("LOOT_ROLL_YOU_WON"), -- "You won: %s"
	LOOT_ROLL_WON = roll("LOOT_ROLL_WON"), -- "%s won: %s"
	LOOT_ROLL_PASSED_SELF = roll("LOOT_ROLL_PASSED_SELF"), -- "You passed on: %s"
	LOOT_ROLL_PASSED = roll("LOOT_ROLL_PASSED"), -- "%s passed on: %s"
	LOOT_ROLL_PASSED_AUTO = roll("LOOT_ROLL_PASSED_AUTO"), -- "%s automatically passed on: %s because ..."
	LOOT_ROLL_PASSED_SELF_AUTO = roll("LOOT_ROLL_PASSED_SELF_AUTO"), -- "You automatically passed on: %s because ..."
	LOOT_ROLL_GREED_SELF = roll("LOOT_ROLL_GREED_SELF"), -- "You have selected Greed for: %s"
	LOOT_ROLL_GREED = roll("LOOT_ROLL_GREED"), -- "%s has selected Greed for: %s"
	LOOT_ROLL_NEED_SELF = roll("LOOT_ROLL_NEED_SELF"), -- "You have selected Need for: %s"
	LOOT_ROLL_NEED = roll("LOOT_ROLL_NEED"), -- "%s has selected Need for: %s"
	LOOT_ROLL_DISENCHANT_SELF = roll("LOOT_ROLL_DISENCHANT_SELF"), -- "You have selected Disenchant for: %s"
	LOOT_ROLL_DISENCHANT = roll("LOOT_ROLL_DISENCHANT"), -- "%s has selected Disenchant for: %s"
	LOOT_ROLL_ALL_PASSED = roll("LOOT_ROLL_ALL_PASSED"), -- "Everyone passed on: %s"

	-- "<action> Roll - %d for %s by %s" result lines.
	LOOT_ROLL_ROLLED_NEED = roll("LOOT_ROLL_ROLLED_NEED"),
	LOOT_ROLL_ROLLED_GREED = roll("LOOT_ROLL_ROLLED_GREED"),
	LOOT_ROLL_ROLLED_DE = roll("LOOT_ROLL_ROLLED_DE"),
	LOOT_ROLL_ROLLED_TRANSMOG = roll("LOOT_ROLL_ROLLED_TRANSMOG"),

	-- "%s has been added to your appearance collection."
	LEARN_TRANSMOG = ERR_LEARN_TRANSMOG_S,
}

-- Convert a WoW global string to a search pattern
local makePattern = ns.MakePattern

-- Search Pattern Cache (self-populating via ns.MakePattern on first lookup).
local P = ns.MakePatternCache()

-- Safe pattern match that tolerates a nil pattern (shared helper).
local safeMatch = ns.SafeMatch

-- Format a buffered quest-reward item's count as " (N)": the brackets stay white
-- (fafafa -- NOT pure "|cffffffff", which the Priest class-colour replacement
-- would recolour) while the number inherits the item's own quality colour, taken
-- from the leading |cAARRGGBB of the item link. Falls back to white if the item
-- carries no colour code.
local WHITE_CODE = "|cfffafafa"
local formatRewardCount = function(item, count)
	local color = string_match(item, "^|c(%x%x%x%x%x%x%x%x)")
	local numCode = color and ("|c" .. color) or WHITE_CODE
	return string_format("%s %s(%s%d%s)|r", item, WHITE_CODE, numCode, count, WHITE_CODE)
end

-- Loot roll lines, evaluated in order. "self" entries capture only the item;
-- "other" entries capture the player name + item. The output arg order for
-- "other" lines varies (the won line is name-first; the rest are item-first),
-- so it's flagged per entry. Replaces ~12 near-identical match/format blocks.
local ROLL_ACTIONS = {
	{ pattern = G.LOOT_ROLL_YOU_WON, kind = "self", out = "roll_won_self" },
	{ pattern = G.LOOT_ROLL_WON, kind = "other", out = "roll_won_other", nameFirst = true },
	{ pattern = G.LOOT_ROLL_NEED_SELF, kind = "self", out = "roll_need_self" },
	{ pattern = G.LOOT_ROLL_NEED, kind = "other", out = "roll_need_other" },
	{ pattern = G.LOOT_ROLL_GREED_SELF, kind = "self", out = "roll_greed_self" },
	{ pattern = G.LOOT_ROLL_GREED, kind = "other", out = "roll_greed_other" },
	{ pattern = G.LOOT_ROLL_DISENCHANT_SELF, kind = "self", out = "roll_de_self" },
	{ pattern = G.LOOT_ROLL_DISENCHANT, kind = "other", out = "roll_de_other" },
	{ pattern = G.LOOT_ROLL_PASSED_SELF, kind = "self", out = "roll_pass_self" },
	{ pattern = G.LOOT_ROLL_PASSED, kind = "other", out = "roll_pass_other" },
	{ pattern = G.LOOT_ROLL_PASSED_SELF_AUTO, kind = "self", out = "roll_pass_self" },
	{ pattern = G.LOOT_ROLL_PASSED_AUTO, kind = "other", out = "roll_pass_other" },
}

-- "<action> Roll - <roll> for <item> by <name>" result lines.
-- Captures: roll, item, name. Output arg order: item, roll, name.
local ROLL_RESULTS = {
	{ pattern = G.LOOT_ROLL_ROLLED_NEED, out = "roll_result_need" },
	{ pattern = G.LOOT_ROLL_ROLLED_GREED, out = "roll_result_greed" },
	{ pattern = G.LOOT_ROLL_ROLLED_DE, out = "roll_result_de" },
	{ pattern = G.LOOT_ROLL_ROLLED_TRANSMOG, out = "roll_result_transmog" },
}

-- Sort pattern captures by what they are: the capture holding a hyperlink is
-- the item, a purely numeric one is the roll, anything else is the player
-- name. Returns item, name, roll (each nil when absent).
local function classify(...)
	local item, name, rolled
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		if type(value) == "string" then
			if string_find(value, "|H", 1, true) then
				item = item or value
			elseif tonumber(value) then
				rolled = rolled or tonumber(value)
			elseif value ~= "" then
				name = name or value
			end
		end
	end
	return item, name, rolled
end

-- True if the text contains an item-like hyperlink.
local function hasItemLink(text)
	return string_find(text, "|Hitem:", 1, true)
		or string_find(text, "|Hbattlepet:", 1, true)
		or string_find(text, "|Hcurrency:", 1, true)
		or string_find(text, "|Hkeystone:", 1, true)
end

Module.OnAddMessage = function(self, chatFrame, msg, r, g, b, chatID, ...)
	-- Not sure any of these Honor entries are parsed, or even needed.

	-- "%s dies, honorable kill Rank: %s (%d Honor Points)"
	if safeMatch(msg, P[G.COMBATLOG_HONORGAIN]) then
		return true
	end

	-- "%s dies, honorable kill (%d Honor Points)"
	if safeMatch(msg, P[G.COMBATLOG_HONORGAIN_NO_RANK]) then
		return true
	end

	-- "You have been awarded %d honor points."
	if safeMatch(msg, P[G.COMBATLOG_HONORAWARD]) then
		return true
	end

	-- "You have been awarded %d arena points."
	if safeMatch(msg, P[G.COMBATLOG_ARENAPOINTSAWARD]) then
		return true
	end
end

Module.OnChatEvent = function(self, chatFrame, event, message, author, ...)
	if type(message) ~= "string" or ns:IsProtectedMessage(message) then
		return
	end

	-- Named quality colour tokens ("|cnIQ4:") -> hex colour codes, so the item
	-- patterns below (and the reformatted output) see a classic coloured link.
	message = ns.NormalizeLinks(message)

	-- NOTE: honor gains are no longer dropped here at the event level. The
	-- Honor filter reformats that same event, and whichever of the two filters
	-- happened to be registered first used to win -- so "+ honor" lines could
	-- vanish at random. Raw honor lines the Honor filter did NOT reformat are
	-- still hidden by the display-layer blacklist above (OnAddMessage).
	if event == "CHAT_MSG_CURRENCY" then
		for _i, pattern in ipairs(self.patterns) do
			-- We use the pattern only as an identifier, not for information.
			local matchedItem = string_match(message, pattern)
			if matchedItem then
				-- Note: Currencies don't appear to be the same format as this.
				-- The patterns above tend to fail on the number,
				-- so we do this ugly non-localized hack instead.
				-- |cffffffff|Hitem:itemID:::::|h[display name]|h|r
				local first, last = string_find(message, "|c(.+)|r")
				if first and last then
					-- Find the actual item name
					local item = string_sub(message, first, last)
					item = string_gsub(item, "[%[/%]]", "") -- kill brackets

					-- Parse our way to the item count
					local countString = string_sub(message, last + 1)
					local count = tonumber(string_match(countString, "(%d+)"))

					-- Check if we should buffer for one-line quest rewards
					if ns.db and ns.db.oneLineQuestRewards and chatFrame then
						local rewardText
						if count and (count > 1) then
							rewardText = formatRewardCount(item, count)
						else
							rewardText = item
						end
						if ns:AddQuestReward(chatFrame, "item", rewardText) then
							return true -- Suppress, will be output with combined rewards
						end
					end

					if count and (count > 1) then
						return false, string_format(ns.out.item_multiple, item, count), author, ...
					else
						return false, string_format(ns.out.item_single, item), author, ...
					end
				end
			end
		end
	elseif event == "CHAT_MSG_LOOT" then
		-- Drop the clickable "[Loot]: " history prefix group-loot lines start
		-- with, so the roll patterns below capture clean names and items.
		local body = string_gsub(message, "^|HlootHistory:%d+|h.-|h[^:]*:%s*", "")
		local isRollLine = body ~= message
		message = body

		-- "Everyone passed on: %s" (before the per-player "passed on" rules,
		-- which would otherwise read "Everyone" as a player name).
		local allPassed = safeMatch(message, P[G.LOOT_ROLL_ALL_PASSED])
		if allPassed then
			return false, string_format(ns.out.roll_all_passed, ns.StripBrackets(allPassed)), author, ...
		end

		-- Handle loot roll messages first (table-driven; see ROLL_ACTIONS).
		-- Captures are sorted by what they ARE (see classify), not by position,
		-- because localized strings reorder their arguments.
		for _, rule in ipairs(ROLL_ACTIONS) do
			local pat = P[rule.pattern]
			if pat then
				local item, name = classify(safeMatch(message, pat))
				if item then
					item = ns.StripBrackets(item)
					if rule.kind == "self" then
						return false, string_format(ns.out[rule.out], item), author, ...
					elseif name then
						if rule.nameFirst then
							return false, string_format(ns.out[rule.out], name, item), author, ...
						else
							return false, string_format(ns.out[rule.out], item, name), author, ...
						end
					end
				end
			end
		end

		-- "<action> Roll - <roll> for <item> by <name>" result lines.
		for _, rule in ipairs(ROLL_RESULTS) do
			local item, name, rolled = classify(safeMatch(message, P[rule.pattern]))
			if item and name and rolled then
				return false, string_format(ns.out[rule.out], ns.StripBrackets(item), rolled, name), author, ...
			end
		end

		-- Any other group-loot line keeps its text but loses the prefix.
		if isRollLine then
			return false, message, author, ...
		end

		-- Handle regular loot patterns
		for _idx, pattern in ipairs(self.patterns) do
			-- We use the pattern only as an identifier, not for information.
			local results = { string_match(message, pattern) }
			if #results > 0 then
				local parsedItem, parsedCount, parsedName
				for ri, rj in ipairs(results) do
					local k = tonumber(rj)
					if k then
						table_remove(results, ri)
						parsedCount = k
						break
					end
				end

				if #results == 2 then
					for ri, rj in ipairs(results) do
						if hasItemLink(rj) then
							parsedItem = table_remove(results, ri)
							parsedItem = string_gsub(parsedItem, "[%[/%]]", "") -- kill brackets
							break
						end
					end
					parsedName = string_gsub(results[1], "[%[/%]]", "")
				elseif #results == 1 then
					parsedItem = string_gsub(results[1], "[%[/%]]", "") -- kill brackets
				end

				if parsedItem then
					-- Self-received items (no name) can be buffered for one-line output
					if (not parsedName) and (ns.db and ns.db.oneLineQuestRewards and chatFrame) then
						local rewardText
						if parsedCount and (parsedCount > 1) then
							rewardText = formatRewardCount(parsedItem, parsedCount)
						else
							rewardText = parsedItem
						end
						if ns:AddQuestReward(chatFrame, "item", rewardText) then
							return true -- Suppress, will be output with combined rewards
						end
					end

					if parsedCount and (parsedCount > 1) then
						if parsedName then
							return false,
								string_format(ns.out.item_multiple_other, parsedName, parsedItem, parsedCount),
								author,
								...
						else
							return false, string_format(ns.out.item_multiple, parsedItem, parsedCount), author, ...
						end
					else
						if parsedName then
							return false, string_format(ns.out.item_single_other, parsedName, parsedItem), author, ...
						else
							return false, string_format(ns.out.item_single, parsedItem), author, ...
						end
					end
				end
			end
		end
	elseif event == "CHAT_MSG_SYSTEM" then
		-- "<item> has been added to your appearance collection."
		local appearance = safeMatch(message, P[G.LEARN_TRANSMOG])
		if appearance then
			return false, string_format(ns.out.appearance_added, ns.StripBrackets(appearance)), author, ...
		end
	end
end

Module.OnInitialize = function(self)
	self.patterns = {}

	for i, global in ipairs({

		-- Order matters: every "...x%d" (multiple) variant must come BEFORE its
		-- single-item twin, otherwise the single pattern swallows the count.

		-- These all return item, and optionally an item count.
		"LOOT_ITEM_CREATED_SELF_MULTIPLE", -- "You create: %sx%d."
		"LOOT_ITEM_CREATED_SELF", -- "You create: %s."
		"LOOT_ITEM_SELF_MULTIPLE", -- "You receive loot: %sx%d"
		"LOOT_ITEM_SELF", -- "You receive loot: %s"
		"LOOT_ITEM_PUSHED_SELF_MULTIPLE", -- "You receive item: %sx%d"
		"LOOT_ITEM_PUSHED_SELF", -- "You receive item: %s"
		"LOOT_ITEM_REFUND_MULTIPLE", -- "You are refunded: %sx%d."
		"LOOT_ITEM_REFUND", -- "You are refunded: %s."
		"CURRENCY_GAINED_MULTIPLE_BONUS", -- "You receive currency: %sx%d (Bonus Objective)"
		"CURRENCY_GAINED_MULTIPLE", -- "You receive currency: %sx%d"
		"CURRENCY_GAINED", -- "You receive currency: %s"

		-- These apply to other players and will include player NAMES, not always links.
		"LOOT_ITEM_BONUS_ROLL_MULTIPLE", -- "%s receives bonus loot: %sx%d."
		"LOOT_ITEM_BONUS_ROLL", -- "%s receives bonus loot: %s."
		"LOOT_ITEM_MULTIPLE", -- "%s receives loot: %sx%d."
		"LOOT_ITEM", -- "%s receives loot: %s."
		"LOOT_ITEM_PUSHED_MULTIPLE", -- "%s receives item: %sx%d."
		"LOOT_ITEM_PUSHED", -- "%s receives item: %s."

		-- Don't filter these here,
		-- they are pure text for both names and items!
		--"CREATED_ITEM", 							-- "%s creates: %s."
		--"CREATED_ITEM_MULTIPLE", 					-- "%s creates: %sx%d."
	}) do
		-- Always check if the global exists,
		-- as a lot of these strings and filters
		-- do not apply to the classic clients.
		local msg = _G[global]
		if msg then
			table_insert(self.patterns, makePattern(msg))
		end
	end

end

-- Selling an item to a vendor generates no chat message of its own -- only the
-- coin gain -- so the bag side of the trade was invisible. Buying shows
-- "+ item" / "- money", but selling only showed "+ money". Mirror it: emit a
-- matching "- item" deficit line when the player sells.
Module.ReportItemSold = function(self, link, count)
	if not link then
		return
	end

	-- Match the loot styling: strip the [] from the link (keeps the |H..|h
	-- hyperlink + quality colour so the line stays clickable and coloured).
	local item = ns.StripBrackets(ns.NormalizeLinks(link))

	local msg
	if count and count > 1 then
		msg = string_format(ns.out.item_deficit_multiple, item, count)
	else
		msg = string_format(ns.out.item_deficit, item)
	end

	ns.PrintToChatType(msg, "LOOT")
end

-- Taking an item from the mailbox produces no loot chat message, so the
-- "+ item" line you get from looting never appeared for mail. A secure
-- post-hook on the mail-take function emits a matching "+ item" line. The
-- cached attachment is still readable in the post-hook (not cleared until the
-- server's MAIL_INBOX_UPDATE), so we read it there.
Module.ReportMailItem = function(self, mailID, attachIndex)
	local link = GetInboxItemLink and GetInboxItemLink(mailID, attachIndex)
	if not link then
		return
	end

	-- Modern return order: name, itemID, texture, count, quality, canUse.
	local _, _, _, count = GetInboxItem(mailID, attachIndex)

	-- Strip the [] from the link (keeps the |H hyperlink + quality colour).
	local item = ns.StripBrackets(ns.NormalizeLinks(link))

	local msg
	if count and count > 1 then
		msg = string_format(ns.out.item_multiple, item, count)
	else
		msg = string_format(ns.out.item_single, item)
	end

	ns.PrintToChatType(msg, "LOOT")
end

-- Trades emit no loot line, so mirror mail/vendor: "+ item" received, "- item" given.
Module.ReportTradeItem = function(self, link, count, received)
	if not link then
		return
	end

	local item = ns.StripBrackets(ns.NormalizeLinks(link))
	local multiple = count and count > 1
	local template
	if received then
		template = multiple and ns.out.item_multiple or ns.out.item_single
	else
		template = multiple and ns.out.item_deficit_multiple or ns.out.item_deficit
	end

	local msg = multiple and string_format(template, item, count) or string_format(template, item)
	ns.PrintToChatType(msg, "LOOT")
end

local onAddMessageProxy = function(...)
	return Module:OnAddMessage(...)
end

local onChatEventProxy = function(...)
	return Module:OnChatEvent(...)
end

Module.OnEnable = function(self)
	self:RegisterBlacklistFilter(onAddMessageProxy)
	self:RegisterMessageEventFilter("CHAT_MSG_CURRENCY", onChatEventProxy)
	self:RegisterMessageEventFilter("CHAT_MSG_LOOT", onChatEventProxy)
	self:RegisterMessageEventFilter("CHAT_MSG_SYSTEM", onChatEventProxy)

	-- Track vendor sales so they show a "- item" line (see ReportItemSold).
	-- Right-clicking a bag item while the merchant window is open sells it.
	-- hooksecurefunc is a SECURE post-hook: Blizzard's function is never
	-- replaced, so using items stays untainted. The item removal is
	-- server-confirmed (async), so the item is still in the slot during the
	-- post-hook; we capture it there, then poll to confirm the sale.
	if not self.merchantHooked and C_Container and C_Container.UseContainerItem then
		self.merchantHooked = true
		hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
			if not Module:IsEnabled() then
				return
			end
			if ns.db and not ns.db.showVendorSales then
				return
			end
			if not MerchantFrame or not MerchantFrame:IsShown() then
				return
			end

			-- Capture the item (still present -- removal is async).
			local link = ns.GetContainerItemLink(bag, slot)
			if not link then
				return
			end
			local countBefore = ns.GetContainerItemCount(bag, slot) or 1

			-- POLL the slot until it changes, then report. If after ~1s it
			-- never changed, the vendor rejected the item (unsellable) so we
			-- report nothing -- no false positive.
			local attempts = 0
			local function check()
				attempts = attempts + 1
				local linkAfter = ns.GetContainerItemLink(bag, slot)
				local countAfter = ns.GetContainerItemCount(bag, slot) or 0

				if not linkAfter then
					-- Slot empty = sold the whole stack
					Module:ReportItemSold(link, countBefore)
				elseif linkAfter == link and countAfter < countBefore then
					-- Same item, fewer of them = sold part of the stack
					Module:ReportItemSold(link, countBefore - countAfter)
				elseif attempts < 12 then
					-- Bag not updated yet, keep polling
					C_Timer.After(0.1, check)
				end
			end
			C_Timer.After(0.05, check)
		end)
	end

	-- Mail attachments (see ReportMailItem). Secure post-hook, no taint.
	if not self.mailHooked and type(TakeInboxItem) == "function" then
		self.mailHooked = true
		hooksecurefunc("TakeInboxItem", function(mailID, attachIndex)
			if Module:IsEnabled() then
				Module:ReportMailItem(mailID, attachIndex)
			end
		end)
	end

	-- Track item destruction so it shows a "- item" line.
	-- The original overwrote the DELETE_ITEM popups' OnAccept, which taints the
	-- (protected) delete on the modern client. Instead: DELETE_ITEM_CONFIRM
	-- fires when the confirmation popup opens, while the item is still on the
	-- cursor -- remember it there; a secure post-hook on DeleteCursorItem then
	-- reports it once the deletion actually ran.
	if not self.deleteHooked then
		self.deleteHooked = true

		local pendingDelete

		local watcher = CreateFrame("Frame")
		watcher:RegisterEvent("DELETE_ITEM_CONFIRM")
		watcher:SetScript("OnEvent", function()
			pendingDelete = nil
			local infoType, itemId, itemLink = GetCursorInfo()
			if infoType == "item" then
				local link = itemLink
				if type(link) ~= "string" or not string_find(link, "|H", 1, true) then
					link = itemId and select(2, ns.GetItemInfo(itemId)) or nil
				end
				pendingDelete = link
			end
		end)

		if type(DeleteCursorItem) == "function" then
			hooksecurefunc("DeleteCursorItem", function()
				local link = pendingDelete
				pendingDelete = nil
				if not link or not Module:IsEnabled() then
					return
				end
				if ns.db and not ns.db.showItemDestruction then
					return
				end
				Module:ReportItemSold(link, 1)
			end)
		end
	end

	-- Trades emit no loot line, so report items that change hands. The trade slots
	-- are cleared by TRADE_CLOSED, so snapshot them on each accept-state change
	-- (window still open) and emit once the trade completes (both sides accepted).
	if not self.tradeHooked then
		self.tradeHooked = true

		local pending, playerAccepted, targetAccepted

		local function snapshotTrade()
			local received, given = {}, {}
			for i = 1, (MAX_TRADABLE_ITEMS or 6) do
				local rlink = GetTradeTargetItemLink and GetTradeTargetItemLink(i)
				if rlink then
					local _, _, rcount = GetTradeTargetItemInfo(i)
					received[#received + 1] = { link = rlink, count = rcount or 1 }
				end
				local glink = GetTradePlayerItemLink and GetTradePlayerItemLink(i)
				if glink then
					local _, _, gcount = GetTradePlayerItemInfo(i)
					given[#given + 1] = { link = glink, count = gcount or 1 }
				end
			end
			pending = { received = received, given = given }
		end

		local frame = CreateFrame("Frame")
		frame:RegisterEvent("TRADE_SHOW")
		frame:RegisterEvent("TRADE_ACCEPT_UPDATE")
		frame:RegisterEvent("TRADE_CLOSED")
		frame:SetScript("OnEvent", function(_, event, arg1, arg2)
			if event == "TRADE_SHOW" then
				pending, playerAccepted, targetAccepted = nil, nil, nil
			elseif event == "TRADE_ACCEPT_UPDATE" then
				playerAccepted, targetAccepted = arg1, arg2
				snapshotTrade()
			elseif event == "TRADE_CLOSED" then
				local report = Module:IsEnabled() and ns.db and ns.db.showTradeItems
				if report and pending and playerAccepted == 1 and targetAccepted == 1 then
					for _, e in ipairs(pending.received) do
						Module:ReportTradeItem(e.link, e.count, true)
					end
					for _, e in ipairs(pending.given) do
						Module:ReportTradeItem(e.link, e.count, false)
					end
				end
				pending, playerAccepted, targetAccepted = nil, nil, nil
			end
		end)
	end
end

Module.OnDisable = function(self)
	self:UnregisterBlacklistFilter(onAddMessageProxy)
	self:UnregisterMessageEventFilter("CHAT_MSG_CURRENCY", onChatEventProxy)
	self:UnregisterMessageEventFilter("CHAT_MSG_LOOT", onChatEventProxy)
	self:UnregisterMessageEventFilter("CHAT_MSG_SYSTEM", onChatEventProxy)
end
