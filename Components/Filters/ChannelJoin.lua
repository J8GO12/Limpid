local _, ns = ...

local Module = ns:NewModule("Channeljoin")

-- Lua API
local ipairs = ipairs
local string_find = string.find
local string_gsub = string.gsub
local string_match = string.match
local string_sub = string.sub
local type = type

-- Localized notice prefixes, taken from the client's own strings so the
-- filter works in every language:
--   "Joined Channel: |Hchannel:%d|h[%s]|h"  -> "Joined Channel:"
local prefixes = {}
for _, global in ipairs({
	"CHAT_YOU_JOINED_NOTICE",
	"CHAT_YOU_LEFT_NOTICE",
	"CHAT_YOU_CHANGED_NOTICE",
	"CHAT_YOU_JOINED_NOTICE_BN",
	"CHAT_YOU_LEFT_NOTICE_BN",
	"CHAT_YOU_CHANGED_NOTICE_BN",
}) do
	local str = _G[global]
	local prefix = type(str) == "string" and string_match(str, "^(.-)|H")
	if prefix and prefix ~= "" then
		prefixes[prefix] = true
	end
end

-- True if the line is a channel join/leave/change NOTICE (not player chat).
-- Anchored to the start of the line (after stripping any leading colour code) so
-- it matches the notice -- e.g. "Left Channel: <channel>" -- but never a normal
-- message that merely mentions the phrase, which renders as "[chan] Sender: ...".
local function isChannelNotice(msg)
	local text = string_gsub(msg, "^|c%x%x%x%x%x%x%x%x", "")
	for prefix in pairs(prefixes) do
		if string_sub(text, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

-- Filter channel join/leave/change notices at the display layer. They carry
-- the CHANNEL's own chat-type id, which is in Limpid's ignoredIDs set, so
-- this is registered as an UNCONDITIONAL blacklist (see ns.FilterMessage).
Module.OnAddMessage = function(_, _, msg)
	if type(msg) ~= "string" then
		return
	end

	if isChannelNotice(msg) then
		return true
	end
end

local onAddMessageProxy = function(...)
	return Module:OnAddMessage(...)
end

-- Filter the actual CHAT_MSG_CHANNEL_NOTICE event.
-- The first argument is the notice type: "YOU_JOINED", "YOU_LEFT", "YOU_CHANGED".
Module.OnChatEvent = function(_, _, _, message)
	if message == "YOU_JOINED" or message == "YOU_LEFT" or message == "YOU_CHANGED" then
		return true
	end
end

local onChatEventProxy = function(...)
	return Module:OnChatEvent(...)
end

Module.OnEnable = function(self)
	self:RegisterUnconditionalBlacklistFilter(onAddMessageProxy)
	self:RegisterMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", onChatEventProxy)
end

Module.OnDisable = function(self)
	self:UnregisterUnconditionalBlacklistFilter(onAddMessageProxy)
	self:UnregisterMessageEventFilter("CHAT_MSG_CHANNEL_NOTICE", onChatEventProxy)
end
