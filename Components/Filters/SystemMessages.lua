local _, ns = ...

local Module = ns:NewModule("SystemMessages")

-- Lua API
local string_find = string.find

-- LANGUAGE NOTE: unlike every other filter in Limpid, this one cannot build its
-- patterns from a client global string, because the line it targets is not a
-- Blizzard message -- it is the server's own "Session started" banner and the
-- client exposes no constant for it. It is therefore matched literally and only
-- works on an English server greeting. Everything else this module used to drop
-- has been removed rather than guessed at (see below).
local SESSION_START = "Session started"

-- True for the one repetitive banner this filter exists to hide.
--
-- The previous version also dropped any system line containing both "AddOn" and
-- "loaded". Nothing in the client produces such a line, the options text never
-- promised it, and it silently swallowed OTHER addons' startup messages, which
-- is exactly the kind of thing a chat addon must not do. It is gone.
local function isSessionBanner(text)
	return string_find(text, SESSION_START, 1, true) ~= nil
end

-- Filter system message spam
Module.OnAddMessage = function(_, _, msg)
	if type(msg) ~= "string" then
		return
	end

	if isSessionBanner(msg) then
		return true
	end
end

local onAddMessageProxy = function(...)
	return Module:OnAddMessage(...)
end

Module.OnChatEvent = function(_, _, _, message)
	if type(message) ~= "string" then
		return
	end

	if isSessionBanner(message) then
		return true -- Suppress message
	end
end

-- Proxy function for message event filter
local onChatEventProxy = function(...)
	return Module:OnChatEvent(...)
end

Module.OnEnable = function(self)
	self:RegisterBlacklistFilter(onAddMessageProxy)
	self:RegisterMessageEventFilter("CHAT_MSG_SYSTEM", onChatEventProxy)
end

Module.OnDisable = function(self)
	self:UnregisterBlacklistFilter(onAddMessageProxy)
	self:UnregisterMessageEventFilter("CHAT_MSG_SYSTEM", onChatEventProxy)
end
