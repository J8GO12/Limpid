local _, ns = ...

local Module = ns:NewModule("Auctions")

-- GLOBALS: hooksecurefunc, C_AuctionHouse, C_Item

-- Lua API
local string_format = string.format
local string_gsub = string.gsub
local type = type

-- WoW Globals
local G = {
	AUCTION_REMOVED = ERR_AUCTION_REMOVED, -- "Auction canceled."
	AUCTION_SOLD = ERR_AUCTION_SOLD_S, -- "A buyer has been found for your auction of %s."
	AUCTION_STARTED = ERR_AUCTION_STARTED, -- "Auction created."
	AUCTION_WON = string_gsub(ERR_AUCTION_WON_S or "You won an auction for %s", "%.$", ""), -- "You won an auction for %s"
	BID_PLACED = ERR_AUCTION_BID_PLACED or "Bid accepted.", -- "Bid accepted."
}

-- Search Pattern Cache (self-populating via ns.MakePattern on first lookup).
local P = ns.MakePatternCache()

-- Safe pattern match that tolerates a nil pattern (shared helper).
local safeMatch = ns.SafeMatch

-- Auctions don't carry item info in their "Auction created." system message.
-- Forever uses the modern auction house, where posting goes through
-- C_AuctionHouse.PostItem / PostCommodity with an ItemLocation. Secure
-- post-hooks on those two read the item link + quantity while the item is
-- still in the bag, then the "Auction created." line picks them up.
Module.CacheSellItem = function(self, itemLocation, quantity)
	self.sellItem = nil
	self.postQuantity = nil

	if not itemLocation or not C_Item or not C_Item.GetItemLink then
		return
	end

	local ok, link = pcall(C_Item.GetItemLink, itemLocation)
	if not ok or type(link) ~= "string" then
		return
	end

	self.sellItem = ns.StripBrackets(ns.NormalizeLinks(link))
	self.postQuantity = type(quantity) == "number" and quantity or 1
end

Module.BuildAuctionLine = function(self)
	local item = self.sellItem
	if not item then
		return ns.out.auction_created_generic
	end

	local quantity = self.postQuantity or 1
	-- One post = one "Auction created." line; don't reuse the item for the next.
	self.sellItem = nil
	self.postQuantity = nil

	if quantity > 1 then
		return string_format(ns.out.auction_created_multiple, item, quantity)
	end
	return string_format(ns.out.auction_created_single, item)
end

Module.OnChatEvent = function(self, chatFrame, event, message, author, ...)
	if type(message) ~= "string" or ns:IsProtectedMessage(message) then
		return
	end

	-- The filter runs once per chat frame showing system messages. Build the
	-- detailed line once and reuse it for the other frames in the same tick.
	if message == G.AUCTION_STARTED then
		local now = GetTime()
		if not self.lastLine or self.lastLineAt ~= now then
			self.lastLine = self:BuildAuctionLine()
			self.lastLineAt = now
		end
		return false, self.lastLine, author, ...

	-- Auction cancelled. Show it immediately, per cancellation.
	elseif message == G.AUCTION_REMOVED then
		return false, ns.out.auction_canceled_single, author, ...

	-- Bid accepted (you placed a bid).
	elseif message == G.BID_PLACED then
		return false, ns.out.auction_bid, author, ...
	end

	-- Auction sold (a buyer was found for your auction).
	local item = safeMatch(message, P[G.AUCTION_SOLD])
	if item then
		return false, string_format(ns.out.auction_sold, item), author, ...
	end

	-- Auction won (you bought/won an item).
	local won = safeMatch(message, P[G.AUCTION_WON])
	if won then
		return false, string_format(ns.out.auction_won, ns.StripBrackets(ns.NormalizeLinks(won))), author, ...
	end
end

local onChatEventProxy = function(...)
	return Module:OnChatEvent(...)
end

Module.OnEnable = function(self)
	if not self.auctionHooked and C_AuctionHouse then
		self.auctionHooked = true
		-- PostItem(item, duration, quantity, bid, buyout)
		if C_AuctionHouse.PostItem then
			hooksecurefunc(C_AuctionHouse, "PostItem", function(itemLocation, _, quantity)
				if Module:IsEnabled() then
					Module:CacheSellItem(itemLocation, quantity)
				end
			end)
		end
		-- PostCommodity(item, duration, quantity, unitPrice)
		if C_AuctionHouse.PostCommodity then
			hooksecurefunc(C_AuctionHouse, "PostCommodity", function(itemLocation, _, quantity)
				if Module:IsEnabled() then
					Module:CacheSellItem(itemLocation, quantity)
				end
			end)
		end
	end

	self:RegisterMessageEventFilter("CHAT_MSG_SYSTEM", onChatEventProxy)
end

Module.OnDisable = function(self)
	self:UnregisterMessageEventFilter("CHAT_MSG_SYSTEM", onChatEventProxy)
end
