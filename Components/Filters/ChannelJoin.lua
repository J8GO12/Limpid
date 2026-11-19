local _, ns = ...

local Module = ns:NewModule("Channeljoin")

-- Lua API
local ipairs = ipairs
local pairs = pairs
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

-- Strip what the client may put in FRONT of the message text before the notice
-- itself starts: a colour code, and the timestamp the game prepends when the
-- "Timestamps" chat option is on ("09:14:02 ", "[9:14 PM] ", ...). Without this
-- the anchored test below silently stopped matching for anyone using
-- timestamps, so the notices were never hidden.
local function stripLeadingNoise(text)
	text = string_gsub(text, "^|c%x%x%x%x%x%x%x%x", "")
	-- Optional bracket, H:M(:S), optional AM/PM, optional closing bracket.
	text = string_gsub(text, "^[%[%(]?%d+[:%.]%d+[:%.%d]*%s*[AaPp]?%.?[Mm]?%.?[%]%)]?%s+", "")
	return text
end

-- True if the line is a channel join/leave/change NOTICE (not player chat).
-- Anchored to the start of the line (after stripping colour code and timestamp)
-- so it matches the notice -- e.g. "Left Channel: <channel>" -- but never a
-- normal message that merely mentions the phrase, which renders as
-- "[chan] Sender: ...".
local function isChannelNotice(msg)
	local text = stripLeadingNoise(msg)
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

-- NOTE: this filter deliberately does NOT suppress the CHAT_MSG_CHANNEL_NOTICE
-- event itself anymore.
--
-- A message event filter that returns true aborts the client's whole chat
-- handler for that line, and the channel bookkeeping lives inside it: leaving a
-- channel clears the frame's channel entries, and a "changed channel" notice is
-- what re-adds a regional channel whose client-side filter was dropped. Cutting
-- the event therefore left dead channel entries behind after /leave and could
-- make a regional channel stop showing until the next /reload -- while hiding
-- the same text the display filter below already hides.
--
-- Hiding happens purely at the display layer, so the game keeps its channel
-- list correct and other addons still see the event.

Module.OnEnable = function(self)
	self:RegisterUnconditionalBlacklistFilter(onAddMessageProxy)
end

Module.OnDisable = function(self)
	self:UnregisterUnconditionalBlacklistFilter(onAddMessageProxy)
end
