local _, ns = ...

-- Lua API
local ipairs = ipairs
local rawget = rawget
local rawset = rawset
local setmetatable = setmetatable
local string_find = string.find
local string_gsub = string.gsub
local string_match = string.match
local tonumber = tonumber
local type = type

-- GLOBALS: UnitExists, UnitIsPlayer, UnitName, UnitClass

-- Converts a WoW global string (containing %d / %s tokens) into a Lua
-- search pattern with capture groups.
--
-- Forever port: the modern client's strings contain Lua pattern magic
-- characters ("[Loot]", "(Honorable Kill: %s)", "+%d", ...), so everything
-- that isn't a format token is now escaped. Format tokens become captures:
--   %s, %1$s      -> (.+)
--   %d, %2$d      -> (%d+)
--   %.1f          -> ([%d%.,]+)
--   %%            -> a literal percent sign
-- Captures are returned in the order they appear in the text (positional
-- "%2$s" indexes are dropped), which is what the callers expect.
local MAGIC = "[%(%)%.%+%-%*%?%[%]%^%$]"
ns.MakePattern = function(msg)
	if (not msg) or (msg == "") then
		return nil
	end
	-- Hide the format tokens behind control characters so escaping the rest
	-- can't touch them.
	msg = string_gsub(msg, "%%%%", "\001")
	msg = string_gsub(msg, "%%%d+%$", "%%")
	msg = string_gsub(msg, "%%[%d%.]*([dsf])", function(kind)
		if kind == "d" then
			return "\002"
		elseif kind == "s" then
			return "\003"
		end
		return "\004"
	end)
	-- Any stray "%" left (unknown token) is a literal percent sign.
	msg = string_gsub(msg, "%%", "\001")
	msg = string_gsub(msg, MAGIC, "%%%0")
	msg = string_gsub(msg, "\001", "%%%%")
	msg = string_gsub(msg, "\002", "(%%d+)")
	msg = string_gsub(msg, "\003", "(.+)")
	msg = string_gsub(msg, "\004", "([%%d%%.,]+)")
	return msg
end

-- Item quality colours. Since patch 11.1.5 (and therefore on Forever) item
-- links are coloured with a NAMED colour token, "|cnIQ<quality>:[Item]|r",
-- instead of a hex code. The filters were written around "|cAARRGGBB", so
-- chat text is normalised to hex first -- which also applies Limpid's own
-- quality palette, replacing the old QualityColors hex swap.
local qualityHex = {}
ns.GetQualityColorCode = function(quality)
	quality = tonumber(quality)
	local code = quality and qualityHex[quality]
	if code then
		return code
	end
	local colors = ns.Colors
	local color = colors and colors.quality and quality and colors.quality[quality]
	if color and color.colorCode then
		qualityHex[quality] = color.colorCode
		return color.colorCode
	end
	return "|cffffffff"
end

ns.NormalizeLinks = function(msg)
	if type(msg) ~= "string" or not string_find(msg, "|cnIQ", 1, true) then
		return msg
	end
	return (string_gsub(msg, "|cnIQ(%d+):", ns.GetQualityColorCode))
end

-- Returns a self-populating pattern cache. Indexing it with a WoW global string
-- lazily compiles (via ns.MakePattern) and memoizes the resulting search
-- pattern. Replaces the identical setmetatable boilerplate that was duplicated
-- in every filter module.
ns.MakePatternCache = function()
	return setmetatable({}, {
		__index = function(t, k)
			if (k == nil) or (k == "") then
				return nil
			end
			rawset(t, k, ns.MakePattern(k))
			return rawget(t, k)
		end,
	})
end

-- Pattern match that tolerates a nil pattern (returns nil instead of erroring),
-- e.g. when a WoW global string doesn't exist on this client.
ns.SafeMatch = function(msg, pattern)
	if (not pattern) or (type(msg) ~= "string") or ns.IsSecret(msg) then
		return nil
	end
	return string_match(msg, pattern)
end

-- Strip the surrounding [ and ] from an item/spell link's display name while
-- keeping the |H...|h hyperlink and its colour intact. (Also strips stray "/"
-- for parity with the original inline gsub used across the filters.)
ns.StripBrackets = function(s)
	if not s then
		return s
	end
	return (string_gsub(s, "[%[/%]]", ""))
end

-- Class-colour a player name via any unit that currently matches it:
-- your char, the target/focus/mouseover chain, party, raid.
-- Returns the name unchanged when the class can't be resolved.
local classColorUnits

-- Unit names can be secret on Forever (restricted contexts); never compare those.
local function sameName(unitName, name)
	if ns.IsSecret(unitName) or type(unitName) ~= "string" then
		return false
	end
	if unitName == name then
		return true
	end
	-- Chat messages name cross-realm players as "Name-Realm".
	return string_match(name, "^([^%-]+)%-") == unitName
end

ns.GetClassColoredName = function(name)
	if (not name) or (name == "") then
		return name
	end
	local colors = ns.Colors
	if (not colors) or not colors.class then
		return name
	end
	if not classColorUnits then
		classColorUnits = { "player", "target", "targettarget", "focus", "focustarget", "mouseover" }
		for i = 1, 4 do
			classColorUnits[#classColorUnits + 1] = "party" .. i
		end
		for i = 1, 40 do
			classColorUnits[#classColorUnits + 1] = "raid" .. i
		end
	end
	for _, unit in ipairs(classColorUnits) do
		if UnitExists(unit) and UnitIsPlayer(unit) and sameName(UnitName(unit), name) then
			local _, class = UnitClass(unit)
			local color = class and colors.class[class]
			if color and color.colorCode then
				return color.colorCode .. name .. "|r"
			end
		end
	end
	return name
end

-- Emit a message to a chat frame using the colour WoW normally uses for the
-- given chat type (e.g. "LOOT", "MONEY"), falling back to the frame default.
-- Centralizes the ChatTypeInfo lookup + AddMessage pattern that was duplicated
-- across the loot, money and reputation modules.
ns.PrintToFrame = function(chatFrame, msg, chatType)
	if (not chatFrame) or not chatFrame.AddMessage or not msg then
		return
	end
	local info = chatType and ChatTypeInfo and ChatTypeInfo[chatType]
	if info then
		chatFrame:AddMessage(msg, info.r, info.g, info.b)
	else
		chatFrame:AddMessage(msg)
	end
end

-- Emit a line Limpid invented itself (a vendor sale, a mail or trade item, a
-- synthesized quest status) to every chat window that is set to show the
-- matching category.
--
-- These lines have no Blizzard chat event behind them, so nothing else routes
-- them: they used to be written straight into the default window, which ignored
-- the per-window chat settings completely. A category the user hid still turned
-- up in the General tab, and a category moved to its own tab still printed into
-- the main one.
--
-- `chatType` picks the colour, `group` the category to look for (defaults to
-- chatType). When no window shows the category, nothing is printed: that is the
-- user having hidden it. The default window is used only when the client does
-- not expose the per-window category API at all.
ns.PrintToChatType = function(msg, chatType, group)
	if not msg then
		return
	end
	group = group or chatType

	local primary = _G.ChatFrame1
	if (not group) or not (primary and primary.ContainsMessageGroup) then
		ns.PrintToFrame(_G.DEFAULT_CHAT_FRAME or primary, msg, chatType)
		return
	end

	local count = _G.NUM_CHAT_WINDOWS or 10
	for i = 1, count do
		local frame = _G["ChatFrame" .. i]
		if frame and frame.ContainsMessageGroup and frame:ContainsMessageGroup(group) then
			ns.PrintToFrame(frame, msg, chatType)
		end
	end
end

-- Creates a per-chat-frame batching buffer. Bursts of events that fire within
-- the same frame (e.g. a quest turn-in) are collected per chat frame and
-- flushed once on the next frame. `newState()` returns a fresh accumulator;
-- `flush(chatFrame, state)` consumes it. Returns a table with:
--   .Get(chatFrame)      -> the current accumulator (created on demand)
--   .Schedule(chatFrame) -> arrange a next-frame flush (idempotent per frame)
-- The accumulator is cleared *before* flush runs, so output produced during the
-- flush safely starts a new batch.
ns.CreateFrameBuffer = function(newState, flush)
	local buffers = {}

	local function get(chatFrame)
		local buf = buffers[chatFrame]
		if not buf then
			buf = newState()
			buf.scheduled = false
			buffers[chatFrame] = buf
		end
		return buf
	end

	local function schedule(chatFrame)
		local buf = get(chatFrame)
		if buf.scheduled then
			return
		end
		buf.scheduled = true

		local function run()
			local b = buffers[chatFrame]
			if not b then
				return
			end
			-- Reset before flushing so anything printed during the flush starts a
			-- fresh batch instead of mutating the one being drained.
			buffers[chatFrame] = nil
			flush(chatFrame, b)
		end

		C_Timer.After(0, run)
	end

	return { Get = get, Schedule = schedule }
end
