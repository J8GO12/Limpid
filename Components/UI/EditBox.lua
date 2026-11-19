local Core, Constants, Utils = unpack(select(2, ...))

local LSM = Core.Libs.LSM

local Colors = Constants.COLORS

local EDIT_FOCUS_GAINED = Constants.EVENTS.EDIT_FOCUS_GAINED
local EDIT_FOCUS_LOST = Constants.EVENTS.EDIT_FOCUS_LOST
local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

-- luacheck: push ignore 113
local hooksecurefunc = hooksecurefunc
-- luacheck: pop

----
-- EditBox
--
-- LimpidUI restyles and repositions the game's own chat edit box
-- (ChatFrame1EditBox) instead of creating a new one, so everything Blizzard's
-- chat input does (history, auto-complete, slash commands, sticky channels)
-- keeps working.
--
-- Forever port: the edit box is the most taint-sensitive piece of the chat UI.
-- Commands typed into it (/cast, /target, /use ...) only work while its code
-- path stays secure. The 3.3.5 version mixed its own methods into the frame,
-- replaced its focus scripts and raw-hooked SetTextInsets; any of those would
-- taint the box on the modern client. This version therefore:
--   * keeps ALL of its own state on a separate controller table (below), so no
--     state field of ours is ever added to the Blizzard frame;
--   * only uses secure post-hooks (HookScript / hooksecurefunc). Be precise
--     about what that means: hooksecurefunc(frame, "SetTextInsets", ...) DOES
--     replace that method on the frame. It is the sanctioned wrapper rather
--     than a raw hook, but it is the one Blizzard-frame field this file
--     writes, and it runs inside the client's own header-update call;
--   * only calls plain layout/skin methods (SetParent, SetPoint, SetFont,
--     texture alpha) on the frame.
local EditBox = {}
EditBox.__index = EditBox

local SetSolidColor = Utils.SetSolidColor

local function GetFontHeight(fontString)
	local height = fontString:GetLineHeight()
	if type(height) == "number" and height > 0 then
		return height
	end
	return 14
end

-- Anchor the frame above or below a window container, per the profile.
function EditBox:Anchor(parent)
	local frame = self.frame
	frame:ClearAllPoints()
	frame:SetWidth(self.profile.frameWidth)
	-- Offset by -1 to compensate for the native edit box's inherent left offset
	if self.profile.editBoxAnchor.position == "ABOVE" then
		frame:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", -1, self.profile.editBoxAnchor.yOfs)
	else
		frame:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", -1, self.profile.editBoxAnchor.yOfs)
	end
end

-- Height + text insets derived from the current font.
function EditBox:UpdateLayout()
	local frame = self.frame
	local lineHeight = GetFontHeight(frame.header)
	self.yPadding = lineHeight * Constants.EDITBOX_PADDING_RATIO
	frame:SetHeight(lineHeight + self.yPadding * 2)
	self:ApplyTextInsets()
end

-- Usable width of a header FontString, or nil when it can't be measured.
--
-- GetWidth() is the LAID-OUT width: the client clamps a long chat-type header
-- to part of the edit box and shows the suffix ("...") to mark the cut.
-- GetStringWidth() returns the full untruncated text width instead, so using it
-- made the left inset far wider than the header actually drawn -- on a long
-- channel name the inset could reach the right edge and the text being typed
-- disappeared. Falls back to the string width only when the frame has no laid
-- out width yet.
local function HeaderWidth(fontString)
	if not fontString then
		return nil
	end
	local width = fontString:GetWidth()
	if type(width) ~= "number" or Utils.IsSecret(width) or width <= 0 then
		width = fontString:GetStringWidth()
	end
	if type(width) ~= "number" or Utils.IsSecret(width) then
		return nil
	end
	return width
end

-- Re-apply LimpidUI' text insets (left inset = width of the channel header).
-- Blizzard calls SetTextInsets itself every time the header changes; the
-- secure post-hook installed in Init routes those calls here. The guard stops
-- our own SetTextInsets call from re-entering through the same hook.
function EditBox:ApplyTextInsets()
	if self.applyingInsets then
		return
	end
	local frame = self.frame
	local header = frame.header

	local left = 8
	if header and header:IsShown() then
		local width = HeaderWidth(header)
		if width then
			left = left + width

			local suffix = frame.headerSuffix
			if suffix and suffix:IsShown() then
				left = left + (HeaderWidth(suffix) or 0)
			end
		else
			-- Header width unreadable (it is a secret value for whisper targets
			-- during chat lockdown). Keep whatever inset is in place rather than
			-- applying a bare 8, which drew the typed text on top of the header.
			return
		end
	end

	-- Never let the header push the text off the box: leave room to type.
	local frameWidth = frame:GetWidth()
	if type(frameWidth) == "number" and not Utils.IsSecret(frameWidth) and frameWidth > 0 then
		local maxLeft = frameWidth - 8 - 40
		if maxLeft > 8 and left > maxLeft then
			left = maxLeft
		end
	end

	local y = self.yPadding or 0
	self.applyingInsets = true
	frame:SetTextInsets(left, 8, y, y)
	self.applyingInsets = false
end

function EditBox:Init(parent)
	local frame = self.frame

	-- Reparent the edit box out of the native chat frame: ChatFrame1 is
	-- hidden (see UIManager), and a child of a hidden frame cannot render.
	-- The fields chat code relies on (editBox.chatFrame, ChatFrame1.editBox)
	-- are not affected by SetParent.
	frame:SetParent(parent)
	frame:SetFrameStrata("LOW")
	self:Anchor(parent)

	frame:SetFontObject("LimpidUIEditBoxFont")
	frame.header:SetFontObject("LimpidUIEditBoxFont")
	frame.header:ClearAllPoints()
	frame.header:SetPoint("LEFT", 8, 0)
	if frame.prompt then
		frame.prompt:SetFontObject("LimpidUIEditBoxFont")
	end

	-- Apply per-window font settings directly
	self:UpdateFontFromProfile()

	-- Our own background (a new texture region: adding one doesn't touch any
	-- Blizzard field of the frame).
	self.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	self.bg:SetAllPoints()
	self:UpdateBackgroundFromProfile()

	-- Strip the native skin: the left/mid/right border slices and their gold
	-- "focus" twins. Blizzard only ever Show()s/Hide()s and re-tints these, so
	-- zero alpha keeps them invisible for good without hooking anything.
	for _, region in ipairs({ frame:GetRegions() }) do
		if region ~= self.bg and region.GetObjectType and region:GetObjectType() == "Texture" then
			region:SetAlpha(0)
		end
	end

	self:UpdateLayout()

	-- Blizzard re-computes the insets whenever the channel header changes.
	-- Post-hook (secure) and put ours back.
	hooksecurefunc(frame, "SetTextInsets", function()
		self:ApplyTextInsets()
	end)

	-- Focus tracking (secure post-hooks: the native handlers run untouched).
	-- We always dispatch so the scroll overlay can hide itself while the edit
	-- box covers that area; the message reveal itself stays gated by
	-- showOnEditFocus inside the listeners.
	frame:HookScript("OnEditFocusGained", function()
		Core:Dispatch(EDIT_FOCUS_GAINED, self.window)
	end)
	frame:HookScript("OnEditFocusLost", function()
		Core:Dispatch(EDIT_FOCUS_LOST, self.window)
	end)

	Core:Subscribe(UPDATE_CONFIG, function(payload)
		local key = Core:ResolveConfigKey(payload, self.window and self.window.id or "Main")

		if key == nil then
			return
		end

		if key == "editBoxFont" or key == "editBoxFontSize" or key == "editBoxFontFlags" then
			self:UpdateFontFromProfile()
			self:UpdateLayout()
		end

		if key == "frameWidth" then
			frame:SetWidth(self.profile.frameWidth)
		end

		if key == "editBoxBackgroundOpacity" or key == "editBoxBackgroundColor" then
			self:UpdateBackgroundFromProfile()
		end

		if key == "editBoxAnchor" then
			-- Anchor relative to whichever window container the box is currently
			-- attached to (it follows the active window), not the original parent.
			self:Anchor(frame:GetParent() or parent)
		end
	end)
end

-- Re-attach the edit box to a different window's container (multi-window). The
-- single edit box "follows" the active window: clicking a window makes ENTER
-- open the box under that window and target that window for focus reveals.
function EditBox:AttachToWindow(parent, profile, window)
	self.profile = profile or self.profile
	self.window = window

	self.frame:SetParent(parent)
	self:Anchor(parent)

	-- Apply the new window's visual settings
	self:UpdateFontFromProfile()
	self:UpdateBackgroundFromProfile()
	self:UpdateLayout()
end

---
-- Apply font settings from the current window's profile directly.
function EditBox:UpdateFontFromProfile()
	local frame = self.frame
	local fontPath = LSM:Fetch(LSM.MediaType.FONT, self.profile.editBoxFont)
	local fontSize = self.profile.editBoxFontSize
	local fontFlags = self.profile.editBoxFontFlags

	if fontPath and fontSize then
		frame:SetFont(fontPath, fontSize, fontFlags or "")
		-- Match the chat messages' drop shadow so the same font flags render
		-- consistently in both places.
		frame:SetShadowColor(0, 0, 0, 1)
		frame:SetShadowOffset(1, -1)
		-- Listed one by one rather than walked with ipairs: ipairs stops at the
		-- first nil, so a client without `headerSuffix` would have silently left
		-- `prompt` on the old font.
		for _, fontString in next, { header = frame.header, suffix = frame.headerSuffix, prompt = frame.prompt } do
			fontString:SetFont(fontPath, fontSize, fontFlags or "")
			fontString:SetShadowColor(0, 0, 0, 1)
			fontString:SetShadowOffset(1, -1)
		end
	end
end

---
-- Apply background settings from the current window's profile.
function EditBox:UpdateBackgroundFromProfile()
	if not self.bg then
		return
	end
	local color = self.profile.editBoxBackgroundColor or Colors.codGray
	local opacity = self.profile.editBoxBackgroundOpacity or 0.6
	SetSolidColor(self.bg, color.r, color.g, color.b, opacity)
end

-- Thin pass-throughs used by the rest of LimpidUI.
function EditBox:HasFocus()
	return self.frame:HasFocus()
end

function EditBox:SetFocus()
	self.frame:SetFocus()
end

function EditBox:ClearFocus()
	self.frame:ClearFocus()
end

Core.Components.CreateEditBox = function(parent, profile)
	local object = setmetatable({
		frame = _G.ChatFrame1EditBox,
		profile = profile or Core.db.profile,
	}, EditBox)
	object:Init(parent)
	return object
end
