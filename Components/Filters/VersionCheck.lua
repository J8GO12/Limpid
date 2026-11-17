local Addon, ns = ...

local Module = ns:NewModule("VersionCheck", "AceEvent-3.0")

-- Lua API
local tonumber = tonumber
local string_match = string.match
local string_format = string.format
local string_gsub = string.gsub
local type = type

-- WoW API
local CreateFrame = CreateFrame
local GetTime = GetTime
local IsInGroup = IsInGroup
local IsInGuild = IsInGuild
local IsInRaid = IsInRaid

-- Addon message prefix (max 16 chars)
local ADDON_PREFIX = "Limpid"

-- Current version from TOC
local CURRENT_VERSION = ns.GetAddOnMetadata("Version") or "0.0"

-- State
local hasNotifiedThisSession = false
local highestVersionSeen = CURRENT_VERSION
local lastBroadcastTime = 0
local lastGuildSendTime = 0
local BROADCAST_THROTTLE = 60 -- seconds between broadcasts
local GUILD_THROTTLE = 300 -- seconds between guild-only pings

-- Parse version string to comparable number (e.g., "2.12" -> 212, "2.9" -> 209)
local function ParseVersion(versionStr)
	if not versionStr then
		return 0
	end
	local major, minor = string_match(versionStr, "^(%d+)%.(%d+)")
	if major and minor then
		return tonumber(major) * 100 + tonumber(minor)
	end
	-- Try single number
	local single = string_match(versionStr, "^(%d+)")
	if single then
		return tonumber(single) * 100
	end
	return 0
end

-- Compare two version strings, returns true if v1 > v2
local function IsNewerVersion(v1, v2)
	return ParseVersion(v1) > ParseVersion(v2)
end

-- Bare "major.minor" of our own version (the TOC version carries a
-- "-forever" suffix that must not go over the wire).
local WIRE_VERSION = string_match(CURRENT_VERSION, "^(%d+%.%d+)") or "0.0"

-- Send version to a channel.
-- Addon messages are refused by the client during chat-messaging lockdown
-- (boss encounters etc.); skip instead of triggering a blocked call.
local function SendVersion(channel)
	if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
		return
	end
	if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
		return
	end
	pcall(C_ChatInfo.SendAddonMessage, ADDON_PREFIX, WIRE_VERSION, channel)
end

-- Broadcast version to all available channels
local function BroadcastVersion()
	-- Throttle broadcasts to prevent spam
	local now = GetTime()
	if now - lastBroadcastTime < BROADCAST_THROTTLE then
		return
	end
	lastBroadcastTime = now

	-- Guild
	if IsInGuild() then
		lastGuildSendTime = now
		SendVersion("GUILD")
	end

	-- Instance group (battlegrounds, dungeon finder), else raid, else party.
	if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		SendVersion("INSTANCE_CHAT")
	elseif IsInRaid() then
		SendVersion("RAID")
	elseif IsInGroup() then
		SendVersion("PARTY")
	end
end

-- Handle incoming version messages
local function OnAddonMessage(prefix, message, _channel, _sender)
	-- Addon message payloads can be secret values on this client.
	if ns.AnySecret(prefix, message) then
		return
	end
	if prefix ~= ADDON_PREFIX then
		return
	end
	if type(message) ~= "string" or message == "" then
		return
	end

	local incomingVersion = string_gsub(message, "%s+", "") -- trim whitespace

	-- Reject anything that isn't a bare "major.minor" version. This is untrusted
	-- input from another player's addon message; without this, a crafted version
	-- string (e.g. one containing |H links or |c colour codes) would be stored
	-- and later printed straight into the user's chat frame.
	if not string_match(incomingVersion, "^%d+%.%d+$") then
		return
	end

	-- Check if this is a newer version than we've seen
	if IsNewerVersion(incomingVersion, highestVersionSeen) then
		highestVersionSeen = incomingVersion
	end

	-- Notify user once per session if they're outdated
	if not hasNotifiedThisSession and IsNewerVersion(highestVersionSeen, CURRENT_VERSION) then
		hasNotifiedThisSession = true

		-- Print update notification to chat
		local msg = string_format(
			"|cffDFBA69Limpid|r: Update available! You have |cffFF6666v%s|r, latest is |cff66FF66v%s|r",
			CURRENT_VERSION,
			highestVersionSeen
		)
		DEFAULT_CHAT_FRAME:AddMessage(msg)
	end
end

function Module:OnEnable()
	if self.eventFrame then
		return
	end

	-- The prefix must be registered to receive CHAT_MSG_ADDON on this client.
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, ADDON_PREFIX)
	end

	-- Create event frame for addon messages
	local eventFrame = CreateFrame("Frame")
	eventFrame:RegisterEvent("CHAT_MSG_ADDON")
	eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
	eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")

	eventFrame:SetScript("OnEvent", function(_frame, event, ...)
		if event == "CHAT_MSG_ADDON" then
			OnAddonMessage(...)
		elseif event == "PLAYER_ENTERING_WORLD" then
			-- Delay broadcast slightly to ensure channels are ready
			C_Timer.After(5, BroadcastVersion)
		elseif event == "GROUP_ROSTER_UPDATE" then
			-- Send version when joining a group
			BroadcastVersion()
		elseif event == "GUILD_ROSTER_UPDATE" then
			-- Send version to guild occasionally (roster updates fire often).
			local now = GetTime()
			if IsInGuild() and (now - lastGuildSendTime) >= GUILD_THROTTLE then
				lastGuildSendTime = now
				SendVersion("GUILD")
			end
		end
	end)

	-- Store reference
	self.eventFrame = eventFrame
end

-- Expose current version for other modules
Module.GetVersion = function()
	return CURRENT_VERSION
end

Module.GetHighestVersionSeen = function()
	return highestVersionSeen
end
